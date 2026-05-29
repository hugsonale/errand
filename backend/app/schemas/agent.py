import uuid
from datetime import datetime
from pydantic import BaseModel, field_validator
from app.models.agent_profile import TrustLevel, VerificationStatus


# ─── KYC Submission ──────────────────────────────────────────────────────────

class KYCSubmitRequest(BaseModel):
    """
    Text fields for KYC. Document files are uploaded separately
    via multipart form data to the same endpoint.
    """
    nin_number: str
    address_text: str
    guarantor_name: str
    guarantor_phone: str
    guarantor_relationship: str
    bvn_number: str | None = None

    @field_validator("nin_number")
    @classmethod
    def validate_nin(cls, v: str) -> str:
        v = v.strip().replace(" ", "")
        if not v.isdigit() or len(v) != 11:
            raise ValueError("NIN must be an 11-digit number")
        return v


class VerificationStatusResponse(BaseModel):
    status: VerificationStatus
    rejection_reason: str | None
    submission_count: int
    submitted_at: datetime

    model_config = {"from_attributes": True}


# ─── Agent Profile ───────────────────────────────────────────────────────────

class AgentProfileResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    trust_level: TrustLevel
    trust_score: float
    total_tasks: int
    completed_tasks: int
    success_rate: float
    punctuality_rate: float
    repeat_client_count: int
    bio: str | None
    skill_tags: list[str] | None
    is_available: bool
    gender: str | None
    years_active: float

    model_config = {"from_attributes": True}


class UpdateAgentProfileRequest(BaseModel):
    bio: str | None = None
    skill_tags: list[str] | None = None
    gender: str | None = None


class UpdateLocationRequest(BaseModel):
    latitude: float
    longitude: float

    @field_validator("latitude")
    @classmethod
    def validate_lat(cls, v: float) -> float:
        if not -90 <= v <= 90:
            raise ValueError("Latitude must be between -90 and 90")
        return v

    @field_validator("longitude")
    @classmethod
    def validate_lng(cls, v: float) -> float:
        if not -180 <= v <= 180:
            raise ValueError("Longitude must be between -180 and 180")
        return v


class ToggleAvailabilityRequest(BaseModel):
    is_available: bool


# ─── Admin verification management ───────────────────────────────────────────

class VerificationListItem(BaseModel):
    id: uuid.UUID
    agent_id: uuid.UUID
    agent_name: str
    agent_phone: str
    status: VerificationStatus
    submission_count: int
    submitted_at: datetime
    nin_doc_url: str | None
    selfie_url: str | None
    address_doc_url: str | None

    model_config = {"from_attributes": True}


class ReviewVerificationRequest(BaseModel):
    action: str  # "approve" or "reject"
    rejection_reason: str | None = None

    @field_validator("action")
    @classmethod
    def validate_action(cls, v: str) -> str:
        if v not in ("approve", "reject"):
            raise ValueError("Action must be 'approve' or 'reject'")
        return v

    @field_validator("rejection_reason")
    @classmethod
    def validate_rejection(cls, v: str | None, info) -> str | None:
        if info.data.get("action") == "reject" and not v:
            raise ValueError("Rejection reason is required when rejecting")
        return v
