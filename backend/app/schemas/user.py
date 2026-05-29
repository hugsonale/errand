import uuid
from datetime import datetime
from pydantic import BaseModel, EmailStr
from app.models.user import UserRole


class UserResponse(BaseModel):
    id: uuid.UUID
    full_name: str
    phone: str
    email: str | None
    role: UserRole
    is_verified: bool
    phone_verified: bool
    avatar_url: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class UpdateProfileRequest(BaseModel):
    full_name: str | None = None
    email: str | None = None
    fcm_token: str | None = None


class AvatarUploadResponse(BaseModel):
    avatar_url: str
    message: str = "Avatar updated successfully"
