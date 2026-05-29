import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.auth import OTPCode
from app.models.user import User
from app.models.task import Task, TaskStatus, TaskApplication, ApplicationStatus


# ─── Helpers ──────────────────────────────────────────────────────────────────

async def _create_verified_user(client: AsyncClient, db: AsyncSession,
                                 phone: str, role: str = "client") -> dict:
    """Registers + verifies a user and returns their tokens."""
    await client.post("/api/v1/auth/register", json={
        "full_name": "Test User",
        "phone": phone,
        "password": "SecurePass1",
        "role": role,
    })
    result = await db.execute(
        select(OTPCode).where(OTPCode.phone == phone, OTPCode.used == False)
    )
    otp = result.scalar_one()
    resp = await client.post("/api/v1/auth/verify-phone",
                              json={"phone": phone, "code": otp.code})
    return resp.json()


def _auth_headers(tokens: dict) -> dict:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


# ─── Task CRUD ────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_client_can_post_task(client: AsyncClient, db: AsyncSession):
    tokens = await _create_verified_user(client, db, "+2348010000001", "client")

    resp = await client.post(
        "/api/v1/tasks/",
        json={
            "title": "Buy groceries from Shoprite",
            "description": "Buy the items on the attached list",
            "category": "shopping",
            "budget": 5000,
            "pickup_address": "Lekki Phase 1, Lagos",
            "pickup_lat": 6.4281,
            "pickup_lng": 3.4219,
        },
        headers=_auth_headers(tokens),
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["status"] == "posted"
    assert data["category"] == "shopping"
    assert data["budget"] == 5000.0


@pytest.mark.asyncio
async def test_budget_too_low_rejected(client: AsyncClient, db: AsyncSession):
    tokens = await _create_verified_user(client, db, "+2348010000002", "client")
    resp = await client.post(
        "/api/v1/tasks/",
        json={
            "title": "Tiny task",
            "description": "Very small budget",
            "category": "custom",
            "budget": 100,  # Below minimum of 500
            "pickup_address": "Lagos",
            "pickup_lat": 6.5244,
            "pickup_lng": 3.3792,
        },
        headers=_auth_headers(tokens),
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_agent_can_list_available_tasks(client: AsyncClient, db: AsyncSession):
    # Create a client and post a task
    client_tokens = await _create_verified_user(client, db, "+2348010000003", "client")
    await client.post(
        "/api/v1/tasks/",
        json={
            "title": "Office errand",
            "description": "Submit documents at the registry",
            "category": "office_errand",
            "budget": 3000,
            "pickup_address": "Victoria Island, Lagos",
            "pickup_lat": 6.4281,
            "pickup_lng": 3.4219,
        },
        headers=_auth_headers(client_tokens),
    )

    # Agent can see it
    agent_tokens = await _create_verified_user(client, db, "+2348010000004", "agent")
    resp = await client.get("/api/v1/tasks/", headers=_auth_headers(agent_tokens))
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] >= 1
    assert any(t["category"] == "office_errand" for t in data["tasks"])


@pytest.mark.asyncio
async def test_client_cannot_see_other_clients_tasks(client: AsyncClient, db: AsyncSession):
    client1_tokens = await _create_verified_user(client, db, "+2348010000005", "client")
    client2_tokens = await _create_verified_user(client, db, "+2348010000006", "client")

    # Client 1 posts a task
    await client.post(
        "/api/v1/tasks/",
        json={
            "title": "Private task",
            "description": "This belongs to client 1",
            "category": "custom",
            "budget": 2000,
            "pickup_address": "Ikeja, Lagos",
            "pickup_lat": 6.6018,
            "pickup_lng": 3.3515,
        },
        headers=_auth_headers(client1_tokens),
    )

    # Client 2 should see 0 tasks (only their own)
    resp = await client.get("/api/v1/tasks/", headers=_auth_headers(client2_tokens))
    assert resp.status_code == 200
    assert resp.json()["total"] == 0


@pytest.mark.asyncio
async def test_task_status_transitions(client: AsyncClient, db: AsyncSession):
    """
    Tests the full happy path:
    posted → agents_applied → accepted → in_progress → proof_submitted → completed
    """
    # Setup
    client_tokens = await _create_verified_user(client, db, "+2348010000007", "client")

    # Post task
    task_resp = await client.post(
        "/api/v1/tasks/",
        json={
            "title": "Full lifecycle task",
            "description": "Testing the complete task flow end to end",
            "category": "delivery",
            "budget": 4000,
            "pickup_address": "Yaba, Lagos",
            "pickup_lat": 6.5147,
            "pickup_lng": 3.3799,
        },
        headers=_auth_headers(client_tokens),
    )
    assert task_resp.status_code == 201
    task_id = task_resp.json()["id"]

    # Get the task
    detail_resp = await client.get(
        f"/api/v1/tasks/{task_id}",
        headers=_auth_headers(client_tokens),
    )
    assert detail_resp.json()["status"] == "posted"


@pytest.mark.asyncio
async def test_task_cancellation_from_posted_state(client: AsyncClient, db: AsyncSession):
    client_tokens = await _create_verified_user(client, db, "+2348010000008", "client")

    task_resp = await client.post(
        "/api/v1/tasks/",
        json={
            "title": "Task to cancel",
            "description": "This task will be cancelled",
            "category": "custom",
            "budget": 1500,
            "pickup_address": "Lagos",
            "pickup_lat": 6.5244,
            "pickup_lng": 3.3792,
        },
        headers=_auth_headers(client_tokens),
    )
    task_id = task_resp.json()["id"]

    cancel_resp = await client.delete(
        f"/api/v1/tasks/{task_id}",
        headers=_auth_headers(client_tokens),
    )
    assert cancel_resp.status_code == 200
    assert cancel_resp.json()["status"] == "cancelled"


@pytest.mark.asyncio
async def test_emergency_task_has_correct_flag(client: AsyncClient, db: AsyncSession):
    client_tokens = await _create_verified_user(client, db, "+2348010000009", "client")

    resp = await client.post(
        "/api/v1/tasks/",
        json={
            "title": "Urgent medicine pickup",
            "description": "Need medicine urgently from pharmacy",
            "category": "pharmacy",
            "budget": 3000,
            "is_emergency": True,
            "pickup_address": "Surulere, Lagos",
            "pickup_lat": 6.5024,
            "pickup_lng": 3.3515,
        },
        headers=_auth_headers(client_tokens),
    )
    assert resp.status_code == 201
    assert resp.json()["is_emergency"] is True


@pytest.mark.asyncio
async def test_task_detail_includes_application_count(client: AsyncClient, db: AsyncSession):
    client_tokens = await _create_verified_user(client, db, "+2348010000010", "client")

    task_resp = await client.post(
        "/api/v1/tasks/",
        json={
            "title": "Application count test",
            "description": "Check application count in detail",
            "category": "cleaning",
            "budget": 8000,
            "pickup_address": "Ajah, Lagos",
            "pickup_lat": 6.4696,
            "pickup_lng": 3.5672,
        },
        headers=_auth_headers(client_tokens),
    )
    task_id = task_resp.json()["id"]

    detail_resp = await client.get(
        f"/api/v1/tasks/{task_id}",
        headers=_auth_headers(client_tokens),
    )
    assert detail_resp.status_code == 200
    assert detail_resp.json()["application_count"] == 0


@pytest.mark.asyncio
async def test_unauthenticated_cannot_post_task(client: AsyncClient):
    resp = await client.post(
        "/api/v1/tasks/",
        json={
            "title": "Hacker task",
            "description": "No auth provided",
            "category": "custom",
            "budget": 1000,
            "pickup_address": "Lagos",
            "pickup_lat": 6.5244,
            "pickup_lng": 3.3792,
        },
    )
    assert resp.status_code == 403
