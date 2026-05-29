import uuid, json, secrets
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_
from sqlalchemy.orm import selectinload
from app.core.exceptions import BadRequestError, NotFoundError, ForbiddenError, ConflictError
from app.models.user import User, UserRole
from app.models.task import Task, TaskApplication, CompletionProof, TaskStatus, ApplicationStatus, GenderPreference
from app.models.agent_profile import AgentProfile, VerificationStatus
from app.schemas.task import CreateTaskRequest, ApplyToTaskRequest, TaskListResponse, TaskResponse, TaskFilters, ConfirmCompletionRequest, RaiseDisputeRequest
from app.utils.helpers import haversine_distance, utc_now


class TaskService:

    async def create_task(self, db: AsyncSession, client: User, data: CreateTaskRequest) -> Task:
        task = Task(
            client_id=client.id,
            title=data.title,
            description=data.description,
            category=data.category,
            special_instructions=data.special_instructions,
            is_emergency=data.is_emergency,
            budget=data.budget,
            emergency_fee=data.budget * 0.15 if data.is_emergency else 0,
            pickup_address=data.pickup_address,
            pickup_lat=data.pickup_lat,
            pickup_lng=data.pickup_lng,
            destination_address=data.destination_address,
            destination_lat=data.destination_lat,
            destination_lng=data.destination_lng,
            gender_preference=data.gender_preference,
            preferred_agents_only=data.preferred_agents_only,
            scheduled_at=data.scheduled_at,
            status=TaskStatus.POSTED,
        )
        db.add(task)
        await db.flush()
        return task

    async def get_task(self, db: AsyncSession, task_id: uuid.UUID) -> Task:
        result = await db.execute(
            select(Task).where(Task.id == task_id)
            .options(
                selectinload(Task.client),
                selectinload(Task.applications).selectinload(TaskApplication.agent).selectinload(AgentProfile.user),
                selectinload(Task.completion_proof),
            )
        )
        task = result.scalar_one_or_none()
        if not task:
            raise NotFoundError("Task")
        return task

    async def list_tasks(self, db: AsyncSession, filters: TaskFilters, current_user: User) -> TaskListResponse:
        query = select(Task)
        if current_user.role in (UserRole.CLIENT, UserRole.BUSINESS):
            query = query.where(Task.client_id == current_user.id)
        else:
            query = query.where(Task.status.in_([TaskStatus.POSTED, TaskStatus.AGENTS_APPLIED]))
        if filters.category:
            query = query.where(Task.category == filters.category)
        if filters.status:
            query = query.where(Task.status == filters.status)
        if filters.is_emergency is not None:
            query = query.where(Task.is_emergency == filters.is_emergency)
        if filters.min_budget:
            query = query.where(Task.budget >= filters.min_budget)
        if filters.max_budget:
            query = query.where(Task.budget <= filters.max_budget)
        count_result = await db.execute(select(func.count()).select_from(query.subquery()))
        total = count_result.scalar_one()
        offset = (filters.page - 1) * filters.page_size
        query = query.order_by(Task.is_emergency.desc(), Task.created_at.desc()).offset(offset).limit(filters.page_size)
        result = await db.execute(query)
        tasks = list(result.scalars().all())
        if filters.lat and filters.lng and current_user.role == UserRole.AGENT:
            tasks = [t for t in tasks if haversine_distance(filters.lat, filters.lng, float(t.pickup_lat), float(t.pickup_lng)) <= filters.radius_km]
        task_responses = []
        for t in tasks:
            resp = TaskResponse.model_validate(t)
            resp.application_count = len(t.applications) if t.applications else 0
            task_responses.append(resp)
        return TaskListResponse(tasks=task_responses, total=total, page=filters.page, page_size=filters.page_size, has_more=(offset + filters.page_size) < total)

    async def apply_to_task(self, db: AsyncSession, agent_user: User, task_id: uuid.UUID, data: ApplyToTaskRequest) -> TaskApplication:
        profile_result = await db.execute(select(AgentProfile).where(AgentProfile.user_id == agent_user.id).options(selectinload(AgentProfile.verification)))
        profile = profile_result.scalar_one_or_none()
        if not profile:
            raise NotFoundError("Agent profile")
        if not profile.verification or profile.verification.status != VerificationStatus.APPROVED:
            raise ForbiddenError("You must complete identity verification before applying to tasks.")
        if not profile.is_available:
            raise ForbiddenError("Set yourself as available before applying to tasks.")
        task = await self.get_task(db, task_id)
        if task.status not in (TaskStatus.POSTED, TaskStatus.AGENTS_APPLIED):
            raise BadRequestError(f"This task is no longer accepting applications.")
        if task.client_id == agent_user.id:
            raise BadRequestError("You cannot apply to your own task.")
        existing = await db.execute(select(TaskApplication).where(and_(TaskApplication.task_id == task_id, TaskApplication.agent_id == profile.id, TaskApplication.status == ApplicationStatus.PENDING)))
        if existing.scalar_one_or_none():
            raise ConflictError("You have already applied to this task.")
        application = TaskApplication(task_id=task_id, agent_id=profile.id, proposed_price=data.proposed_price, message=data.message, eta_minutes=data.eta_minutes)
        db.add(application)
        if task.status == TaskStatus.POSTED:
            task.status = TaskStatus.AGENTS_APPLIED
        await db.flush()
        return application

    async def accept_application(self, db: AsyncSession, client: User, task_id: uuid.UUID, application_id: uuid.UUID) -> Task:
        task = await self.get_task(db, task_id)
        if task.client_id != client.id:
            raise ForbiddenError("You do not own this task.")
        if not task.can_transition_to(TaskStatus.ACCEPTED):
            raise BadRequestError(f"Cannot accept agent — task is currently {task.status.value}.")
        app_result = await db.execute(select(TaskApplication).where(and_(TaskApplication.id == application_id, TaskApplication.task_id == task_id)))
        application = app_result.scalar_one_or_none()
        if not application:
            raise NotFoundError("Application")
        if application.status != ApplicationStatus.PENDING:
            raise BadRequestError("This application is no longer pending.")
        application.status = ApplicationStatus.ACCEPTED
        task.agent_id = application.agent_id
        task.final_price = application.proposed_price
        task.status = TaskStatus.ACCEPTED
        task.accepted_at = utc_now().isoformat()
        others = await db.execute(select(TaskApplication).where(and_(TaskApplication.task_id == task_id, TaskApplication.id != application_id, TaskApplication.status == ApplicationStatus.PENDING)))
        for other in others.scalars().all():
            other.status = ApplicationStatus.REJECTED
        await db.flush()
        return task

    async def start_task(self, db: AsyncSession, agent_user: User, task_id: uuid.UUID) -> Task:
        task = await self.get_task(db, task_id)
        profile_result = await db.execute(select(AgentProfile).where(AgentProfile.user_id == agent_user.id))
        profile = profile_result.scalar_one_or_none()
        if not profile or task.agent_id != profile.id:
            raise ForbiddenError("You are not the assigned agent for this task.")
        if not task.can_transition_to(TaskStatus.IN_PROGRESS):
            raise BadRequestError(f"Cannot start task — current status is {task.status.value}.")
        task.status = TaskStatus.IN_PROGRESS
        task.started_at = utc_now().isoformat()
        await db.flush()
        return task

    async def submit_proof(self, db: AsyncSession, agent_user: User, task_id: uuid.UUID, photo_keys: list[str], notes: str | None) -> Task:
        task = await self.get_task(db, task_id)
        profile_result = await db.execute(select(AgentProfile).where(AgentProfile.user_id == agent_user.id))
        profile = profile_result.scalar_one_or_none()
        if not profile or task.agent_id != profile.id:
            raise ForbiddenError("You are not the assigned agent for this task.")
        if not task.can_transition_to(TaskStatus.PROOF_SUBMITTED):
            raise BadRequestError(f"Cannot submit proof — current status is {task.status.value}.")
        otp = "".join([str(secrets.randbelow(10)) for _ in range(6)])
        proof = CompletionProof(task_id=task_id, photo_urls=json.dumps(photo_keys), notes=notes, otp_code=otp, otp_verified=False)
        db.add(proof)
        task.status = TaskStatus.PROOF_SUBMITTED
        await db.flush()
        print(f"[DEV PROOF OTP] Task {task_id} | OTP: {otp}")
        return task

    async def confirm_completion(self, db: AsyncSession, client: User, task_id: uuid.UUID, data: ConfirmCompletionRequest) -> Task:
        task = await self.get_task(db, task_id)
        if task.client_id != client.id:
            raise ForbiddenError("You do not own this task.")
        if not task.can_transition_to(TaskStatus.COMPLETED):
            raise BadRequestError(f"Cannot confirm — task status is {task.status.value}.")
        proof = task.completion_proof
        if not proof:
            raise BadRequestError("No proof submitted yet.")
        if data.otp_code:
            if proof.otp_code != data.otp_code:
                raise BadRequestError("Incorrect confirmation code.")
            proof.otp_verified = True
            proof.otp_verified_at = utc_now().isoformat()
        task.status = TaskStatus.COMPLETED
        task.completed_at = utc_now().isoformat()
        if task.agent_id:
            agent_result = await db.execute(select(AgentProfile).where(AgentProfile.id == task.agent_id))
            agent_profile = agent_result.scalar_one_or_none()
            if agent_profile:
                agent_profile.completed_tasks += 1
                agent_profile.total_tasks += 1
                if agent_profile.total_tasks > 0:
                    agent_profile.success_rate = (agent_profile.completed_tasks / agent_profile.total_tasks) * 100
                agent_profile.trust_level = agent_profile.compute_trust_level()
        await db.flush()
        # Release escrow payment to agent
        try:
            from app.services.payment_service import payment_service
            await payment_service.release_to_agent(db, task_id)
        except Exception:
            pass  # Log but don't block — admin can release manually
        # Notify client to leave a review
        try:
            from app.services.notification_service import notification_service
            await notification_service.send(
                db, client.id,
                __import__('app.models.payment', fromlist=['NotificationType']).NotificationType.TASK_COMPLETED,
                title="Task complete! Leave a review ⭐",
                body=f"How did '{task.title}' go? Rate your agent.",
                data={"task_id": str(task_id), "screen": "review"},
            )
        except Exception:
            pass
        return task

    async def cancel_task(self, db: AsyncSession, user: User, task_id: uuid.UUID) -> Task:
        task = await self.get_task(db, task_id)
        if task.client_id != user.id and user.role != UserRole.ADMIN:
            raise ForbiddenError("Only the task owner or admin can cancel this task.")
        if not task.can_transition_to(TaskStatus.CANCELLED):
            raise BadRequestError(f"Task cannot be cancelled at this stage ({task.status.value}).")
        task.status = TaskStatus.CANCELLED
        await db.flush()
        return task

    async def raise_dispute(self, db: AsyncSession, user: User, task_id: uuid.UUID, data: RaiseDisputeRequest) -> Task:
        task = await self.get_task(db, task_id)
        profile_result = await db.execute(select(AgentProfile).where(AgentProfile.user_id == user.id))
        profile = profile_result.scalar_one_or_none()
        is_client = task.client_id == user.id
        is_agent = profile and task.agent_id == profile.id
        if not is_client and not is_agent:
            raise ForbiddenError("Only the client or assigned agent can raise a dispute.")
        if not task.can_transition_to(TaskStatus.DISPUTED):
            raise BadRequestError(f"Cannot dispute task in status: {task.status.value}.")
        task.status = TaskStatus.DISPUTED
        await db.flush()
        return task

    async def get_nearby_agents(self, db: AsyncSession, lat: float, lng: float, radius_km: float = 5.0, limit: int = 20) -> list[AgentProfile]:
        result = await db.execute(
            select(AgentProfile).where(and_(AgentProfile.is_available == True, AgentProfile.current_lat.isnot(None), AgentProfile.current_lng.isnot(None)))
            .options(selectinload(AgentProfile.user), selectinload(AgentProfile.verification))
        )
        all_agents = result.scalars().all()
        nearby = []
        for agent in all_agents:
            if not agent.verification or agent.verification.status != VerificationStatus.APPROVED:
                continue
            dist = haversine_distance(lat, lng, float(agent.current_lat), float(agent.current_lng))
            if dist <= radius_km:
                nearby.append((dist, agent))
        nearby.sort(key=lambda x: (-float(x[1].trust_score), x[0]))
        return [a for _, a in nearby[:limit]]


task_service = TaskService()
