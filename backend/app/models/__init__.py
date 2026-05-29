# Import all models here so Alembic autogenerate can detect them
# Order matters — base models before dependent models

# Phase 1
from app.models.user import User, UserRole
from app.models.agent_profile import AgentProfile, AgentVerification, TrustLevel, VerificationStatus
from app.models.auth import OTPCode, RefreshToken

# Phase 2
from app.models.task import (
    Task, TaskApplication, CompletionProof,
    TaskCategory, TaskStatus, ApplicationStatus, GenderPreference
)

# Phase 3
from app.models.payment import (
    EscrowTransaction, EscrowStatus,
    Review, Dispute, DisputeStatus,
    Notification, NotificationType,
)

__all__ = [
    # Phase 1
    "User", "UserRole",
    "AgentProfile", "AgentVerification", "TrustLevel", "VerificationStatus",
    "OTPCode", "RefreshToken",
    # Phase 2
    "Task", "TaskApplication", "CompletionProof",
    "TaskCategory", "TaskStatus", "ApplicationStatus", "GenderPreference",
    # Phase 3
    "EscrowTransaction", "EscrowStatus",
    "Review", "Dispute", "DisputeStatus",
    "Notification", "NotificationType",
]
