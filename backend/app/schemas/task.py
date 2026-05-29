import uuid
from datetime import datetime
from pydantic import BaseModel, field_validator, model_validator
from app.models.task import TaskCategory, TaskStatus, ApplicationStatus, GenderPreference


class CreateTaskRequest(BaseModel):
    title: str
    description: str
    category: TaskCategory
    special_instructions: str | None = None
    is_emergency: bool = False
    budget: float
    pickup_address: str
    pickup_lat: float
    pickup_lng: float
    destination_address: str | None = None
    destination_lat: float | None = None
    destination_lng: float | None = None
    gender_preference: GenderPreference = GenderPreference.ANY
    preferred_agents_only: bool = False
    scheduled_at: str | None = None

    @field_validator("title")
    @classmethod
    def validate_title(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 5:
            raise ValueError("Title must be at least 5 characters")
        if len(v) > 200:
            raise ValueError("Title must be under 200 characters")
        return v

    @field_validator("budget")
    @classmethod
    def validate_budget(cls, v: float) -> float:
        if v < 500:
            raise ValueError("Minimum budget is ₦500")
        if v > 5_000_000:
            raise ValueError("Budget exceeds maximum allowed amount")
        return v

    @field_validator("description")
    @classmethod
    def validate_description(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 10:
            raise ValueError("Description must be at least 10 characters")
        return v

    @model_validator(mode="after")
    def validate_destination(self) -> "CreateTaskRequest":
        if self.destination_address and (
            self.destination_lat is None or self.destination_lng is None
        ):
            raise ValueError("Destination coordinates required when address is given")
        return self


class ClientSummary(BaseModel):
    id: uuid.UUID
    full_name: str
    avatar_url: str | None
    model_config = {"from_attributes": True}


class TaskResponse(BaseModel):
    id: uuid.UUID
    title: str
    description: str
    category: TaskCategory
    status: TaskStatus
    is_emergency: bool
    budget: float
    final_price: float | None
    pickup_address: str
    pickup_lat: float
    pickup_lng: float
    destination_address: str | None
    gender_preference: GenderPreference
    preferred_agents_only: bool
    special_instructions: str | None
    scheduled_at: str | None
    accepted_at: str | None
    started_at: str | None
    completed_at: str | None
    created_at: datetime
    client_id: uuid.UUID
    agent_id: uuid.UUID | None
    application_count: int = 0
    model_config = {"from_attributes": True}


class ApplicationResponse(BaseModel):
    id: uuid.UUID
    task_id: uuid.UUID
    agent_id: uuid.UUID
    proposed_price: float
    message: str | None
    eta_minutes: int | None
    status: ApplicationStatus
    created_at: datetime
    agent_trust_level: str | None = None
    agent_trust_score: float | None = None
    agent_completed_tasks: int | None = None
    agent_name: str | None = None
    agent_avatar_url: str | None = None
    model_config = {"from_attributes": True}


class TaskDetailResponse(TaskResponse):
    client: ClientSummary | None = None
    applications: list[ApplicationResponse] = []
    model_config = {"from_attributes": True}


class ApplyToTaskRequest(BaseModel):
    proposed_price: float
    message: str | None = None
    eta_minutes: int | None = None

    @field_validator("proposed_price")
    @classmethod
    def validate_price(cls, v: float) -> float:
        if v < 500:
            raise ValueError("Minimum proposed price is ₦500")
        return v


class TaskFilters(BaseModel):
    category: TaskCategory | None = None
    status: TaskStatus | None = None
    is_emergency: bool | None = None
    lat: float | None = None
    lng: float | None = None
    radius_km: float = 10.0
    min_budget: float | None = None
    max_budget: float | None = None
    page: int = 1
    page_size: int = 20

    @field_validator("page_size")
    @classmethod
    def cap_page_size(cls, v: int) -> int:
        return min(v, 50)


class TaskListResponse(BaseModel):
    tasks: list[TaskResponse]
    total: int
    page: int
    page_size: int
    has_more: bool


class ConfirmCompletionRequest(BaseModel):
    otp_code: str | None = None


class RaiseDisputeRequest(BaseModel):
    reason: str
    description: str

    @field_validator("description")
    @classmethod
    def validate_description(cls, v: str) -> str:
        if len(v.strip()) < 20:
            raise ValueError("Please describe the issue in at least 20 characters")
        return v.strip()
