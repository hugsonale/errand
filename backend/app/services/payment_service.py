import uuid
import json
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.exceptions import BadRequestError, NotFoundError, ForbiddenError
from app.models.user import User
from app.models.task import Task, TaskStatus
from app.models.payment import EscrowTransaction, EscrowStatus
from app.services.paystack_service import paystack_service
from app.services.notification_service import notification_service
from app.schemas.payment import (
    InitiatePaymentResponse,
    EscrowTransactionResponse,
    PaymentHistoryResponse,
)
from app.utils.helpers import utc_now


class PaymentService:

    async def initiate_payment(
        self, db: AsyncSession, client: User, task_id: uuid.UUID
    ) -> InitiatePaymentResponse:
        """
        Creates a Paystack charge for the task amount.
        Called after client accepts an agent application.
        Money is NOT yet held — it's held when webhook fires.
        """
        # Load task
        result = await db.execute(
            select(Task).where(Task.id == task_id)
        )
        task = result.scalar_one_or_none()
        if not task:
            raise NotFoundError("Task")
        if task.client_id != client.id:
            raise ForbiddenError("You do not own this task.")
        if task.status != TaskStatus.ACCEPTED:
            raise BadRequestError(
                f"Payment can only be initiated for accepted tasks. "
                f"Current status: {task.status.value}"
            )

        # Check if already paid
        existing = await db.execute(
            select(EscrowTransaction).where(
                EscrowTransaction.task_id == task_id,
                EscrowTransaction.status.in_([EscrowStatus.HELD, EscrowStatus.PENDING]),
            )
        )
        if existing.scalar_one_or_none():
            raise BadRequestError("Payment already initiated for this task.")

        amount = float(task.final_price or task.budget)
        if task.is_emergency:
            amount += float(task.emergency_fee or 0)

        platform_fee, agent_payout = paystack_service.compute_fees(amount)
        reference = paystack_service.generate_reference(task_id)

        # Call Paystack
        paystack_data = await paystack_service.initiate_charge(
            email=client.email or f"{str(client.id)[:8]}@errandmarketplace.com",
            amount_naira=amount,
            task_id=task_id,
            reference=reference,
            metadata={"task_title": task.title},
        )

        # Create escrow record in PENDING state
        escrow = EscrowTransaction(
            task_id=task_id,
            client_id=client.id,
            agent_id=task.agent_id,
            paystack_reference=reference,
            paystack_authorization_url=paystack_data.get("authorization_url"),
            paystack_access_code=paystack_data.get("access_code"),
            amount=amount,
            platform_fee=platform_fee,
            agent_payout=agent_payout,
            status=EscrowStatus.PENDING,
        )
        db.add(escrow)
        await db.flush()

        return InitiatePaymentResponse(
            authorization_url=paystack_data["authorization_url"],
            access_code=paystack_data["access_code"],
            reference=reference,
            amount=amount,
        )

    async def handle_webhook(self, db: AsyncSession, event: str, data: dict) -> None:
        """
        Processes verified Paystack webhook events.
        Called only after HMAC signature has been verified.
        """
        if event == "charge.success":
            await self._on_charge_success(db, data)
        elif event == "transfer.success":
            await self._on_transfer_success(db, data)
        elif event == "transfer.failed":
            await self._on_transfer_failed(db, data)

    async def _on_charge_success(self, db: AsyncSession, data: dict) -> None:
        """Payment confirmed — move escrow from PENDING to HELD."""
        reference = data.get("reference")
        if not reference:
            return

        result = await db.execute(
            select(EscrowTransaction).where(
                EscrowTransaction.paystack_reference == reference
            )
        )
        escrow = result.scalar_one_or_none()
        if not escrow or escrow.status != EscrowStatus.PENDING:
            return

        escrow.status = EscrowStatus.HELD
        escrow.paid_at = utc_now().isoformat()

        # Verify amount matches (security check)
        paid_kobo = data.get("amount", 0)
        paid_naira = paid_kobo / 100
        if abs(paid_naira - float(escrow.amount)) > 1:
            print(f"[PAYMENT WARNING] Amount mismatch: paid={paid_naira} expected={escrow.amount}")

        await db.flush()
        print(f"[ESCROW] ₦{escrow.amount:,.2f} held for task {escrow.task_id}")

    async def _on_transfer_success(self, db: AsyncSession, data: dict) -> None:
        """Agent payout completed."""
        reference = data.get("reference", "")
        if not reference.startswith("PAY-"):
            return

        # Find the escrow with this payout reference
        result = await db.execute(
            select(EscrowTransaction).where(
                EscrowTransaction.payout_reference == reference
            )
        )
        escrow = result.scalar_one_or_none()
        if escrow:
            escrow.payout_status = "completed"
            await db.flush()

    async def _on_transfer_failed(self, db: AsyncSession, data: dict) -> None:
        """Agent payout failed — flag for manual review."""
        reference = data.get("reference", "")
        result = await db.execute(
            select(EscrowTransaction).where(
                EscrowTransaction.payout_reference == reference
            )
        )
        escrow = result.scalar_one_or_none()
        if escrow:
            escrow.payout_status = "failed"
            await db.flush()
            print(f"[PAYOUT FAILED] Task {escrow.task_id} — manual review needed")

    async def release_to_agent(
        self, db: AsyncSession, task_id: uuid.UUID
    ) -> EscrowTransaction:
        """
        Releases escrow to agent after task completion.
        Called internally when client confirms task.
        """
        result = await db.execute(
            select(EscrowTransaction)
            .where(EscrowTransaction.task_id == task_id)
            .options(selectinload(EscrowTransaction.task_id))
        )
        escrow = result.scalar_one_or_none()
        if not escrow:
            raise NotFoundError("Escrow transaction")
        if escrow.status != EscrowStatus.HELD:
            raise BadRequestError(
                f"Cannot release escrow — current status: {escrow.status.value}"
            )

        # Trigger Paystack transfer to agent
        # (In MVP, agent bank details are stored separately — Phase 4 adds agent bank setup)
        # For now, mark as released and flag for manual payout
        escrow.status = EscrowStatus.RELEASED
        escrow.released_at = utc_now().isoformat()

        # Load task to get agent info for notification
        task_result = await db.execute(
            select(Task).where(Task.id == task_id)
        )
        task = task_result.scalar_one_or_none()

        if task and task.agent_id:
            from app.models.agent_profile import AgentProfile
            from app.models.user import User as UserModel
            agent_result = await db.execute(
                select(AgentProfile).where(AgentProfile.id == task.agent_id)
            )
            agent_profile = agent_result.scalar_one_or_none()
            if agent_profile:
                user_result = await db.execute(
                    select(UserModel).where(UserModel.id == agent_profile.user_id)
                )
                agent_user = user_result.scalar_one_or_none()
                if agent_user:
                    await notification_service.payment_released(
                        db,
                        agent_id=agent_profile.user_id,
                        amount=float(escrow.agent_payout),
                        task_title=task.title,
                    )

        await db.flush()
        return escrow

    async def refund_to_client(
        self, db: AsyncSession, task_id: uuid.UUID, reason: str = ""
    ) -> EscrowTransaction:
        """Refunds escrow to client — called on cancellation or dispute resolution."""
        result = await db.execute(
            select(EscrowTransaction).where(EscrowTransaction.task_id == task_id)
        )
        escrow = result.scalar_one_or_none()
        if not escrow:
            return None  # No payment was made — nothing to refund

        if escrow.status not in (EscrowStatus.HELD, EscrowStatus.PENDING):
            raise BadRequestError(f"Cannot refund — status: {escrow.status.value}")

        # Trigger Paystack refund
        if escrow.status == EscrowStatus.HELD:
            await paystack_service.refund_transaction(
                escrow.paystack_reference,
                float(escrow.amount),
            )

        escrow.status = EscrowStatus.REFUNDED
        escrow.refunded_at = utc_now().isoformat()
        await db.flush()
        return escrow

    async def get_payment_history(
        self, db: AsyncSession, user: User, page: int = 1, page_size: int = 20
    ) -> PaymentHistoryResponse:
        """Returns paginated payment history for the user."""
        from sqlalchemy import func, or_

        query = select(EscrowTransaction).where(
            EscrowTransaction.client_id == user.id
        ).order_by(EscrowTransaction.created_at.desc())

        count_result = await db.execute(
            select(func.count()).select_from(query.subquery())
        )
        total = count_result.scalar_one()

        offset = (page - 1) * page_size
        result = await db.execute(query.offset(offset).limit(page_size))
        transactions = result.scalars().all()

        return PaymentHistoryResponse(
            transactions=[
                EscrowTransactionResponse.model_validate(t) for t in transactions
            ],
            total=total,
        )


payment_service = PaymentService()
