import json
import uuid
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.payment import Notification, NotificationType
from app.models.user import User
from app.services.fcm_service import fcm_service


class NotificationService:

    async def send(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        notification_type: NotificationType,
        title: str,
        body: str,
        data: dict | None = None,
    ) -> Notification:
        """
        Creates a notification record in DB and fires FCM push.
        Never raises — notification failures are non-fatal.
        """
        notification = Notification(
            user_id=user_id,
            type=notification_type,
            title=title,
            body=body,
            data=json.dumps(data) if data else None,
            is_read=False,
            sent_push=False,
        )
        db.add(notification)
        await db.flush()

        # Get user's FCM token
        try:
            user_result = await db.execute(
                select(User).where(User.id == user_id)
            )
            user = user_result.scalar_one_or_none()
            if user and user.fcm_token:
                success = await fcm_service.send_to_token(
                    fcm_token=user.fcm_token,
                    title=title,
                    body=body,
                    data=data,
                )
                notification.sent_push = success
        except Exception as e:
            print(f"[NOTIFICATION ERROR] {e}")

        return notification

    # ─── Pre-built notification templates ────────────────────────────────────

    async def agent_applied(
        self, db: AsyncSession, client_id: uuid.UUID, task_title: str,
        agent_name: str, task_id: uuid.UUID
    ) -> None:
        await self.send(
            db, client_id,
            NotificationType.AGENT_APPLIED,
            title="New application! 🙋",
            body=f"{agent_name} wants to help with '{task_title}'",
            data={"task_id": str(task_id), "screen": "applicants"},
        )

    async def application_accepted(
        self, db: AsyncSession, agent_id: uuid.UUID, task_title: str,
        task_id: uuid.UUID
    ) -> None:
        await self.send(
            db, agent_id,
            NotificationType.APPLICATION_ACCEPTED,
            title="You've been hired! 🎉",
            body=f"A client selected you for '{task_title}'. Get ready!",
            data={"task_id": str(task_id), "screen": "active_job"},
        )

    async def task_started(
        self, db: AsyncSession, client_id: uuid.UUID, task_title: str,
        task_id: uuid.UUID
    ) -> None:
        await self.send(
            db, client_id,
            NotificationType.TASK_STARTED,
            title="Task started! 🚀",
            body=f"Your agent has started working on '{task_title}'",
            data={"task_id": str(task_id), "screen": "track"},
        )

    async def proof_submitted(
        self, db: AsyncSession, client_id: uuid.UUID, task_title: str,
        otp_code: str, task_id: uuid.UUID
    ) -> None:
        await self.send(
            db, client_id,
            NotificationType.PROOF_SUBMITTED,
            title="Task completed — confirm now 📸",
            body=f"Your agent says '{task_title}' is done. Confirm code: {otp_code}",
            data={"task_id": str(task_id), "otp": otp_code, "screen": "track"},
        )

    async def payment_released(
        self, db: AsyncSession, agent_id: uuid.UUID, amount: float,
        task_title: str
    ) -> None:
        await self.send(
            db, agent_id,
            NotificationType.PAYMENT_RELEASED,
            title="Payment received! 💰",
            body=f"₦{amount:,.0f} has been sent to your account for '{task_title}'",
            data={"screen": "earnings"},
        )

    async def review_received(
        self, db: AsyncSession, agent_id: uuid.UUID, rating: int,
        task_title: str
    ) -> None:
        stars = "⭐" * rating
        await self.send(
            db, agent_id,
            NotificationType.REVIEW_RECEIVED,
            title=f"New review {stars}",
            body=f"A client rated your work on '{task_title}'",
            data={"screen": "profile"},
        )

    async def level_up(
        self, db: AsyncSession, agent_id: uuid.UUID,
        new_level: str
    ) -> None:
        level_emoji = {
            "silver": "🥈", "gold": "🥇", "platinum": "💎"
        }.get(new_level, "🏆")
        await self.send(
            db, agent_id,
            NotificationType.LEVEL_UP,
            title=f"Level up! {level_emoji}",
            body=f"Congratulations! You've reached {new_level.upper()} status!",
            data={"new_level": new_level, "screen": "trust_score"},
        )

    async def verification_approved(
        self, db: AsyncSession, agent_id: uuid.UUID
    ) -> None:
        await self.send(
            db, agent_id,
            NotificationType.VERIFICATION_APPROVED,
            title="Identity verified! ✅",
            body="Your account is verified. Go online and start earning!",
            data={"screen": "home"},
        )

    async def verification_rejected(
        self, db: AsyncSession, agent_id: uuid.UUID, reason: str
    ) -> None:
        await self.send(
            db, agent_id,
            NotificationType.VERIFICATION_REJECTED,
            title="Verification needs attention",
            body=f"Please review and resubmit: {reason}",
            data={"screen": "kyc", "reason": reason},
        )


notification_service = NotificationService()
