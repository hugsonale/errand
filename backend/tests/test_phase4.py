import pytest
import json
import hashlib
import hmac
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.auth import OTPCode
from app.middleware.security import sanitize_string, mask_phone, mask_sensitive_data
from app.services.paystack_service import paystack_service
from app.websockets.connection_manager import ConnectionManager


# ─── Helpers ──────────────────────────────────────────────────────────────────

async def _create_verified_user(
    client: AsyncClient, db: AsyncSession, phone: str, role: str = "client"
) -> dict:
    await client.post("/api/v1/auth/register", json={
        "full_name": "Phase 4 Test User",
        "phone": phone,
        "password": "SecurePass1",
        "role": role,
    })
    otp_result = await db.execute(
        select(OTPCode).where(OTPCode.phone == phone, OTPCode.used == False)
    )
    otp = otp_result.scalar_one()
    resp = await client.post("/api/v1/auth/verify-phone",
                              json={"phone": phone, "code": otp.code})
    return resp.json()


def _headers(tokens: dict) -> dict:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


# ─── Security middleware tests ────────────────────────────────────────────────

class TestSanitizeString:
    def test_strips_null_bytes(self):
        assert "\x00" not in sanitize_string("hello\x00world")

    def test_respects_max_length(self):
        long_str = "a" * 2000
        result = sanitize_string(long_str, max_length=100)
        assert len(result) == 100

    def test_normalizes_whitespace(self):
        result = sanitize_string("  hello   world  ")
        assert result == "hello world"

    def test_handles_non_string(self):
        assert sanitize_string(123) == 123

    def test_strips_leading_trailing(self):
        assert sanitize_string("  hello  ") == "hello"


class TestMaskPhone:
    def test_masks_nigerian_number(self):
        masked = mask_phone("+2348012345678")
        assert "***" in masked
        assert masked.startswith("+234801")
        assert not masked.endswith("2345678")

    def test_short_phone_returns_stars(self):
        assert mask_phone("123") == "***"

    def test_preserves_prefix(self):
        masked = mask_phone("+2348099999999")
        assert masked.startswith("+234809")


class TestMaskSensitiveData:
    def test_masks_password(self):
        data = {"email": "test@test.com", "password": "secret123"}
        masked = mask_sensitive_data(data)
        assert masked["password"] == "***"
        assert masked["email"] == "test@test.com"

    def test_masks_tokens(self):
        data = {"access_token": "eyJhbGc...", "user": "test"}
        masked = mask_sensitive_data(data)
        assert masked["access_token"] == "***"

    def test_masks_nin(self):
        data = {"nin_number": "12345678901", "name": "Test"}
        masked = mask_sensitive_data(data)
        assert masked["nin_number"] == "***"

    def test_masks_phone(self):
        data = {"phone": "+2348012345678"}
        masked = mask_sensitive_data(data)
        assert "***" in masked["phone"]


# ─── Paystack HMAC verification ───────────────────────────────────────────────

class TestPaystackWebhookSecurity:
    def test_valid_signature_passes(self):
        secret = "test_webhook_secret"
        payload = b'{"event":"charge.success","data":{"reference":"EM-TEST"}}'
        sig = hmac.new(secret.encode(), payload, hashlib.sha512).hexdigest()

        # Monkey-patch settings for this test
        import app.services.paystack_service as ps_module
        original = ps_module.settings.PAYSTACK_WEBHOOK_SECRET

        ps_module.settings.PAYSTACK_WEBHOOK_SECRET = secret
        result = paystack_service.verify_webhook_signature(payload, sig)
        ps_module.settings.PAYSTACK_WEBHOOK_SECRET = original

        assert result is True

    def test_invalid_signature_fails(self):
        secret = "test_webhook_secret"
        payload = b'{"event":"charge.success"}'

        import app.services.paystack_service as ps_module
        original = ps_module.settings.PAYSTACK_WEBHOOK_SECRET
        ps_module.settings.PAYSTACK_WEBHOOK_SECRET = secret

        result = paystack_service.verify_webhook_signature(payload, "wrong_sig")
        ps_module.settings.PAYSTACK_WEBHOOK_SECRET = original

        assert result is False

    def test_empty_secret_passes_in_dev(self):
        """When no webhook secret set (dev mode), all webhooks pass."""
        import app.services.paystack_service as ps_module
        original = ps_module.settings.PAYSTACK_WEBHOOK_SECRET
        ps_module.settings.PAYSTACK_WEBHOOK_SECRET = ""

        result = paystack_service.verify_webhook_signature(b"payload", "any_sig")
        ps_module.settings.PAYSTACK_WEBHOOK_SECRET = original

        assert result is True


# ─── Reference generation ─────────────────────────────────────────────────────

