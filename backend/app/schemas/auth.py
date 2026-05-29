import re
from pydantic import BaseModel, field_validator, model_validator
from app.models.user import UserRole


# ─── Register ────────────────────────────────────────────────────────────────

class RegisterRequest(BaseModel):
    full_name: str
    phone: str
    email: str | None = None
    password: str
    role: UserRole = UserRole.CLIENT

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        # Normalise Nigerian numbers: 08012345678 → +2348012345678
        v = v.strip().replace(" ", "")
        if v.startswith("0") and len(v) == 11:
            v = "+234" + v[1:]
        if not re.match(r"^\+?[1-9]\d{7,14}$", v):
            raise ValueError("Invalid phone number format")
        return v

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters")
        if not any(c.isupper() for c in v):
            raise ValueError("Password must contain at least one uppercase letter")
        if not any(c.isdigit() for c in v):
            raise ValueError("Password must contain at least one number")
        return v

    @field_validator("full_name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 2:
            raise ValueError("Full name must be at least 2 characters")
        if len(v) > 100:
            raise ValueError("Full name must be under 100 characters")
        return v


# ─── Login ───────────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    """Accepts either phone or email + password."""
    identifier: str  # phone or email
    password: str


# ─── OTP ─────────────────────────────────────────────────────────────────────

class VerifyPhoneRequest(BaseModel):
    phone: str
    code: str

    @field_validator("code")
    @classmethod
    def validate_code(cls, v: str) -> str:
        v = v.strip()
        if not v.isdigit() or len(v) != 6:
            raise ValueError("OTP must be a 6-digit number")
        return v


class ResendOTPRequest(BaseModel):
    phone: str


# ─── Token responses ─────────────────────────────────────────────────────────

class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int  # seconds


class RefreshTokenRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str


# ─── Generic responses ───────────────────────────────────────────────────────

class MessageResponse(BaseModel):
    message: str


class SuccessResponse(BaseModel):
    success: bool = True
    message: str
