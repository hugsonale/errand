import uuid
import json
from fastapi import APIRouter, Depends, Request, Header
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Annotated

from app.database import get_db
from app.schemas.payment import (
    InitiatePaymentResponse,
    PaymentHistoryResponse,
    EscrowTransactionResponse,
)
from app.schemas.auth import SuccessResponse
from app.services.payment_service import payment_service
from app.services.paystack_service import paystack_service
from app.core.dependencies import VerifiedUser, ClientUser, AdminUser
from app.core.exceptions import BadRequestError

router = APIRouter(prefix="/payments", tags=["Payments"])


@router.post(
    "/initiate/{task_id}",
    response_model=InitiatePaymentResponse,
    summary="Initiate escrow payment for a task",
    description=(
        "Creates a Paystack payment link. Client is redirected to the "
        "authorization_url to complete payment. Funds are held in escrow "
        "until the client confirms task completion."
    ),
)
async def initiate_payment(
    task_id: uuid.UUID,
    current_user: ClientUser,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    return await payment_service.initiate_payment(db, current_user, task_id)


@router.post(
    "/webhook",
    include_in_schema=False,
    summary="Paystack webhook receiver",
)
async def paystack_webhook(
    request: Request,
    db: Annotated[AsyncSession, Depends(get_db)],
    x_paystack_signature: str | None = Header(default=None),
):
    """
    Receives verified Paystack events.
    HMAC-SHA512 signature verified before any processing.
    This endpoint must remain public (no auth) — Paystack calls it directly.
    """
    payload = await request.body()

    # Verify signature
    if not paystack_service.verify_webhook_signature(
        payload, x_paystack_signature or ""
    ):
        raise BadRequestError("Invalid webhook signature")

    try:
        body = json.loads(payload)
        event = body.get("event", "")
        data = body.get("data", {})
        await payment_service.handle_webhook(db, event, data)
    except json.JSONDecodeError:
        raise BadRequestError("Invalid JSON payload")

    return {"status": "ok"}


@router.post(
    "/release/{task_id}",
    response_model=EscrowTransactionResponse,
    summary="[Admin] Manually release escrow to agent",
    description="Admin endpoint for manual escrow release if needed.",
)
async def admin_release_escrow(
    task_id: uuid.UUID,
    admin: AdminUser,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    escrow = await payment_service.release_to_agent(db, task_id)
    return EscrowTransactionResponse.model_validate(escrow)


@router.post(
    "/refund/{task_id}",
    response_model=EscrowTransactionResponse,
    summary="[Admin] Manually refund escrow to client",
)
async def admin_refund_escrow(
    task_id: uuid.UUID,
    admin: AdminUser,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    escrow = await payment_service.refund_to_client(db, task_id)
    return EscrowTransactionResponse.model_validate(escrow)


@router.get(
    "/history",
    response_model=PaymentHistoryResponse,
    summary="Get payment history",
)
async def get_payment_history(
    current_user: VerifiedUser,
    db: Annotated[AsyncSession, Depends(get_db)],
    page: int = 1,
    page_size: int = 20,
):
    return await payment_service.get_payment_history(
        db, current_user, page=page, page_size=page_size
    )
