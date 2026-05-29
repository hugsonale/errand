from fastapi import APIRouter, Depends, UploadFile, File
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.schemas.user import UserResponse, UpdateProfileRequest, AvatarUploadResponse
from app.services.user_service import user_service
from app.core.dependencies import CurrentUser, VerifiedUser

router = APIRouter(prefix="/users", tags=["Users"])


@router.get(
    "/me",
    response_model=UserResponse,
    summary="Get current user profile",
)
async def get_me(current_user: CurrentUser):
    return UserResponse.model_validate(current_user)


@router.patch(
    "/me",
    response_model=UserResponse,
    summary="Update profile",
    description="Update full name, email, or FCM push token.",
)
async def update_me(
    data: UpdateProfileRequest,
    current_user: VerifiedUser,
    db: AsyncSession = Depends(get_db),
):
    updated = await user_service.update_profile(db, current_user, data)
    return UserResponse.model_validate(updated)


@router.post(
    "/me/avatar",
    response_model=AvatarUploadResponse,
    summary="Upload profile avatar",
    description="Accepts JPEG, PNG, or WebP images up to 10MB.",
)
async def upload_avatar(
    current_user: VerifiedUser,
    db: AsyncSession = Depends(get_db),
    file: UploadFile = File(..., description="Image file (JPEG/PNG/WebP, max 10MB)"),
):
    url = await user_service.upload_avatar(db, current_user, file)
    return AvatarUploadResponse(avatar_url=url)
