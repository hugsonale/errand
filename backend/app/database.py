from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from app.config import settings


# Async engine — used by the running app
engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    pool_pre_ping=True,       # reconnects dropped connections
    pool_size=10,
    max_overflow=20,
)

# Session factory
AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,   # prevents lazy-load errors after commit
    autocommit=False,
    autoflush=False,
)


class Base(DeclarativeBase):
    """
    All ORM models inherit from this base.
    Provides the metadata registry Alembic needs.
    """
    pass


async def get_db() -> AsyncSession:
    """
    FastAPI dependency — yields a DB session per request,
    commits on success, rolls back on any exception.
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()
