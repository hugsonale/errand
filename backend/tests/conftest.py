import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

from app.main import app
from app.database import Base, get_db

# Use a separate in-memory SQLite DB for tests
TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"

test_engine = create_async_engine(TEST_DATABASE_URL, echo=False)
TestSessionLocal = async_sessionmaker(
    test_engine, class_=AsyncSession, expire_on_commit=False
)


@pytest_asyncio.fixture(autouse=True)
async def setup_db():
    """Create all tables before each test, drop after."""
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)


@pytest_asyncio.fixture
async def db():
    async with TestSessionLocal() as session:
        yield session


@pytest_asyncio.fixture
async def client(db):
    """HTTP test client with DB dependency overridden to use test DB."""
    async def override_get_db():
        yield db

    app.dependency_overrides[get_db] = override_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


# ── Helpers ────────────────────────────────────────────────────────────────────

async def register_and_verify_client(client: AsyncClient) -> dict:
    """Registers a client user and returns their tokens."""
    reg_resp = await client.post("/api/v1/auth/register", json={
        "full_name": "Test Client",
        "phone": "+2348011111111",
        "password": "Password123",
        "role": "client",
    })
    assert reg_resp.status_code == 201

    # Simulate OTP verification — in tests, OTP service prints to console
    # We need to fetch the OTP from the DB directly
    verify_resp = await client.post("/api/v1/auth/verify-phone", json={
        "phone": "+2348011111111",
        "code": "000000",  # Override in specific tests
    })
    return verify_resp.json()
