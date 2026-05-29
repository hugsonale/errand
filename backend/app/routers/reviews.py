import uuid
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Annotated

from app.database import get_db
from app.schemas.payment import (
    SubmitReviewRequest, ReviewResponse,
    AgentReviewsResponse, TrustScoreBreakdown,
)
from app.services.review_service import review_service
from app.core.dependencies import VerifiedUser

router = APIRouter(prefix="/reviews", tags=["Reviews & Trust"])


@router.post(
    "/",
    response_model=ReviewResponse,
    status_code=201,
    summary="Submit a review after task completion",
    description=(
        "Clients review agents on 5 dimensions: overall, punctuality, "
        "trustworthiness, communication, and professionalism. "
        "Reviews trigger automatic trust score recalculation and "
        "level-up notification if applicable."
    ),
)
async def submit_review(
    data: SubmitReviewRequest,
    current_user: VerifiedUser,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    review = await review_service.submit_review(db, current_user, data)
    return ReviewResponse.model_validate(review)


@router.get(
    "/agent/{agent_user_id}",
    response_model=AgentReviewsResponse,
    summary="Get all reviews for an agent",
)
async def get_agent_reviews(
    agent_user_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=10, le=50),
):
    return await review_service.get_agent_reviews(
        db, agent_user_id, page=page, page_size=page_size
    )


@router.get(
    "/trust-score/{agent_user_id}",
    response_model=TrustScoreBreakdown,
    summary="Get full trust score breakdown for an agent",
    description="Returns the complete trust profile used on the agent profile screen.",
)
async def get_trust_score(
    agent_user_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    return await review_service.get_trust_score_breakdown(db, agent_user_id)
