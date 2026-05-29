from app.routers.auth import router as auth_router
from app.routers.users import router as users_router
from app.routers.agents import router as agents_router
from app.routers.tasks import router as tasks_router
from app.routers.payments import router as payments_router
from app.routers.reviews import router as reviews_router
from app.routers.notifications import router as notifications_router

__all__ = [
    "auth_router", "users_router", "agents_router", "tasks_router",
    "payments_router", "reviews_router", "notifications_router",
]
