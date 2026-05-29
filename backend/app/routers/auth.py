from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.database import get_db
from app.schemas.auth import (
    RegisterRequest,
    LoginRequest,
    VerifyPhoneRequest,
    ResendOTPRequest,
    RefreshTokenRequest,
    LogoutRequest,
    TokenResponse,
    MessageResponse,
    SuccessResponse,
)
from app.schemas.user import UserResponse
from app.services.auth_service import auth_service
from app.core.dependencies import CurrentUser

router = APIRouter(prefix="/auth", tags=["Authentication"])
limiter = Limiter(key_func=get_remote_address)


@router.post(
    "/register",
    response_model=UserResponse,
    status_code=201,
    summary="Register a new user",
    description=(
        "Creates a new client, agent, or business account. "
        "An OTP is automatically sent to the provided phone number. "
        "The account is not fully active until the phone is verified."
    ),
)
async def register(
    data: RegisterRequest,
    db: AsyncSession = Depends(get_db),
):
    user = await auth_service.register(db, data)
    return UserResponse.model_validate(user)


@router.post(
    "/verify-phone",
    response_model=TokenResponse,
    summary="Verify phone with OTP",
    description=(
        "Submits the 6-digit OTP sent to the user's phone. "
        "On success, returns access and refresh tokens — the user is now logged in."
    ),
)
async def verify_phone(
    data: VerifyPhoneRequest,
    db: AsyncSession = Depends(get_db),
):
    return await auth_service.verify_phone(db, data.phone, data.code)


@router.post(
    "/resend-otp",
    response_model=SuccessResponse,
    summary="Resend OTP",
)
async def resend_otp(
    data: ResendOTPRequest,
    db: AsyncSession = Depends(get_db),
):
    await auth_service.resend_otp(db, data.phone)
    return SuccessResponse(message="If that phone number exists, a new OTP has been sent.")


@router.post(
    "/login",
    response_model=TokenResponse,
    summary="Login with phone/email and password",
)
async def login(
    data: LoginRequest,
    db: AsyncSession = Depends(get_db),
):
    return await auth_service.login(db, data)


@router.post(
    "/refresh",
    response_model=TokenResponse,
    summary="Refresh access token",
    description="Provide a valid refresh token to receive a new access + refresh token pair.",
)
async def refresh_token(
    data: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db),
):
    return await auth_service.refresh(db, data.refresh_token)


@router.post(
    "/logout",
    response_model=SuccessResponse,
    summary="Logout — revoke refresh token",
)
async def logout(
    data: LogoutRequest,
    current_user: CurrentUser,
    db: AsyncSession = Depends(get_db),
):
    await auth_service.logout(db, data.refresh_token)
    return SuccessResponse(message="Logged out successfully.")
