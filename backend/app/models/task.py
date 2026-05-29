import uuid
import enum
from sqlalchemy import (
    String, Boolean, Enum as SAEnum, Text,
    Numeric, Integer, ForeignKey
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base
from app.models.base import UUIDMixin, TimestampMixin


class TaskCategory(str, enum.Enum):
    SHOPPING = "shopping"
    FOOD_PICKUP = "food_pickup"
    CLEANING = "cleaning"
    DELIVERY = "delivery"
    OFFICE_ERRAND = "office_errand"
    CAR_WASH = "car_wash"
    DOCUMENT_SUBMISSION = "document_submission"
    PHARMACY = "pharmacy"
    MARKET_SHOPPING = "market_shopping"
    PERSONAL_ASSISTANCE = "personal_assistance"
    QUEUE_STANDING = "queue_standing"
    MOVING_ITEMS = "moving_items"
    COOKING_HELP = "cooking_help"
    ELDERLY_CARE = "elderly_care"
    CUSTOM = "custom"


class TaskStatus(str, enum.Enum):
    POSTED = "posted"
    AGENTS_APPLIED = "agents_applied"
    ACCEPTED = "accepted"
    IN_PROGRESS = "in_progress"
    PROOF_SUBMITTED = "proof_submitted"
    COMPLETED = "completed"
    DISPUTED = "disputed"
    CANCELLED = "cancelled"
    EXPIRED = "expired"


class ApplicationStatus(str, enum.Enum):
    PENDING = "pending"
    ACCEPTED = "accepted"
    REJECTED = "rejected"
    WITHDRAWN = "withdrawn"


class GenderPreference(str, enum.Enum):
    ANY = "any"
    FEMALE = "female"
    MALE = "male"


class Task(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "tasks"

    client_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    agent_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("agent_profiles.id", ondelete="SET NULL"),
        nullable=True, index=True,
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    category: Mapped[TaskCategory] = mapped_column(
        SAEnum(TaskCategory, name="task_category"), nullable=False, index=True,
    )
    special_instructions: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[TaskStatus] = mapped_column(
        SAEnum(TaskStatus, name="task_status"),
        default=TaskStatus.POSTED, nullable=False, index=True,
    )
    is_emergency: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    emergency_fee: Mapped[float] = mapped_column(Numeric(12, 2), default=0.0)
    budget: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    final_price: Mapped[float | None] = mapped_column(Numeric(12, 2), nullable=True)
    pickup_address: Mapped[str] = mapped_column(Text, nullable=False)
    pickup_lat: Mapped[float] = mapped_column(Numeric(10, 8), nullable=False)
    pickup_lng: Mapped[float] = mapped_column(Numeric(11, 8), nullable=False)
    destination_address: Mapped[str | None] = mapped_column(Text, nullable=True)
    destination_lat: Mapped[float | None] = mapped_column(Numeric(10, 8), nullable=True)
    destination_lng: Mapped[float | None] = mapped_column(Numeric(11, 8), nullable=True)
    gender_preference: Mapped[GenderPreference] = mapped_column(
        SAEnum(GenderPreference, name="gender_preference"),
        default=GenderPreference.ANY, nullable=False,
    )
    preferred_agents_only: Mapped[bool] = mapped_column(Boolean, default=False)
    scheduled_at: Mapped[str | None] = mapped_column(String(50), nullable=True)
    accepted_at: Mapped[str | None] = mapped_column(String(50), nullable=True)
    started_at: Mapped[str | None] = mapped_column(String(50), nullable=True)
    completed_at: Mapped[str | None] = mapped_column(String(50), nullable=True)
    expires_at: Mapped[str | None] = mapped_column(String(50), nullable=True)

    client: Mapped["User"] = relationship("User", foreign_keys=[client_id], lazy="select")
    agent: Mapped["AgentProfile"] = relationship("AgentProfile", foreign_keys=[agent_id], lazy="select")
    applications: Mapped[list["TaskApplication"]] = relationship("TaskApplication", back_populates="task", lazy="select")
    completion_proof: Mapped["CompletionProof"] = relationship("CompletionProof", back_populates="task", uselist=False, lazy="select")

    VALID_TRANSITIONS = {
        TaskStatus.POSTED: [TaskStatus.AGENTS_APPLIED, TaskStatus.CANCELLED, TaskStatus.EXPIRED],
        TaskStatus.AGENTS_APPLIED: [TaskStatus.ACCEPTED, TaskStatus.CANCELLED, TaskStatus.EXPIRED],
        TaskStatus.ACCEPTED: [TaskStatus.IN_PROGRESS, TaskStatus.CANCELLED, TaskStatus.DISPUTED],
        TaskStatus.IN_PROGRESS: [TaskStatus.PROOF_SUBMITTED, TaskStatus.DISPUTED],
        TaskStatus.PROOF_SUBMITTED: [TaskStatus.COMPLETED, TaskStatus.DISPUTED],
        TaskStatus.COMPLETED: [],
        TaskStatus.DISPUTED: [TaskStatus.COMPLETED, TaskStatus.CANCELLED],
        TaskStatus.CANCELLED: [],
        TaskStatus.EXPIRED: [],
    }

    def can_transition_to(self, new_status: TaskStatus) -> bool:
        return new_status in self.VALID_TRANSITIONS.get(self.status, [])

    def __repr__(self) -> str:
        return f"<Task {self.title[:30]} [{self.status}]>"


class TaskApplication(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "task_applications"

    task_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tasks.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    agent_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("agent_profiles.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    proposed_price: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    message: Mapped[str | None] = mapped_column(Text, nullable=True)
    eta_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    status: Mapped[ApplicationStatus] = mapped_column(
        SAEnum(ApplicationStatus, name="application_status"),
        default=ApplicationStatus.PENDING, nullable=False, index=True,
    )

    task: Mapped["Task"] = relationship("Task", back_populates="applications")
    agent: Mapped["AgentProfile"] = relationship("AgentProfile", lazy="select")


class CompletionProof(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "completion_proofs"

    task_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tasks.id", ondelete="CASCADE"),
        unique=True, nullable=False, index=True,
    )
    photo_urls: Mapped[str | None] = mapped_column(Text, nullable=True)
    video_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    otp_code: Mapped[str | None] = mapped_column(String(6), nullable=True)
    otp_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    otp_verified_at: Mapped[str | None] = mapped_column(String(50), nullable=True)

    task: Mapped["Task"] = relationship("Task", back_populates="completion_proof")
