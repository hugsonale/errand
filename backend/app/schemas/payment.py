import uuid
from datetime import datetime
from pydantic import BaseModel, field_validator
from app.models.payment import EscrowStatus, DisputeStatus, NotificationType


# ─── Payment ──────────────────────────────────────────────────────────────────

class InitiatePaymentResponse(BaseModel):
    authorization_url: str
    access_code: str
    reference: str
    amount: float
    message: str = "Redirect user to authorization_url to complete payment"


class EscrowTransactionResponse(BaseModel):
    id: uuid.UUID
    task_id: uuid.UUID
    paystack_reference: str
    amount: float
    platform_fee: float
    agent_payout: float
    status: EscrowStatus
    paid_at: str | None
    released_at: str | None
    refunded_at: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class PaymentHistoryResponse(BaseModel):
    transactions: list[EscrowTransactionResponse]
    total: int


# ─── Review ───────────────────────────────────────────────────────────────────

class SubmitReviewRequest(BaseModel):
    task_id: uuid.UUID
    overall_rating: int
    punctuality: int
    trustworthiness: int
    communication: int
    professionalism: int
    comment: str | None = None

    @field_validator(
        "overall_rating", "punctuality", "trustworthiness",
        "communication", "professionalism"
    )
    @classmethod
    def validate_rating(cls, v: int) -> int:
        if not 1 <= v <= 5:
            raise ValueError("Rating must be between 1 and 5")
        return v


class ReviewResponse(BaseModel):
    id: uuid.UUID
    task_id: uuid.UUID
    reviewer_id: uuid.UUID
    reviewee_id: uuid.UUID
    overall_rating: int
    punctuality: int
    trustworthiness: int
    communication: int
    professionalism: int
    weighted_score: float
    comment: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class AgentReviewsResponse(BaseModel):
    reviews: list[ReviewResponse]
    total: int
    average_score: float
    breakdown: dict[str, float]   # dimension averages


class TrustScoreBreakdown(BaseModel):
    agent_id: uuid.UUID
    trust_score: float
    trust_level: str
    total_reviews: int
    average_overall: float
    average_punctuality: float
    average_trustworthiness: float
    average_communication: float
    average_professionalism: float
    completed_tasks: int
    success_rate: float
    repeat_client_count: int


# ─── Dispute ─────────────────────────────────────────────────────────────────

class DisputeResponse(BaseModel):
    id: uuid.UUID
    task_id: uuid.UUID
    raised_by: uuid.UUID
    reason: str
    description: str
    status: DisputeStatus
    resolution_note: str | None
    resolved_at: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class ResolveDisputeRequest(BaseModel):
    action: str          # "refund" | "release" | "partial"
    resolution_note: str

    @field_validator("action")
    @classmethod
    def validate_action(cls, v: str) -> str:
        if v not in ("refund", "release", "partial"):
            raise ValueError("action must be 'refund', 'release', or 'partial'")
        return v

    @field_validator("resolution_note")
    @classmethod
    def validate_note(cls, v: str) -> str:
        if len(v.strip()) < 10:
            raise ValueError("Resolution note must be at least 10 characters")
        return v.strip()


# ─── Notification ─────────────────────────────────────────────────────────────

class NotificationResponse(BaseModel):
    id: uuid.UUID
    type: NotificationType
    title: str
    body: str
    data: str | None
    is_read: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class NotificationListResponse(BaseModel):
    notifications: list[NotificationResponse]
    unread_count: int
    total: int
