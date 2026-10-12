"""
Pydantic schemas for authentication endpoints.
"""

from pydantic import BaseModel, EmailStr, field_validator
from app.schemas.user import UserResponse


class RegisterRequest(BaseModel):
    name: str
    email: EmailStr
    phone: str
    password: str

    @field_validator("name")
    @classmethod
    def name_must_not_be_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("name must not be empty")
        return v

    @field_validator("phone")
    @classmethod
    def phone_basic_validation(cls, v: str) -> str:
        from app.utils.phone_normalizer import normalize_to_e164
        try:
            return normalize_to_e164(v)
        except ValueError as exc:
            raise ValueError(f"Invalid phone number: {exc}")

    @field_validator("password")
    @classmethod
    def password_min_length(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("password must be at least 8 characters")
        return v


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


class OtpSendRequest(BaseModel):
    phone: str

    @field_validator("phone")
    @classmethod
    def validate_and_normalize_phone(cls, v: str) -> str:
        from app.utils.phone_normalizer import normalize_to_e164
        try:
            return normalize_to_e164(v)
        except ValueError as exc:
            raise ValueError(f"Invalid phone number: {exc}")


class OtpSendResponse(BaseModel):
    status: str
    phone: str
    expires_in_seconds: int
    dev_code: str
    message: str


class OtpVerifyRequest(BaseModel):
    phone: str
    code: str

    @field_validator("phone")
    @classmethod
    def validate_and_normalize_phone(cls, v: str) -> str:
        from app.utils.phone_normalizer import normalize_to_e164
        try:
            return normalize_to_e164(v)
        except ValueError as exc:
            raise ValueError(f"Invalid phone number: {exc}")

    @field_validator("code")
    @classmethod
    def validate_code(cls, v: str) -> str:
        v = v.strip()
        if len(v) != 6 or not v.isdigit():
            raise ValueError("Verification code must be 6 digits")
        return v


class OtpVerifyResponse(BaseModel):
    verified: bool
    phone: str
    message: str

