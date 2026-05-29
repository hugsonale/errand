import uuid
import enum
from sqlalchemy import String, Boolean, Enum as SAEnum, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base
from app.models.base import UUIDMixin, TimestampMixin


class UserRole(str, enum.Enum):
    CLIENT = "client"
    AGENT = "agent"
    BUSINESS = "business"
    ADMIN = "admin"


class User(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "users"

    # Contact
    email: Mapped[str | None] = mapped_column(
        String(255), unique=True, nullable=True, index=True
    )
    phone: Mapped[str] = mapped_column(
        String(20), unique=True, nullable=False, index=True
    )
    phone_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    # Identity
    full_name: Mapped[str] = mapped_column(String(100), nullable=False)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    role: Mapped[UserRole] = mapped_column(
        SAEnum(UserRole, name="user_role"),
        nullable=False,
        default=UserRole.CLIENT,
    )

    # Status
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    # Media
    avatar_url: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Push notifications
    fcm_token: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Relationships
    agent_profile: Mapped["AgentProfile"] = relationship(
        "AgentProfile", back_populates="user", uselist=False, lazy="select"
    )
    refresh_tokens: Mapped[list["RefreshToken"]] = relationship(
        "RefreshToken", back_populates="user", lazy="select"
    )
    otp_codes: Mapped[list["OTPCode"]] = relationship(
        "OTPCode", back_populates="user", lazy="select"
    )

    def __repr__(self) -> str:
        return f"<User {self.phone} [{self.role}]>"
