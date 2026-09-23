"""
Pydantic schemas for user-facing responses.

password_hash is intentionally excluded from every outbound schema.
"""

from datetime import datetime
from pydantic import BaseModel, EmailStr, ConfigDict


class UserResponse(BaseModel):
    """Public user representation — never includes password_hash."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    email: EmailStr
    phone: str
    status: str
    reciprocal_call_preference: str = "ASK"
    dnd_enabled: bool = False
    vip_contacts: str = ""
    created_at: datetime
    updated_at: datetime


class UserPreferenceUpdate(BaseModel):
    """Schema for updating reciprocal call preferences and context rules."""
    reciprocal_call_preference: str | None = None
    dnd_enabled: bool | None = None
    vip_contacts: str | None = None


class UserListResponse(BaseModel):
    """Wrapper for paginated or full user lists."""

    users: list[UserResponse]
    total: int