class TestPaystackReference:
    def test_reference_format(self):
        import uuid
        task_id = uuid.uuid4()
        ref = paystack_service.generate_reference(task_id)
        assert ref.startswith("EM-")
        assert len(ref) > 10

    def test_references_are_unique(self):
        import uuid
        task_id = uuid.uuid4()
        refs = {paystack_service.generate_reference(task_id) for _ in range(10)}
        assert len(refs) == 10  # All unique


# ─── WebSocket connection manager ─────────────────────────────────────────────

class TestConnectionManager:
    @pytest.mark.asyncio
    async def test_join_and_leave_room(self):
        manager = ConnectionManager()

        class MockWS:
            async def accept(self): pass
            async def send_text(self, msg): pass

        ws = MockWS()
        await manager.join_task_room("task-123", ws)
        assert "task-123" in manager._task_rooms
        assert ws in manager._task_rooms["task-123"]

        await manager.leave_task_room("task-123", ws)
        assert "task-123" not in manager._task_rooms

    @pytest.mark.asyncio
    async def test_broadcast_to_empty_room(self):
        """Broadcasting to a room with no connections should not raise."""
        manager = ConnectionManager()
        # Should not raise
        await manager.broadcast_location(
            task_id="nonexistent-room",
            lat=6.5244,
            lng=3.3792,
            agent_id="agent-123",
        )

    @pytest.mark.asyncio
    async def test_broadcast_reaches_all_in_room(self):
        manager = ConnectionManager()
        received = []

        class MockWS:
            async def accept(self): pass
            async def send_text(self, msg): received.append(msg)

        ws1, ws2, ws3 = MockWS(), MockWS(), MockWS()
        await manager.join_task_room("task-abc", ws1)
        await manager.join_task_room("task-abc", ws2)
        await manager.join_task_room("task-abc", ws3)

        await manager.broadcast_location("task-abc", 6.5244, 3.3792, "agent-1")

        assert len(received) == 3
        for msg in received:
            data = json.loads(msg)
            assert data["type"] == "location_update"
            assert data["lat"] == 6.5244
            assert data["lng"] == 3.3792

    @pytest.mark.asyncio
    async def test_dead_connection_cleaned_up(self):
        """WebSockets that error on send should be removed from the room."""
        manager = ConnectionManager()
        removed = []

        class DeadWS:
            async def accept(self): pass
            async def send_text(self, msg):
                raise ConnectionError("Client disconnected")

        ws = DeadWS()
        await manager.join_task_room("task-dead", ws)
        await manager.broadcast_location("task-dead", 6.5244, 3.3792, "agent-1")

        # Dead connection should be removed after broadcast
        assert ws not in manager._task_rooms.get("task-dead", set())


# ─── Rate limiting headers ─────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_health_check_no_rate_limit(client: AsyncClient):
    """Health check endpoint should always return 200."""
    for _ in range(5):
        resp = await client.get("/health")
        assert resp.status_code == 200


@pytest.mark.asyncio
async def test_security_headers_present(client: AsyncClient):
    """Every response should include security headers."""
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert "x-content-type-options" in resp.headers
    assert resp.headers["x-content-type-options"] == "nosniff"
    assert "x-frame-options" in resp.headers
    assert resp.headers["x-frame-options"] == "DENY"


@pytest.mark.asyncio
async def test_webhook_invalid_json_rejected(client: AsyncClient):
    """Webhook endpoint should reject malformed JSON."""
    resp = await client.post(
        "/api/v1/payments/webhook",
        content=b"not valid json at all",
        headers={"Content-Type": "application/json"},
    )
    assert resp.status_code in (400, 422)


@pytest.mark.asyncio
async def test_sql_injection_in_search_rejected(client: AsyncClient, db: AsyncSession):
    """SQL injection attempts in query params should be handled safely."""
    tokens = await _create_verified_user(client, db, "+2348030000001", "client")

    # SQLAlchemy parameterized queries prevent injection — this should just return empty results
    resp = await client.get(
        "/api/v1/tasks/",
        params={"category": "'; DROP TABLE tasks; --"},
        headers=_headers(tokens),
    )
    # Should not crash — returns 422 (invalid enum) or 200 with empty results
    assert resp.status_code in (200, 422)


@pytest.mark.asyncio
async def test_extremely_long_input_handled(client: AsyncClient, db: AsyncSession):
    """Very long inputs should be rejected, not cause server errors."""
    tokens = await _create_verified_user(client, db, "+2348030000002", "client")

    resp = await client.post(
        "/api/v1/tasks/",
        json={
            "title": "A" * 10000,  # Way over 200 char limit
            "description": "Test",
            "category": "shopping",
            "budget": 5000,
            "pickup_address": "Lagos",
            "pickup_lat": 6.5244,
            "pickup_lng": 3.3792,
        },
        headers=_headers(tokens),
    )
    assert resp.status_code == 422
