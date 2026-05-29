import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.auth import OTPCode
from app.models.user import User


@pytest.mark.asyncio
async def test_register_client_success(client: AsyncClient):
    response = await client.post("/api/v1/auth/register", json={
        "full_name": "Amaka Johnson",
        "phone": "+2348012345678",
        "password": "SecurePass1",
        "role": "client",
    })
    assert response.status_code == 201
    data = response.json()
    assert data["phone"] == "+2348012345678"
    assert data["role"] == "client"
    assert data["phone_verified"] is False
    assert "password_hash" not in data


@pytest.mark.asyncio
async def test_register_normalises_nigerian_phone(client: AsyncClient):
    """08012345678 should be stored as +2348012345678."""
    response = await client.post("/api/v1/auth/register", json={
        "full_name": "Chidi Okonkwo",
        "phone": "08012345679",
        "password": "SecurePass1",
        "role": "client",
    })
    assert response.status_code == 201
    assert response.json()["phone"] == "+2348012345679"


@pytest.mark.asyncio
async def test_register_duplicate_phone_rejected(client: AsyncClient):
    payload = {
        "full_name": "User One",
        "phone": "+2348099999999",
        "password": "SecurePass1",
        "role": "client",
    }
    await client.post("/api/v1/auth/register", json=payload)
    response = await client.post("/api/v1/auth/register", json=payload)
    assert response.status_code == 409
    assert "already exists" in response.json()["detail"]


@pytest.mark.asyncio
async def test_register_weak_password_rejected(client: AsyncClient):
    response = await client.post("/api/v1/auth/register", json={
        "full_name": "Test User",
        "phone": "+2348011112222",
        "password": "weak",
        "role": "client",
    })
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_register_agent_creates_profile(client: AsyncClient, db: AsyncSession):
    response = await client.post("/api/v1/auth/register", json={
        "full_name": "Emeka Agent",
        "phone": "+2348033333333",
        "password": "SecurePass1",
        "role": "agent",
    })
    assert response.status_code == 201
    user_id = response.json()["id"]

    from app.models.agent_profile import AgentProfile
    result = await db.execute(
        select(AgentProfile).where(AgentProfile.user_id == user_id)
    )
    profile = result.scalar_one_or_none()
    assert profile is not None
    assert profile.trust_level.value == "bronze"


@pytest.mark.asyncio
async def test_verify_phone_success(client: AsyncClient, db: AsyncSession):
    # Register
    await client.post("/api/v1/auth/register", json={
        "full_name": "Ngozi Verify",
        "phone": "+2348044444444",
        "password": "SecurePass1",
        "role": "client",
    })

    # Fetch the OTP from DB (since we're in test mode)
    result = await db.execute(
        select(OTPCode).where(OTPCode.phone == "+2348044444444", OTPCode.used == False)
    )
    otp = result.scalar_one()

    response = await client.post("/api/v1/auth/verify-phone", json={
        "phone": "+2348044444444",
        "code": otp.code,
    })
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"


@pytest.mark.asyncio
async def test_verify_phone_wrong_otp(client: AsyncClient, db: AsyncSession):
    await client.post("/api/v1/auth/register", json={
        "full_name": "Wrong OTP",
        "phone": "+2348055555555",
        "password": "SecurePass1",
        "role": "client",
    })
    response = await client.post("/api/v1/auth/verify-phone", json={
        "phone": "+2348055555555",
        "code": "000000",
    })
    assert response.status_code == 400
    assert "Incorrect OTP" in response.json()["detail"]


@pytest.mark.asyncio
async def test_login_before_verification_resends_otp(client: AsyncClient, db: AsyncSession):
    await client.post("/api/v1/auth/register", json={
        "full_name": "Unverified User",
        "phone": "+2348066666666",
        "password": "SecurePass1",
        "role": "client",
    })
    response = await client.post("/api/v1/auth/login", json={
        "identifier": "+2348066666666",
        "password": "SecurePass1",
    })
    assert response.status_code == 400
    assert "Phone not verified" in response.json()["detail"]


@pytest.mark.asyncio
async def test_login_wrong_password(client: AsyncClient, db: AsyncSession):
    await client.post("/api/v1/auth/register", json={
        "full_name": "Login Test",
        "phone": "+2348077777777",
        "password": "SecurePass1",
        "role": "client",
    })
    response = await client.post("/api/v1/auth/login", json={
        "identifier": "+2348077777777",
        "password": "WrongPassword1",
    })
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_token_refresh(client: AsyncClient, db: AsyncSession):
    # Full register + verify flow
    await client.post("/api/v1/auth/register", json={
        "full_name": "Refresh Test",
        "phone": "+2348088888888",
        "password": "SecurePass1",
        "role": "client",
    })
    otp_result = await db.execute(
        select(OTPCode).where(OTPCode.phone == "+2348088888888", OTPCode.used == False)
    )
    otp = otp_result.scalar_one()
    verify_resp = await client.post("/api/v1/auth/verify-phone", json={
        "phone": "+2348088888888",
        "code": otp.code,
    })
    refresh_token = verify_resp.json()["refresh_token"]

    # Refresh
    refresh_resp = await client.post("/api/v1/auth/refresh", json={
        "refresh_token": refresh_token,
    })
    assert refresh_resp.status_code == 200
    assert "access_token" in refresh_resp.json()

    # Old refresh token should be revoked (cannot be used again)
    second_refresh = await client.post("/api/v1/auth/refresh", json={
        "refresh_token": refresh_token,
    })
    assert second_refresh.status_code == 401


@pytest.mark.asyncio
async def test_get_me_requires_auth(client: AsyncClient):
    response = await client.get("/api/v1/users/me")
    assert response.status_code == 403  # No bearer token
