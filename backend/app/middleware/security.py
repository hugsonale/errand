import time
import re
import json
import uuid
import hashlib
from typing import Callable
from fastapi import Request, Response
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
import redis.asyncio as aioredis

from app.config import settings


# ─── Rate Limit Middleware ────────────────────────────────────────────────────

class RateLimitMiddleware(BaseHTTPMiddleware):
    """
    Sliding-window rate limiter backed by Redis.
    Different limits for auth endpoints vs general API.
    """

    # (requests, window_seconds)
    AUTH_LIMIT = (10, 60)       # 10 requests per minute for auth
    OTP_LIMIT = (3, 300)        # 3 OTP requests per 5 minutes
    GENERAL_LIMIT = (120, 60)   # 120 requests per minute general

    def __init__(self, app, redis_url: str):
        super().__init__(app)
        self._redis_url = redis_url
        self._redis: aioredis.Redis | None = None

    async def _get_redis(self) -> aioredis.Redis | None:
        if self._redis is None:
            try:
                self._redis = await aioredis.from_url(
                    self._redis_url, decode_responses=True
                )
            except Exception:
                return None
        return self._redis

    def _get_limit(self, path: str) -> tuple[int, int]:
        if "/auth/resend-otp" in path or "/auth/verify-phone" in path:
            return self.OTP_LIMIT
        if "/auth/" in path:
            return self.AUTH_LIMIT
        return self.GENERAL_LIMIT

    def _get_client_id(self, request: Request) -> str:
        """Use IP address as rate limit key."""
        forwarded = request.headers.get("X-Forwarded-For")
        if forwarded:
            ip = forwarded.split(",")[0].strip()
        else:
            ip = request.client.host if request.client else "unknown"
        return hashlib.md5(ip.encode()).hexdigest()[:16]

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        # Skip rate limiting for health checks and webhooks
        path = request.url.path
        if path in ("/health", "/", "/api/v1/payments/webhook"):
            return await call_next(request)

        redis = await self._get_redis()
        if not redis:
            # Redis unavailable — allow request (fail open)
            return await call_next(request)

        max_requests, window = self._get_limit(path)
        client_id = self._get_client_id(request)
        key = f"rl:{client_id}:{path.replace('/', '_')[:30]}"

        try:
            pipe = redis.pipeline()
            now = time.time()
            window_start = now - window

            await pipe.zremrangebyscore(key, 0, window_start)
            await pipe.zadd(key, {str(uuid.uuid4()): now})
            await pipe.zcard(key)
            await pipe.expire(key, window)
            results = await pipe.execute()
            request_count = results[2]

            if request_count > max_requests:
                return JSONResponse(
                    status_code=429,
                    content={
                        "detail": "Too many requests. Please slow down.",
                        "retry_after": window,
                    },
                    headers={"Retry-After": str(window)},
                )
        except Exception:
            pass  # Redis error — allow request

        response = await call_next(request)

        # Add rate limit headers
        try:
            response.headers["X-RateLimit-Limit"] = str(max_requests)
            response.headers["X-RateLimit-Window"] = str(window)
        except Exception:
            pass

        return response


# ─── Security Headers Middleware ──────────────────────────────────────────────

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Adds security headers to every response."""

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = "geolocation=(self)"
        if settings.APP_ENV == "production":
            response.headers["Strict-Transport-Security"] = (
                "max-age=31536000; includeSubDomains"
            )
        return response


# ─── Audit Log Middleware ─────────────────────────────────────────────────────

class AuditLogMiddleware(BaseHTTPMiddleware):
    """
    Logs sensitive operations to the audit trail.
    Only logs write operations to sensitive endpoints.
    """

    SENSITIVE_PATHS = {
        "/auth/login",
        "/auth/register",
        "/agents/verify",
        "/admin/",
        "/payments/",
    }

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        start_time = time.time()
        response = await call_next(request)
        duration_ms = int((time.time() - start_time) * 1000)

        # Only log writes to sensitive paths
        method = request.method
        path = request.url.path
        is_sensitive = any(s in path for s in self.SENSITIVE_PATHS)

        if is_sensitive and method in ("POST", "PUT", "PATCH", "DELETE"):
            forwarded = request.headers.get("X-Forwarded-For", "")
            ip = forwarded.split(",")[0].strip() if forwarded else (
                request.client.host if request.client else "unknown"
            )
            print(
                f"[AUDIT] {method} {path} | "
                f"status={response.status_code} | "
                f"ip={ip} | "
                f"duration={duration_ms}ms"
            )

        return response


# ─── Input Sanitization Helpers ───────────────────────────────────────────────

# Characters that could be used for SQL injection or XSS
_DANGEROUS_PATTERN = re.compile(r"[<>\"'%;()&+\-]{3,}")
_SQL_KEYWORDS = re.compile(
    r"\b(SELECT|INSERT|UPDATE|DELETE|DROP|UNION|EXEC|SCRIPT)\b",
    re.IGNORECASE,
)


def sanitize_string(value: str, max_length: int = 1000) -> str:
    """
    Basic input sanitization. SQLAlchemy parameterized queries already
    prevent SQL injection — this is defense in depth.
    """
    if not isinstance(value, str):
        return value

    # Truncate
    value = value[:max_length]

    # Strip null bytes
    value = value.replace("\x00", "")

    # Normalize whitespace
    value = " ".join(value.split())

    return value.strip()


def mask_phone(phone: str) -> str:
    """
    Returns masked phone for logs — never log raw phone numbers.
    +2348012345678 → +234801***678
    """
    if len(phone) < 8:
        return "***"
    return phone[:7] + "***" + phone[-3:]


def mask_sensitive_data(data: dict) -> dict:
    """Masks sensitive fields before logging."""
    masked = data.copy()
    for key in ("password", "password_hash", "nin_number", "bvn_number",
                "otp_code", "token", "access_token", "refresh_token"):
        if key in masked:
            masked[key] = "***"
    if "phone" in masked:
        masked["phone"] = mask_phone(str(masked["phone"]))
    return masked
