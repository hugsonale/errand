import hashlib
import hmac
import secrets
import uuid
import httpx
from app.config import settings
from app.core.exceptions import ServiceUnavailableError, BadRequestError

PAYSTACK_BASE = "https://api.paystack.co"
PLATFORM_FEE_RATE = 0.15   # 15% platform commission


class PaystackService:
    """
    Handles all Paystack API interactions.

    Escrow flow:
    1. initiate_charge()  → client pays, money goes to Paystack
    2. webhook confirms   → we mark escrow as HELD
    3. release_to_agent() → we transfer to agent's bank account
    4. refund_to_client() → we issue refund via Paystack
    """

    def _headers(self) -> dict:
        return {
            "Authorization": f"Bearer {settings.PAYSTACK_SECRET_KEY}",
            "Content-Type": "application/json",
        }

    def verify_webhook_signature(self, payload: bytes, signature: str) -> bool:
        """
        Verifies Paystack webhook HMAC-SHA512 signature.
        CRITICAL: Never process webhooks without this check.
        """
        if not settings.PAYSTACK_WEBHOOK_SECRET:
            # Dev mode — skip verification
            return True
        expected = hmac.new(
            settings.PAYSTACK_WEBHOOK_SECRET.encode(),
            payload,
            hashlib.sha512,
        ).hexdigest()
        return hmac.compare_digest(expected, signature)

    def generate_reference(self, task_id: uuid.UUID) -> str:
        """Unique, traceable payment reference."""
        short = secrets.token_hex(6).upper()
        return f"EM-{str(task_id)[:8].upper()}-{short}"

    async def initiate_charge(
        self,
        email: str,
        amount_naira: float,
        task_id: uuid.UUID,
        reference: str,
        metadata: dict | None = None,
    ) -> dict:
        """
        Creates a Paystack payment link.
        Amount is converted to kobo (Paystack uses smallest currency unit).
        """
        amount_kobo = int(amount_naira * 100)

        payload = {
            "email": email or f"client+{str(task_id)[:8]}@errandmarketplace.com",
            "amount": amount_kobo,
            "reference": reference,
            "callback_url": f"https://errandmarketplace.com/payment/callback",
            "metadata": {
                "task_id": str(task_id),
                "platform": "errand_marketplace",
                **(metadata or {}),
            },
            "channels": ["card", "bank", "ussd", "qr", "bank_transfer"],
        }

        if not settings.PAYSTACK_SECRET_KEY:
            # Dev mode — return mock response
            return {
                "authorization_url": f"https://checkout.paystack.com/dev_{reference}",
                "access_code": f"dev_access_{reference}",
                "reference": reference,
            }

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.post(
                    f"{PAYSTACK_BASE}/transaction/initialize",
                    json=payload,
                    headers=self._headers(),
                )
                resp.raise_for_status()
                data = resp.json()
                if not data.get("status"):
                    raise BadRequestError(
                        f"Paystack error: {data.get('message', 'Unknown error')}"
                    )
                return data["data"]
        except httpx.HTTPError as e:
            raise ServiceUnavailableError(f"Paystack unavailable: {e}")

    async def verify_transaction(self, reference: str) -> dict:
        """Verify a transaction by reference — used in webhook processing."""
        if not settings.PAYSTACK_SECRET_KEY:
            return {"status": "success", "amount": 0, "reference": reference}

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.get(
                    f"{PAYSTACK_BASE}/transaction/verify/{reference}",
                    headers=self._headers(),
                )
                resp.raise_for_status()
                data = resp.json()
                return data.get("data", {})
        except httpx.HTTPError as e:
            raise ServiceUnavailableError(f"Paystack verify failed: {e}")

    async def transfer_to_agent(
        self,
        agent_name: str,
        bank_account: str,
        bank_code: str,
        amount_naira: float,
        task_id: uuid.UUID,
    ) -> dict:
        """
        Transfers agent payout to their bank account via Paystack Transfers.
        Requires Paystack Transfer feature enabled on account.
        """
        if not settings.PAYSTACK_SECRET_KEY:
            ref = f"PAY-{str(task_id)[:8].upper()}-{secrets.token_hex(4).upper()}"
            print(f"[DEV PAYOUT] ₦{amount_naira:.2f} → {agent_name} | ref: {ref}")
            return {"transfer_code": ref, "status": "pending"}

        # Step 1: Create transfer recipient
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                recipient_resp = await client.post(
                    f"{PAYSTACK_BASE}/transferrecipient",
                    json={
                        "type": "nuban",
                        "name": agent_name,
                        "account_number": bank_account,
                        "bank_code": bank_code,
                        "currency": "NGN",
                    },
                    headers=self._headers(),
                )
                recipient_resp.raise_for_status()
                recipient_code = recipient_resp.json()["data"]["recipient_code"]

                # Step 2: Initiate transfer
                transfer_resp = await client.post(
                    f"{PAYSTACK_BASE}/transfer",
                    json={
                        "source": "balance",
                        "amount": int(amount_naira * 100),
                        "recipient": recipient_code,
                        "reason": f"Errand payout - task {str(task_id)[:8]}",
                        "reference": f"PAY-{str(task_id)[:8].upper()}-{secrets.token_hex(4).upper()}",
                    },
                    headers=self._headers(),
                )
                transfer_resp.raise_for_status()
                return transfer_resp.json()["data"]
        except httpx.HTTPError as e:
            raise ServiceUnavailableError(f"Paystack transfer failed: {e}")

    async def refund_transaction(self, reference: str, amount_naira: float | None = None) -> dict:
        """Issues a refund for a transaction (full or partial)."""
        if not settings.PAYSTACK_SECRET_KEY:
            print(f"[DEV REFUND] ref={reference} amount={amount_naira}")
            return {"status": "processed"}

        payload: dict = {"transaction": reference}
        if amount_naira:
            payload["amount"] = int(amount_naira * 100)

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.post(
                    f"{PAYSTACK_BASE}/refund",
                    json=payload,
                    headers=self._headers(),
                )
                resp.raise_for_status()
                return resp.json().get("data", {})
        except httpx.HTTPError as e:
            raise ServiceUnavailableError(f"Paystack refund failed: {e}")

    def compute_fees(self, amount: float) -> tuple[float, float]:
        """
        Returns (platform_fee, agent_payout).
        Platform takes 15%, agent receives 85%.
        """
        platform_fee = round(amount * PLATFORM_FEE_RATE, 2)
        agent_payout = round(amount - platform_fee, 2)
        return platform_fee, agent_payout


paystack_service = PaystackService()
