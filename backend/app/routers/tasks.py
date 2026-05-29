import uuid
from fastapi import APIRouter, Depends, UploadFile, File, Form, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Annotated
from app.database import get_db
from app.schemas.task import (CreateTaskRequest, TaskResponse, TaskDetailResponse, TaskListResponse, ApplyToTaskRequest, ApplicationResponse, TaskFilters, ConfirmCompletionRequest, RaiseDisputeRequest, ClientSummary)
from app.schemas.agent import AgentProfileResponse
from app.schemas.auth import SuccessResponse
from app.services.task_service import task_service
from app.services.s3_service import s3_service
from app.core.dependencies import VerifiedUser, AgentUser, ClientUser
from app.models.task import TaskCategory, TaskStatus

router = APIRouter(prefix="/tasks", tags=["Tasks"])


@router.post("/", response_model=TaskResponse, status_code=201, summary="Post a new task")
async def create_task(data: CreateTaskRequest, current_user: ClientUser, db: Annotated[AsyncSession, Depends(get_db)]):
    task = await task_service.create_task(db, current_user, data)
    return TaskResponse.model_validate(task)


@router.get("/nearby-agents", response_model=list[AgentProfileResponse], summary="Get nearby available agents")
async def nearby_agents(current_user: VerifiedUser, db: Annotated[AsyncSession, Depends(get_db)], lat: float = Query(...), lng: float = Query(...), radius_km: float = Query(default=5.0)):
    agents = await task_service.get_nearby_agents(db, lat, lng, radius_km)
    return [AgentProfileResponse.model_validate(a) for a in agents]


@router.get("/", response_model=TaskListResponse, summary="List tasks")
async def list_tasks(
    current_user: VerifiedUser, db: Annotated[AsyncSession, Depends(get_db)],
    category: TaskCategory | None = Query(default=None),
    status: TaskStatus | None = Query(default=None),
    is_emergency: bool | None = Query(default=None),
    lat: float | None = Query(default=None), lng: float | None = Query(default=None),
    radius_km: float = Query(default=10.0),
    min_budget: float | None = Query(default=None), max_budget: float | None = Query(default=None),
    page: int = Query(default=1, ge=1), page_size: int = Query(default=20, le=50),
):
    filters = TaskFilters(category=category, status=status, is_emergency=is_emergency, lat=lat, lng=lng, radius_km=radius_km, min_budget=min_budget, max_budget=max_budget, page=page, page_size=page_size)
    return await task_service.list_tasks(db, filters, current_user)


@router.get("/{task_id}", response_model=TaskDetailResponse, summary="Get task details")
async def get_task(task_id: uuid.UUID, current_user: VerifiedUser, db: Annotated[AsyncSession, Depends(get_db)]):
    task = await task_service.get_task(db, task_id)
    app_responses = []
    for app in (task.applications or []):
        agent_profile = app.agent
        agent_user = agent_profile.user if agent_profile else None
        app_responses.append(ApplicationResponse(
            id=app.id, task_id=app.task_id, agent_id=app.agent_id,
            proposed_price=float(app.proposed_price), message=app.message,
            eta_minutes=app.eta_minutes, status=app.status, created_at=app.created_at,
            agent_trust_level=agent_profile.trust_level.value if agent_profile else None,
            agent_trust_score=float(agent_profile.trust_score) if agent_profile else None,
            agent_completed_tasks=agent_profile.completed_tasks if agent_profile else None,
            agent_name=agent_user.full_name if agent_user else None,
            agent_avatar_url=s3_service.build_public_url(agent_user.avatar_url) if agent_user and agent_user.avatar_url else None,
        ))
    client_summary = ClientSummary(id=task.client.id, full_name=task.client.full_name, avatar_url=s3_service.build_public_url(task.client.avatar_url) if task.client and task.client.avatar_url else None) if task.client else None
    return TaskDetailResponse(
        id=task.id, title=task.title, description=task.description, category=task.category,
        status=task.status, is_emergency=task.is_emergency, budget=float(task.budget),
        final_price=float(task.final_price) if task.final_price else None,
        pickup_address=task.pickup_address, pickup_lat=float(task.pickup_lat), pickup_lng=float(task.pickup_lng),
        destination_address=task.destination_address, gender_preference=task.gender_preference,
        preferred_agents_only=task.preferred_agents_only, special_instructions=task.special_instructions,
        scheduled_at=task.scheduled_at, accepted_at=task.accepted_at, started_at=task.started_at,
        completed_at=task.completed_at, created_at=task.created_at, client_id=task.client_id,
        agent_id=task.agent_id, application_count=len(app_responses), client=client_summary, applications=app_responses,
    )


