import uuid
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from sqlalchemy.orm import selectinload

from app.core.exceptions import BadRequestError, NotFoundError, ForbiddenError, ConflictError
from app.models.user import User, UserRole
from app.models.task import Task, TaskStatus
from app.models.agent_profile import AgentProfile, TrustLevel
from app.models.payment import Review
from app.schemas.payment import (
    SubmitReviewRequest, ReviewResponse,
    AgentReviewsResponse, TrustScoreBreakdown,
)
from app.services.notification_service import notification_service


class ReviewService:

    async def submit_review(
        self, db: AsyncSession, reviewer: User, data: SubmitReviewRequest
    ) -> Review:
        """
        Submits a review after task completion.
        - Clients review agents
        - Agents review clients (future)
        Both need a completed task together.
        """
        # Load the task
        result = await db.execute(
            select(Task).where(Task.id == data.task_id)
            .options(selectinload(Task.agent))
        )
        task = result.scalar_one_or_none()
        if not task:
            raise NotFoundError("Task")

        if task.status != TaskStatus.COMPLETED:
            raise BadRequestError("You can only review completed tasks.")

        # Determine reviewee
        if reviewer.role in (UserRole.CLIENT, UserRole.BUSINESS):
            if task.client_id != reviewer.id:
                raise ForbiddenError("You are not the client for this task.")
            # Client reviews the agent
            if not task.agent_id:
                raise BadRequestError("No agent assigned to review.")
            # Get agent's user_id
            agent_result = await db.execute(
                select(AgentProfile).where(AgentProfile.id == task.agent_id)
            )
            agent_profile = agent_result.scalar_one_or_none()
            if not agent_profile:
                raise NotFoundError("Agent")
            reviewee_id = agent_profile.user_id

        else:
            # Agent reviews the client
            agent_result = await db.execute(
                select(AgentProfile).where(AgentProfile.user_id == reviewer.id)
            )
            agent_profile = agent_result.scalar_one_or_none()
            if not agent_profile or task.agent_id != agent_profile.id:
                raise ForbiddenError("You are not the assigned agent for this task.")
            reviewee_id = task.client_id

        # Prevent duplicate reviews
        existing = await db.execute(
            select(Review).where(
                Review.task_id == data.task_id,
                Review.reviewer_id == reviewer.id,
            )
        )
        if existing.scalar_one_or_none():
            raise ConflictError("You have already reviewed this task.")

        # Create review
        review = Review(
            task_id=data.task_id,
            reviewer_id=reviewer.id,
            reviewee_id=reviewee_id,
            overall_rating=data.overall_rating,
            punctuality=data.punctuality,
            trustworthiness=data.trustworthiness,
            communication=data.communication,
            professionalism=data.professionalism,
            comment=data.comment,
        )
        review.weighted_score = review.compute_weighted_score()
        db.add(review)
        await db.flush()

        # Update agent trust score if this is a client→agent review
        if reviewer.role in (UserRole.CLIENT, UserRole.BUSINESS):
            old_level = agent_profile.trust_level
            await self._update_agent_trust_score(db, agent_profile)
            new_level = agent_profile.trust_level

            # Fire notifications
            await notification_service.review_received(
                db,
                agent_id=agent_profile.user_id,
                rating=data.overall_rating,
                task_title=task.title,
            )

            # Level-up notification if level changed
            if new_level != old_level:
                await notification_service.level_up(
                    db,
                    agent_id=agent_profile.user_id,
                    new_level=new_level.value,
                )

        return review

    async def _update_agent_trust_score(
        self, db: AsyncSession, agent_profile: AgentProfile
    ) -> None:
        """
        Recomputes the agent's trust score from all their reviews.
        Uses recency-weighted average — recent reviews count more.
        Also recomputes trust level.
        """
        # Get all reviews for this agent
        result = await db.execute(
            select(Review)
            .join(Task, Review.task_id == Task.id)
            .where(Task.agent_id == agent_profile.id)
            .order_by(Review.created_at.desc())
        )
        reviews = result.scalars().all()

        if not reviews:
            return

        # Recency-weighted: most recent review has full weight,
        # older reviews decay by 0.95 per position
        total_weight = 0.0
        weighted_sum = 0.0
        decay = 0.95

        for i, review in enumerate(reviews):
            weight = decay ** i
            weighted_sum += float(review.weighted_score) * weight
            total_weight += weight

        new_score = round(weighted_sum / total_weight, 2) if total_weight > 0 else 0.0
        agent_profile.trust_score = new_score

        # Recompute punctuality rate from punctuality ratings
        punct_avg = sum(r.punctuality for r in reviews) / len(reviews)
        agent_profile.punctuality_rate = round((punct_avg / 5.0) * 100, 2)

        # Recompute trust level
        agent_profile.trust_level = agent_profile.compute_trust_level()

        await db.flush()

    async def get_agent_reviews(
        self,
        db: AsyncSession,
        agent_user_id: uuid.UUID,
        page: int = 1,
        page_size: int = 10,
    ) -> AgentReviewsResponse:
        """Returns paginated reviews for an agent with score breakdown."""
        result = await db.execute(
            select(Review)
            .join(Task, Review.task_id == Task.id)
            .join(AgentProfile, Task.agent_id == AgentProfile.id)
            .where(AgentProfile.user_id == agent_user_id)
            .options(selectinload(Review.reviewer))
            .order_by(Review.created_at.desc())
        )
        all_reviews = result.scalars().all()
        total = len(all_reviews)

        # Paginate
        offset = (page - 1) * page_size
        page_reviews = all_reviews[offset: offset + page_size]

        # Compute averages
        if all_reviews:
            avg_score = sum(float(r.weighted_score) for r in all_reviews) / total
            breakdown = {
                "overall": sum(r.overall_rating for r in all_reviews) / total,
                "punctuality": sum(r.punctuality for r in all_reviews) / total,
                "trustworthiness": sum(r.trustworthiness for r in all_reviews) / total,
                "communication": sum(r.communication for r in all_reviews) / total,
                "professionalism": sum(r.professionalism for r in all_reviews) / total,
            }
            breakdown = {k: round(v, 2) for k, v in breakdown.items()}
        else:
            avg_score = 0.0
            breakdown = {d: 0.0 for d in
                         ["overall", "punctuality", "trustworthiness",
                          "communication", "professionalism"]}

        return AgentReviewsResponse(
            reviews=[ReviewResponse.model_validate(r) for r in page_reviews],
            total=total,
            average_score=round(avg_score, 2),
            breakdown=breakdown,
        )

    async def get_trust_score_breakdown(
        self, db: AsyncSession, agent_user_id: uuid.UUID
    ) -> TrustScoreBreakdown:
        """Returns the full trust score breakdown for an agent's profile page."""
        agent_result = await db.execute(
            select(AgentProfile).where(AgentProfile.user_id == agent_user_id)
        )
        agent = agent_result.scalar_one_or_none()
        if not agent:
            raise NotFoundError("Agent profile")

        reviews_data = await self.get_agent_reviews(db, agent_user_id, page_size=1000)

        return TrustScoreBreakdown(
            agent_id=agent_user_id,
            trust_score=float(agent.trust_score),
            trust_level=agent.trust_level.value,
            total_reviews=reviews_data.total,
            average_overall=reviews_data.breakdown.get("overall", 0.0),
            average_punctuality=reviews_data.breakdown.get("punctuality", 0.0),
            average_trustworthiness=reviews_data.breakdown.get("trustworthiness", 0.0),
            average_communication=reviews_data.breakdown.get("communication", 0.0),
            average_professionalism=reviews_data.breakdown.get("professionalism", 0.0),
            completed_tasks=agent.completed_tasks,
            success_rate=float(agent.success_rate),
            repeat_client_count=agent.repeat_client_count,
        )


review_service = ReviewService()
