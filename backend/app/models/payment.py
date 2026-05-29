import uuid
import enum
from sqlalchemy import (
    String, Boolean, Enum as SAEnum, Text,
    Numeric, Integer, ForeignKey, DateTime
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base
from app.models.base import UUIDMixin, TimestampMixin


# ─── Escrow Transaction ───────────────────────────────────────────────────────

class EscrowStatus(str, enum.Enum):
    PENDING = "pending"         # Payment initiated, not yet confirmed
    HELD = "held"               # Payment confirmed, funds held in escrow
    RELEASED = "released"       # Funds released to agent
    REFUNDED = "refunded"       # Funds refunded to client
    FAILED = "failed"           # Payment failed


class EscrowTransaction(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "escrow_transactions"

    task_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tasks.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )
    client_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    agent_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("agent_profiles.id", ondelete="SET NULL"),
        nullable=True,
    )

    # Paystack identifiers
    paystack_reference: Mapped[str] = mapped_column(
        String(100), unique=True, nullable=False, index=True
    )
    paystack_authorization_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    paystack_access_code: Mapped[str | None] = mapped_column(String(100), nullable=True)

    # Amounts (in kobo internally from Paystack, stored as Naira)
    amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    platform_fee: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    agent_payout: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)

    # Status
    status: Mapped[EscrowStatus] = mapped_column(
        SAEnum(EscrowStatus, name="escrow_status"),
        default=EscrowStatus.PENDING,
        nullable=False,
        index=True,
    )

    # Lifecycle timestamps (ISO strings for simplicity)
    paid_at: Mapped[str | None] = mapped_column(String(50), nullable=True)
    released_at: Mapped[str | None] = mapped_column(String(50), nullable=True)
    refunded_at: Mapped[str | None] = mapped_column(String(50), nullable=True)

    # Paystack transfer reference (for agent payout)
    payout_reference: Mapped[str | None] = mapped_column(String(100), nullable=True)
    payout_status: Mapped[str | None] = mapped_column(String(30), nullable=True)

    def __repr__(self) -> str:
        return f"<EscrowTransaction task={self.task_id} status={self.status} amount={self.amount}>"


# ─── Review ───────────────────────────────────────────────────────────────────

class Review(Base, UUIDMixin, TimestampMixin):
    """
    5-dimension trust review. Both client→agent and agent→client reviews
    are supported via reviewer_id / reviewee_id.
    """
    __tablename__ = "reviews"

    task_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tasks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    reviewer_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    reviewee_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # Ratings 1-5
    overall_rating: Mapped[int] = mapped_column(Integer, nullable=False)
    punctuality: Mapped[int] = mapped_column(Integer, nullable=False)
    trustworthiness: Mapped[int] = mapped_column(Integer, nullable=False)
    communication: Mapped[int] = mapped_column(Integer, nullable=False)
    professionalism: Mapped[int] = mapped_column(Integer, nullable=False)

    comment: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_public: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    # Computed weighted score stored for fast querying
    weighted_score: Mapped[float] = mapped_column(Numeric(4, 2), nullable=False, default=0)

    reviewer: Mapped["User"] = relationship(
        "User", foreign_keys=[reviewer_id], lazy="select"
    )
    reviewee: Mapped["User"] = relationship(
        "User", foreign_keys=[reviewee_id], lazy="select"
    )

    def compute_weighted_score(self) -> float:
        """
        Weighted average:
        - overall_rating:    30%
        - trustworthiness:   25%
        - professionalism:   20%
        - punctuality:       15%
        - communication:     10%
        """
        return round(
            self.overall_rating * 0.30
            + self.trustworthiness * 0.25
            + self.professionalism * 0.20
            + self.punctuality * 0.15
            + self.communication * 0.10,
            2,
        )

    def __repr__(self) -> str:
        return f"<Review task={self.task_id} score={self.overall_rating}>"


# ─── Dispute ──────────────────────────────────────────────────────────────────

class DisputeStatus(str, enum.Enum):
    OPEN = "open"
    UNDER_REVIEW = "under_review"
    RESOLVED_REFUND = "resolved_refund"       # Client refunded
    RESOLVED_RELEASE = "resolved_release"     # Agent paid
    RESOLVED_PARTIAL = "resolved_partial"     # Split resolution
    CLOSED = "closed"


class Dispute(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "disputes"

    task_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tasks.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )
    raised_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    reason: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    evidence_urls: Mapped[str | None] = mapped_column(Text, nullable=True)  # JSON array

    status: Mapped[DisputeStatus] = mapped_column(
        SAEnum(DisputeStatus, name="dispute_status"),
        default=DisputeStatus.OPEN,
        nullable=False,
        index=True,
    )
    resolved_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    resolution_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    resolved_at: Mapped[str | None] = mapped_column(String(50), nullable=True)

    def __repr__(self) -> str:
        return f"<Dispute task={self.task_id} status={self.status}>"


# ─── Notification ─────────────────────────────────────────────────────────────

class NotificationType(str, enum.Enum):
    TASK_POSTED = "task_posted"
    AGENT_APPLIED = "agent_applied"
    APPLICATION_ACCEPTED = "application_accepted"
    APPLICATION_REJECTED = "application_rejected"
    TASK_STARTED = "task_started"
    PROOF_SUBMITTED = "proof_submitted"
    TASK_COMPLETED = "task_completed"
    PAYMENT_RECEIVED = "payment_received"
    PAYMENT_RELEASED = "payment_released"
    REVIEW_RECEIVED = "review_received"
    LEVEL_UP = "level_up"
    VERIFICATION_APPROVED = "verification_approved"
    VERIFICATION_REJECTED = "verification_rejected"
    DISPUTE_RAISED = "dispute_raised"
    DISPUTE_RESOLVED = "dispute_resolved"


class Notification(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "notifications"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    type: Mapped[NotificationType] = mapped_column(
        SAEnum(NotificationType, name="notification_type"),
        nullable=False,
        index=True,
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    data: Mapped[str | None] = mapped_column(Text, nullable=True)   # JSON payload
    is_read: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    sent_push: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    def __repr__(self) -> str:
        return f"<Notification user={self.user_id} type={self.type} read={self.is_read}>"
