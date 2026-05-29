import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update

from app.config import settings
from app.core.security import (
    hash_password,
    verify_password,
    create_access_token,
    create_refresh_token,
    hash_refresh_token,
)
from app.core.exceptions import (
    BadRequestError,
    UnauthorizedError,
    ConflictError,
    NotFoundError,
)
from app.models.user import User, UserRole
from app.models.agent_profile import AgentProfile
from app.models.auth import RefreshToken
from app.schemas.auth import RegisterRequest, LoginRequest, TokenResponse
from app.services.otp_service import otp_service


class AuthService:

    async def register(self, db: AsyncSession, data: RegisterRequest) -> User:
        """
        1. Check phone (and email if given) are not already taken
        2. Create User record
        3. If role is AGENT, create AgentProfile record
        4. Send OTP for phone verification
        """
        # Check phone uniqueness
        existing = await db.execute(
            select(User).where(User.phone == data.phone)
        )
        if existing.scalar_one_or_none():
            raise ConflictError("An account with this phone number already exists.")

        # Check email uniqueness if provided
        if data.email:
            existing_email = await db.execute(
                select(User).where(User.email == data.email)
            )
            if existing_email.scalar_one_or_none():
                raise ConflictError("An account with this email already exists.")

        # Create user
        user = User(
            full_name=data.full_name,
            phone=data.phone,
            email=data.email,
            password_hash=hash_password(data.password),
            role=data.role,
            phone_verified=False,
            is_active=True,
            is_verified=False,
        )
        db.add(user)
        await db.flush()  # assigns user.id before creating related records

        # Create agent profile if registering as agent
        if data.role == UserRole.AGENT:
            profile = AgentProfile(user_id=user.id)
            db.add(profile)
            await db.flush()

        # Send OTP
        await otp_service.create_and_send(db, user)

        return user

    async def verify_phone(
        self, db: AsyncSession, phone: str, code: str
    ) -> TokenResponse:
        """
        Verifies OTP → marks phone as verified → returns tokens.
        This is the moment a user becomes active on the platform.
        """
        # Find user
        result = await db.execute(select(User).where(User.phone == phone))
        user = result.scalar_one_or_none()
        if not user:
            raise NotFoundError("User")

        # Verify the OTP (raises BadRequestError on failure)
        await otp_service.verify(db, phone, code)

        # Mark phone verified
        user.phone_verified = True
        await db.flush()

        return await self._issue_tokens(db, user)

    async def login(self, db: AsyncSession, data: LoginRequest) -> TokenResponse:
        """
        Accepts phone or email as identifier.
        Returns access + refresh tokens on success.
        """
        identifier = data.identifier.strip()

        # Determine if identifier is phone or email
        if "@" in identifier:
            result = await db.execute(
                select(User).where(User.email == identifier)
            )
        else:
            # Normalise Nigerian phone
            if identifier.startswith("0") and len(identifier) == 11:
                identifier = "+234" + identifier[1:]
            result = await db.execute(
                select(User).where(User.phone == identifier)
            )

        user = result.scalar_one_or_none()

        # Use constant-time comparison to prevent user enumeration
        if not user or not verify_password(data.password, user.password_hash):
            raise UnauthorizedError("Incorrect phone/email or password.")

        if not user.is_active:
            raise UnauthorizedError("Your account has been deactivated. Contact support.")

        if not user.phone_verified:
            # Re-send OTP so they can verify
            await otp_service.create_and_send(db, user)
            raise BadRequestError(
                "Phone not verified. A new verification code has been sent to your phone."
            )

        return await self._issue_tokens(db, user)

    async def refresh(self, db: AsyncSession, raw_token: str) -> TokenResponse:
        """
        Validates the refresh token, revokes it (rotation),
        and issues a new pair.
        """
        token_hash = hash_refresh_token(raw_token)

        result = await db.execute(
            select(RefreshToken).where(
                RefreshToken.token_hash == token_hash,
                RefreshToken.revoked == False,
            )
        )
        stored = result.scalar_one_or_none()

        if not stored:
            raise UnauthorizedError("Invalid or expired refresh token.")

        now = datetime.now(timezone.utc)
        if stored.expires_at.replace(tzinfo=timezone.utc) < now:
            stored.revoked = True
            raise UnauthorizedError("Refresh token has expired. Please log in again.")

        # Revoke old token (rotation — prevents replay attacks)
        stored.revoked = True
        await db.flush()

        # Load user
        result = await db.execute(select(User).where(User.id == stored.user_id))
        user = result.scalar_one_or_none()
        if not user or not user.is_active:
            raise UnauthorizedError("Account not found or deactivated.")

        return await self._issue_tokens(db, user)

    async def logout(self, db: AsyncSession, raw_token: str) -> None:
        """Revokes the refresh token so it can't be reused."""
        token_hash = hash_refresh_token(raw_token)
        await db.execute(
            update(RefreshToken)
            .where(RefreshToken.token_hash == token_hash)
            .values(revoked=True)
        )

    async def resend_otp(self, db: AsyncSession, phone: str) -> None:
        """Rate-limited OTP resend."""
        result = await db.execute(select(User).where(User.phone == phone))
        user = result.scalar_one_or_none()

        if not user:
            # Don't reveal whether phone exists — just return silently
            return

        if user.phone_verified:
            raise BadRequestError("Phone number is already verified.")

        await otp_service.create_and_send(db, user)

    # ─── Private helpers ─────────────────────────────────────────────────────

    async def _issue_tokens(self, db: AsyncSession, user: User) -> TokenResponse:
        """Creates access + refresh tokens and persists the refresh token."""
        access_token = create_access_token(
            subject=str(user.id),
            extra={"role": user.role.value, "phone": user.phone},
        )
        raw_refresh, hashed_refresh = create_refresh_token()

        expires_at = datetime.now(timezone.utc) + timedelta(
            days=settings.REFRESH_TOKEN_EXPIRE_DAYS
        )
        refresh_record = RefreshToken(
            user_id=user.id,
            token_hash=hashed_refresh,
            expires_at=expires_at,
        )
        db.add(refresh_record)
        await db.flush()

        return TokenResponse(
            access_token=access_token,
            refresh_token=raw_refresh,
            token_type="bearer",
            expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        )


auth_service = AuthService()
