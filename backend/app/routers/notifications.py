import uuid
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, func
from typing import Annotated

from app.database import get_db
from app.schemas.payment import NotificationListResponse, NotificationResponse
from app.schemas.auth import SuccessResponse
from app.models.payment import Notification
from app.core.dependencies import VerifiedUser

router = APIRouter(prefix="/notifications", tags=["Notifications"])


@router.get(
    "/",
    response_model=NotificationListResponse,
    summary="Get notifications for current user",
)
async def get_notifications(
    current_user: VerifiedUser,
    db: Annotated[AsyncSession, Depends(get_db)],
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=30, le=50),
    unread_only: bool = Query(default=False),
):
    query = select(Notification).where(Notification.user_id == current_user.id)
    if unread_only:
        query = query.where(Notification.is_read == False)

    # Count unread
    unread_result = await db.execute(
        select(func.count()).where(
            Notification.user_id == current_user.id,
            Notification.is_read == False,
        )
    )
    unread_count = unread_result.scalar_one()

    # Total
    total_result = await db.execute(
        select(func.count()).where(Notification.user_id == current_user.id)
    )
    total = total_result.scalar_one()

    # Paginate
    offset = (page - 1) * page_size
    result = await db.execute(
        query.order_by(Notification.created_at.desc())
        .offset(offset)
        .limit(page_size)
    )
    notifications = result.scalars().all()

    return NotificationListResponse(
        notifications=[NotificationResponse.model_validate(n) for n in notifications],
        unread_count=unread_count,
        total=total,
    )


@router.post(
    "/{notification_id}/read",
    response_model=SuccessResponse,
    summary="Mark a notification as read",
)
async def mark_read(
    notification_id: uuid.UUID,
    current_user: VerifiedUser,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    await db.execute(
        update(Notification)
        .where(
            Notification.id == notification_id,
            Notification.user_id == current_user.id,
        )
        .values(is_read=True)
    )
    return SuccessResponse(message="Marked as read.")


@router.post(
    "/read-all",
    response_model=SuccessResponse,
    summary="Mark all notifications as read",
)
async def mark_all_read(
    current_user: VerifiedUser,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    await db.execute(
        update(Notification)
        .where(
            Notification.user_id == current_user.id,
            Notification.is_read == False,
        )
        .values(is_read=True)
    )
    return SuccessResponse(message="All notifications marked as read.")