@router.post("/{task_id}/apply", response_model=ApplicationResponse, status_code=201, summary="Agent applies to task")
async def apply_to_task(task_id: uuid.UUID, data: ApplyToTaskRequest, current_user: AgentUser, db: Annotated[AsyncSession, Depends(get_db)]):
    application = await task_service.apply_to_task(db, current_user, task_id, data)
    return ApplicationResponse(id=application.id, task_id=application.task_id, agent_id=application.agent_id, proposed_price=float(application.proposed_price), message=application.message, eta_minutes=application.eta_minutes, status=application.status, created_at=application.created_at)


@router.post("/{task_id}/accept/{application_id}", response_model=TaskResponse, summary="Client selects agent")
async def accept_application(task_id: uuid.UUID, application_id: uuid.UUID, current_user: ClientUser, db: Annotated[AsyncSession, Depends(get_db)]):
    task = await task_service.accept_application(db, current_user, task_id, application_id)
    return TaskResponse.model_validate(task)


@router.post("/{task_id}/start", response_model=TaskResponse, summary="Agent starts task")
async def start_task(task_id: uuid.UUID, current_user: AgentUser, db: Annotated[AsyncSession, Depends(get_db)]):
    task = await task_service.start_task(db, current_user, task_id)
    return TaskResponse.model_validate(task)


@router.post("/{task_id}/complete", response_model=TaskResponse, summary="Agent submits proof")
async def submit_proof(task_id: uuid.UUID, current_user: AgentUser, db: Annotated[AsyncSession, Depends(get_db)], notes: str | None = Form(default=None), photos: list[UploadFile] = File(default=[])):
    photo_keys = []
    for photo in photos[:3]:
        key = await s3_service.upload_file(photo, folder=f"proofs/{task_id}", allowed_types={"image/jpeg", "image/png", "image/webp"})
        photo_keys.append(key)
    task = await task_service.submit_proof(db, current_user, task_id, photo_keys, notes)
    return TaskResponse.model_validate(task)


@router.post("/{task_id}/confirm", response_model=TaskResponse, summary="Client confirms completion")
async def confirm_completion(task_id: uuid.UUID, data: ConfirmCompletionRequest, current_user: ClientUser, db: Annotated[AsyncSession, Depends(get_db)]):
    task = await task_service.confirm_completion(db, current_user, task_id, data)
    return TaskResponse.model_validate(task)


@router.delete("/{task_id}", response_model=TaskResponse, summary="Cancel task")
async def cancel_task(task_id: uuid.UUID, current_user: VerifiedUser, db: Annotated[AsyncSession, Depends(get_db)]):
    task = await task_service.cancel_task(db, current_user, task_id)
    return TaskResponse.model_validate(task)


@router.post("/{task_id}/dispute", response_model=TaskResponse, summary="Raise dispute")
async def raise_dispute(task_id: uuid.UUID, data: RaiseDisputeRequest, current_user: VerifiedUser, db: Annotated[AsyncSession, Depends(get_db)]):
    task = await task_service.raise_dispute(db, current_user, task_id, data)
    return TaskResponse.model_validate(task)
