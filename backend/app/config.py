"""
Application configuration loaded from environment variables.
Never hardcode secrets — all sensitive values come from .env.
"""

from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    # Database
    DATABASE_URL: str

    # JWT
    JWT_SECRET_KEY: str
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60

    # Call request TTL — how long a PENDING request stays valid
    REQUEST_TTL_SECONDS: int = 30

    # Reciprocal detection window — two requests within this window form a pair
    RECIPROCAL_WINDOW_SECONDS: int = 10

    # App
    APP_ENV: str = "development"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


@lru_cache()
def get_settings() -> Settings:
    """Return a cached Settings instance. Call once per process."""
    return Settings()
