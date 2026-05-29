import uuid
from fastapi import APIRouter, Depends, UploadFile, File, Form
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Annotated

from app.database import get_db
from app.schemas.agent import (
    AgentProfileResponse,
    UpdateAgentProfileRequest,
    UpdateLocationRequest,
    ToggleAvailabilityRequest,
    VerificationStatusResponse,
    VerificationListItem,
    ReviewVerificationRequest,
)
from app.schemas.auth import SuccessResponse
from app.services.agent_service import agent_service
from app.core.dependencies import (
    VerifiedUser,
    AgentUser,
    AdminUser,
    CurrentUser,
)
from app.core.exceptions import ForbiddenError
from app.models.user import UserRole

router = APIRouter(prefix="/agents", tags=["Agents"])


# ─── KYC Verification ────────────────────────────────────────────────────────

@router.post(
    "/verify/submit",
    response_model=SuccessResponse,
    summary="Submit KYC documents",
    description=(
        "Agent submits NIN number, address, guarantor info, "
        "and uploads NIN document, selfie, and address proof. "
        "Submission goes into the admin review queue."
    ),
)
async def submit_kyc(
    current_user: AgentUser,
    db: Annotated[AsyncSession, Depends(get_db)],
    # Text fields as Form data (multipart request)
    nin_number: str = Form(...),
    address_text: str = Form(...),
    guarantor_name: str = Form(...),
    guarantor_phone: str = Form(...),
    guarantor_relationship: str = Form(...),
    bvn_number: str | None = Form(default=None),
    # File uploads
    nin_doc: UploadFile = File(..., description="NIN document image/PDF"),
    selfie: UploadFile = File(..., description="Clear selfie photo"),
    address_doc: UploadFile = File(..., description="Utility bill or address proof"),
):
    from app.schemas.agent import KYCSubmitRequest
    data = KYCSubmitRequest(
        nin_number=nin_number,
        address_text=address_text,
        guarantor_name=guarantor_name,
        guarantor_phone=guarantor_phone,
        guarantor_relationship=guarantor_relationship,
        bvn_number=bvn_number,
    )
    await agent_service.submit_kyc(db, current_user, data, nin_doc, selfie, address_doc)
    return SuccessResponse(
        message="KYC documents submitted successfully. Review typically takes 24–48 hours."
    )


@router.get(
    "/verify/status",
    response_model=VerificationStatusResponse,
    summary="Check KYC verification status",
)
async def get_verification_status(
    current_user: AgentUser,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    verification = await agent_service.get_verification_status(db, current_user)
    return VerificationStatusResponse.model_validate(verification)


# ─── Agent Profile ────────────────────────────────────────────────────────────

@router.get(
    "/me/profile",
    response_model=AgentProfileResponse,
    summary="Get own agent profile",
)
async def get_my_profile(
    current_user: AgentUser,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    profile = await agent_service.get_profile(db, current_user.id)
    return AgentProfileResponse.model_validate(profile)


@router.patch(
    "/me/profile",
    response_model=AgentProfileResponse,
    summary="Update agent bio, skills, gender",
)
async def update_my_profile(
    data: UpdateAgentProfileRequest,
    current_user: AgentUser,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    profile = await agent_service.update_profile(db, current_user, data)
    return AgentProfileResponse.model_validate(profile)


@router.get(
    "/{agent_id}/profile",
    response_model=AgentProfileResponse,
    summary="Get public agent profile by ID",
    description="Visible to all authenticated users — clients use this to evaluate agents.",
)
async def get_agent_profile(
    agent_id: uuid.UUID,
    current_user: VerifiedUser,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    profile = await agent_service.get_profile(db, agent_id)
    return AgentProfileResponse.model_validate(profile)


# ─── Availability & Location ─────────────────────────────────────────────────

@router.patch(
    "/location",
    response_model=SuccessResponse,
    summary="Update agent live location",
    description="Called by the Flutter app every 30 seconds when the agent is online.",
)
async def update_location(
    data: UpdateLocationRequest,
    current_user: AgentUser,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    await agent_service.update_location(db, current_user, data)
    return SuccessResponse(message="Location updated.")


@router.patch(
    "/availability",
    response_model=AgentProfileResponse,
    summary="Toggle agent online/offline status",
)
async def toggle_availability(
    data: ToggleAvailabilityRequest,
    current_user: AgentUser,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    profile = await agent_service.toggle_availability(
        db, current_user, data.is_available
    )
    return AgentProfileResponse.model_validate(profile)


# ─── Admin Endpoints ──────────────────────────────────────────────────────────

@router.get(
    "/admin/verifications",
    response_model=list[VerificationListItem],
    summary="[Admin] List pending KYC verifications",
    description="Returns all pending and resubmitted KYC applications with presigned document URLs.",
)
async def list_pending_verifications(
    admin: AdminUser,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    return await agent_service.list_pending_verifications(db)


@router.post(
    "/admin/verifications/{verification_id}/review",
    response_model=SuccessResponse,
    summary="[Admin] Approve or reject a KYC submission",
)
async def review_verification(
    verification_id: uuid.UUID,
    data: ReviewVerificationRequest,
    admin: AdminUser,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    await agent_service.review_verification(db, verification_id, admin, data)
    action_word = "approved" if data.action == "approve" else "rejected"
    return SuccessResponse(message=f"Verification {action_word} successfully.")
