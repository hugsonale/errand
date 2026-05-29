import uuid
from fastapi import UploadFile
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.exceptions import NotFoundError, BadRequestError, ForbiddenError
from app.models.user import User, UserRole
from app.models.agent_profile import AgentProfile, AgentVerification, VerificationStatus
from app.schemas.agent import (
    KYCSubmitRequest,
    UpdateAgentProfileRequest,
    UpdateLocationRequest,
    ReviewVerificationRequest,
    VerificationListItem,
)
from app.services.s3_service import s3_service, ALLOWED_DOC_TYPES


class AgentService:

    async def get_profile(self, db: AsyncSession, user_id: uuid.UUID) -> AgentProfile:
        result = await db.execute(
            select(AgentProfile)
            .where(AgentProfile.user_id == user_id)
            .options(selectinload(AgentProfile.verification))
        )
        profile = result.scalar_one_or_none()
        if not profile:
            raise NotFoundError("Agent profile")
        return profile

    async def submit_kyc(
        self,
        db: AsyncSession,
        user: User,
        data: KYCSubmitRequest,
        nin_doc: UploadFile,
        selfie: UploadFile,
        address_doc: UploadFile,
    ) -> AgentVerification:
        """
        Handles the full KYC submission:
        1. Validates user is an agent
        2. Uploads 3 documents to S3
        3. Creates or updates the verification record
        """
        if user.role != UserRole.AGENT:
            raise ForbiddenError("Only agents can submit KYC.")

        profile = await self.get_profile(db, user.id)

        # Check if already approved
        if profile.verification and profile.verification.status == VerificationStatus.APPROVED:
            raise BadRequestError("Your verification has already been approved.")

        # Upload documents concurrently (sequential here for simplicity — Phase 4 adds asyncio.gather)
        nin_key = await s3_service.upload_file(
            nin_doc,
            folder=f"kyc/{user.id}/nin",
            allowed_types=ALLOWED_DOC_TYPES,
        )
        selfie_key = await s3_service.upload_file(
            selfie,
            folder=f"kyc/{user.id}/selfie",
            allowed_types={"image/jpeg", "image/png", "image/webp"},
        )
        address_key = await s3_service.upload_file(
            address_doc,
            folder=f"kyc/{user.id}/address",
            allowed_types=ALLOWED_DOC_TYPES,
        )

        # Create or update verification record
        if profile.verification:
            v = profile.verification
            v.nin_number = data.nin_number
            v.nin_doc_url = nin_key
            v.selfie_url = selfie_key
            v.address_doc_url = address_key
            v.address_text = data.address_text
            v.guarantor_name = data.guarantor_name
            v.guarantor_phone = data.guarantor_phone
            v.guarantor_relationship = data.guarantor_relationship
            v.bvn_number = data.bvn_number
            v.status = VerificationStatus.RESUBMITTED
            v.rejection_reason = None
            v.submission_count += 1
        else:
            v = AgentVerification(
                agent_id=profile.id,
                nin_number=data.nin_number,
                nin_doc_url=nin_key,
                selfie_url=selfie_key,
                address_doc_url=address_key,
                address_text=data.address_text,
                guarantor_name=data.guarantor_name,
                guarantor_phone=data.guarantor_phone,
                guarantor_relationship=data.guarantor_relationship,
                bvn_number=data.bvn_number,
                status=VerificationStatus.PENDING,
            )
            db.add(v)

        await db.flush()
        return v

    async def get_verification_status(
        self, db: AsyncSession, user: User
    ) -> AgentVerification:
        profile = await self.get_profile(db, user.id)
        if not profile.verification:
            raise NotFoundError("No verification submission found")
        return profile.verification

    async def update_location(
        self,
        db: AsyncSession,
        user: User,
        data: UpdateLocationRequest,
    ) -> AgentProfile:
        profile = await self.get_profile(db, user.id)
        profile.current_lat = data.latitude
        profile.current_lng = data.longitude
        await db.flush()
        return profile

    async def toggle_availability(
        self,
        db: AsyncSession,
        user: User,
        is_available: bool,
    ) -> AgentProfile:
        profile = await self.get_profile(db, user.id)

        # Can only go online if verification is approved
        if is_available and (
            not profile.verification
            or profile.verification.status != VerificationStatus.APPROVED
        ):
            raise ForbiddenError(
                "You must complete identity verification before going online."
            )

        profile.is_available = is_available
        await db.flush()
        return profile

    async def update_profile(
        self,
        db: AsyncSession,
        user: User,
        data: UpdateAgentProfileRequest,
    ) -> AgentProfile:
        profile = await self.get_profile(db, user.id)
        if data.bio is not None:
            profile.bio = data.bio
        if data.skill_tags is not None:
            profile.skill_tags = data.skill_tags
        if data.gender is not None:
            profile.gender = data.gender
        await db.flush()
        return profile

    # ─── Admin actions ────────────────────────────────────────────────────────

    async def list_pending_verifications(
        self, db: AsyncSession
    ) -> list[VerificationListItem]:
        """Admin endpoint — returns all pending/resubmitted KYC applications."""
        result = await db.execute(
            select(AgentVerification)
            .where(
                AgentVerification.status.in_([
                    VerificationStatus.PENDING,
                    VerificationStatus.RESUBMITTED,
                ])
            )
            .options(
                selectinload(AgentVerification.agent).selectinload(AgentProfile.user)
            )
            .order_by(AgentVerification.created_at.asc())
        )
        verifications = result.scalars().all()

        items = []
        for v in verifications:
            agent_user = v.agent.user
            items.append(
                VerificationListItem(
                    id=v.id,
                    agent_id=v.agent_id,
                    agent_name=agent_user.full_name,
                    agent_phone=agent_user.phone,
                    status=v.status,
                    submission_count=v.submission_count,
                    submitted_at=v.created_at,
                    nin_doc_url=s3_service.get_presigned_url(v.nin_doc_url) if v.nin_doc_url else None,
                    selfie_url=s3_service.get_presigned_url(v.selfie_url) if v.selfie_url else None,
                    address_doc_url=s3_service.get_presigned_url(v.address_doc_url) if v.address_doc_url else None,
                )
            )
        return items

    async def review_verification(
        self,
        db: AsyncSession,
        verification_id: uuid.UUID,
        admin: User,
        data: ReviewVerificationRequest,
    ) -> AgentVerification:
        """Admin approves or rejects a KYC submission."""
        result = await db.execute(
            select(AgentVerification)
            .where(AgentVerification.id == verification_id)
            .options(selectinload(AgentVerification.agent))
        )
        v = result.scalar_one_or_none()
        if not v:
            raise NotFoundError("Verification")

        if v.status == VerificationStatus.APPROVED:
            raise BadRequestError("Verification is already approved.")

        if data.action == "approve":
            v.status = VerificationStatus.APPROVED
            v.rejection_reason = None
            v.reviewed_by = admin.id
            # Mark the agent's user account as verified
            result2 = await db.execute(
                select(User).where(User.id == v.agent.user_id)
            )
            agent_user = result2.scalar_one_or_none()
            if agent_user:
                agent_user.is_verified = True
            # Send notification
            from app.services.notification_service import notification_service
            await notification_service.verification_approved(db, v.agent.user_id)
        else:
            v.status = VerificationStatus.REJECTED
            v.rejection_reason = data.rejection_reason
            v.reviewed_by = admin.id
            from app.services.notification_service import notification_service
            await notification_service.verification_rejected(
                db, v.agent.user_id, data.rejection_reason or "Documents unclear"
            )

        await db.flush()
        return v


agent_service = AgentService()
