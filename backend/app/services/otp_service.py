import httpx
from datetime import datetime, timedelta, timezone

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update

from app.config import settings
from app.core.security import generate_otp
from app.core.exceptions import BadRequestError, ServiceUnavailableError
from app.models.auth import OTPCode
from app.models.user import User


class OTPService:
    MAX_ATTEMPTS = 5  # Max wrong attempts before OTP is invalidated

    async def create_and_send(self, db: AsyncSession, user: User) -> str:
        """
        Invalidates any existing unused OTPs for this user,
        generates a new one, persists it, and sends via SMS.
        Returns the OTP code (for dev/testing when SMS is off).
        """
        # Invalidate previous unused OTPs for this phone
        await db.execute(
            update(OTPCode)
            .where(OTPCode.phone == user.phone, OTPCode.used == False)
            .values(used=True)
        )

        code = generate_otp(settings.OTP_LENGTH)
        expires_at = datetime.now(timezone.utc) + timedelta(
            minutes=settings.OTP_EXPIRE_MINUTES
        )

        otp_record = OTPCode(
            user_id=user.id,
            phone=user.phone,
            code=code,
            expires_at=expires_at,
        )
        db.add(otp_record)
        await db.flush()  # get the ID without committing

        # Send SMS
        await self._send_sms(user.phone, code)

        return code

    async def verify(self, db: AsyncSession, phone: str, code: str) -> bool:
        """
        Returns True if valid, raises BadRequestError otherwise.
        Increments attempt counter to prevent brute force.
        """
        result = await db.execute(
            select(OTPCode)
            .where(
                OTPCode.phone == phone,
                OTPCode.used == False,
            )
            .order_by(OTPCode.created_at.desc())
            .limit(1)
        )
        otp = result.scalar_one_or_none()

        if not otp:
            raise BadRequestError("No active OTP found. Please request a new one.")

        # Increment attempt count before checking
        otp.attempt_count += 1

        if otp.attempt_count > self.MAX_ATTEMPTS:
            otp.used = True
            raise BadRequestError(
                "Too many incorrect attempts. Please request a new OTP."
            )

        now = datetime.now(timezone.utc)
        if otp.expires_at.replace(tzinfo=timezone.utc) < now:
            otp.used = True
            raise BadRequestError("OTP has expired. Please request a new one.")

        if otp.code != code:
            raise BadRequestError(
                f"Incorrect OTP. {self.MAX_ATTEMPTS - otp.attempt_count} attempts remaining."
            )

        # Valid — mark as used
        otp.used = True
        return True

    async def _send_sms(self, phone: str, code: str) -> None:
        """Send OTP via Termii SMS API."""
        if not settings.TERMII_API_KEY:
            # Development mode — log to console instead of sending
            print(f"[DEV OTP] Phone: {phone} | Code: {code}")
            return

        message = (
            f"Your Errand Marketplace verification code is: {code}. "
            f"Valid for {settings.OTP_EXPIRE_MINUTES} minutes. "
            f"Do not share this code with anyone."
        )

        payload = {
            "to": phone,
            "from": settings.TERMII_SENDER_ID,
            "sms": message,
            "type": "plain",
            "channel": "dnd",
            "api_key": settings.TERMII_API_KEY,
        }

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.post(
                    "https://api.ng.termii.com/api/sms/send",
                    json=payload,
                )
                response.raise_for_status()
        except httpx.HTTPError as e:
            # Don't block registration if SMS fails — log and continue
            print(f"[SMS ERROR] Failed to send OTP to {phone}: {e}")


otp_service = OTPService()
