from pydantic_settings import BaseSettings
from pydantic import AnyHttpUrl, validator
from typing import List, Optional
import secrets


class Settings(BaseSettings):
    # App
    APP_NAME: str = "Errand Marketplace API"
    APP_ENV: str = "development"
    DEBUG: bool = True
    API_V1_PREFIX: str = "/api/v1"

    # Security
    SECRET_KEY: str = secrets.token_urlsafe(32)
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # Database
    DATABASE_URL: str
    DATABASE_URL_SYNC: str

    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"

    # AWS S3
    AWS_ACCESS_KEY_ID: str = ""
    AWS_SECRET_ACCESS_KEY: str = ""
    AWS_REGION: str = "eu-west-1"
    S3_BUCKET_NAME: str = "errand-marketplace-media"
    S3_PRESIGNED_URL_EXPIRE: int = 3600

    # OTP / SMS
    TERMII_API_KEY: str = ""
    TERMII_SENDER_ID: str = "ErrandApp"
    OTP_EXPIRE_MINUTES: int = 10
    OTP_LENGTH: int = 6

    # Paystack (Phase 3)
    PAYSTACK_SECRET_KEY: str = ""
    PAYSTACK_PUBLIC_KEY: str = ""
    PAYSTACK_WEBHOOK_SECRET: str = ""

    # Firebase (Phase 3)
    FIREBASE_CREDENTIALS_PATH: str = ""

    # CORS
    ALLOWED_ORIGINS: str = "http://localhost:3000,http://localhost:8080"

    @property
    def allowed_origins_list(self) -> List[str]:
        return [origin.strip() for origin in self.ALLOWED_ORIGINS.split(",")]

    # Admin seed
    FIRST_ADMIN_EMAIL: str = "admin@errandmarketplace.com"
    FIRST_ADMIN_PASSWORD: str = "ChangeThisPassword123!"

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
