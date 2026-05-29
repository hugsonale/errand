import uuid
import enum
from sqlalchemy import (
    String, Boolean, Enum as SAEnum, Text,
    Numeric, Integer, ForeignKey, ARRAY
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base
from app.models.base import UUIDMixin, TimestampMixin


class TrustLevel(str, enum.Enum):
    BRONZE = "bronze"
    SILVER = "silver"
    GOLD = "gold"
    PLATINUM = "platinum"


class VerificationStatus(str, enum.Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    RESUBMITTED = "resubmitted"


class AgentProfile(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "agent_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )

    # Trust system
    trust_level: Mapped[TrustLevel] = mapped_column(
        SAEnum(TrustLevel, name="trust_level"),
        default=TrustLevel.BRONZE,
        nullable=False,
    )
    trust_score: Mapped[float] = mapped_column(
        Numeric(4, 2), default=0.0, nullable=False
    )

    # Performance stats
    total_tasks: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    completed_tasks: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    cancelled_tasks: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    success_rate: Mapped[float] = mapped_column(
        Numeric(5, 2), default=0.0, nullable=False
    )
    punctuality_rate: Mapped[float] = mapped_column(
        Numeric(5, 2), default=0.0, nullable=False
    )
    repeat_client_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    # Profile
    bio: Mapped[str | None] = mapped_column(Text, nullable=True)
    skill_tags: Mapped[list[str] | None] = mapped_column(ARRAY(String), nullable=True)
    years_active: Mapped[float] = mapped_column(Numeric(4, 1), default=0.0)

    # Availability and location
    is_available: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    current_lat: Mapped[float | None] = mapped_column(Numeric(10, 8), nullable=True)
    current_lng: Mapped[float | None] = mapped_column(Numeric(11, 8), nullable=True)

    # Gender preference agents offer (for client filtering)
    gender: Mapped[str | None] = mapped_column(String(10), nullable=True)

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="agent_profile")
    verification: Mapped["AgentVerification"] = relationship(
        "AgentVerification", back_populates="agent", uselist=False, lazy="select"
    )

    def compute_trust_level(self) -> TrustLevel:
        """
        Trust level thresholds:
        Bronze:   < 10 tasks  OR score < 3.5
        Silver:   10+ tasks   AND score >= 3.5
        Gold:     50+ tasks   AND score >= 4.2
        Platinum: 100+ tasks  AND score >= 4.7
        """
        if self.completed_tasks >= 100 and float(self.trust_score) >= 4.7:
            return TrustLevel.PLATINUM
        elif self.completed_tasks >= 50 and float(self.trust_score) >= 4.2:
            return TrustLevel.GOLD
        elif self.completed_tasks >= 10 and float(self.trust_score) >= 3.5:
            return TrustLevel.SILVER
        else:
            return TrustLevel.BRONZE

    def __repr__(self) -> str:
        return f"<AgentProfile user={self.user_id} level={self.trust_level}>"


class AgentVerification(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "agent_verifications"

    agent_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("agent_profiles.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )

    # NIN (National Identification Number — Nigeria)
    nin_number: Mapped[str | None] = mapped_column(String(20), nullable=True)
    nin_doc_url: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Supporting documents
    selfie_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    address_doc_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    address_text: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Guarantor
    guarantor_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    guarantor_phone: Mapped[str | None] = mapped_column(String(20), nullable=True)
    guarantor_relationship: Mapped[str | None] = mapped_column(String(50), nullable=True)

    # BVN (Bank Verification Number)
    bvn_number: Mapped[str | None] = mapped_column(String(20), nullable=True)

    # Review state
    status: Mapped[VerificationStatus] = mapped_column(
        SAEnum(VerificationStatus, name="verification_status"),
        default=VerificationStatus.PENDING,
        nullable=False,
        index=True,
    )
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    rejection_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    submission_count: Mapped[int] = mapped_column(Integer, default=1, nullable=False)

    # Relationships
    agent: Mapped["AgentProfile"] = relationship(
        "AgentProfile", back_populates="verification"
    )

    def __repr__(self) -> str:
        return f"<AgentVerification agent={self.agent_id} status={self.status}>"
