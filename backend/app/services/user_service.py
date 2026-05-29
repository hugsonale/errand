import uuid
from fastapi import UploadFile
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.exceptions import NotFoundError
from app.models.user import User
from app.schemas.user import UpdateProfileRequest
from app.services.s3_service import s3_service, ALLOWED_IMAGE_TYPES


class UserService:

    async def get_by_id(self, db: AsyncSession, user_id: uuid.UUID) -> User:
        result = await db.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if not user:
            raise NotFoundError("User")
        return user

    async def update_profile(
        self,
        db: AsyncSession,
        user: User,
        data: UpdateProfileRequest,
    ) -> User:
        if data.full_name is not None:
            user.full_name = data.full_name.strip()
        if data.email is not None:
            user.email = data.email.lower().strip()
        if data.fcm_token is not None:
            user.fcm_token = data.fcm_token
        await db.flush()
        return user

    async def upload_avatar(
        self, db: AsyncSession, user: User, file: UploadFile
    ) -> str:
        """
        Uploads avatar to S3 under avatars/{user_id}/ folder.
        Returns presigned URL for immediate display.
        """
        key = await s3_service.upload_file(
            file,
            folder=f"avatars/{user.id}",
            allowed_types=ALLOWED_IMAGE_TYPES,
        )
        user.avatar_url = key
        await db.flush()
        return s3_service.build_public_url(key)


user_service = UserService()
