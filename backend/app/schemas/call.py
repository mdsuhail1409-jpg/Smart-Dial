"""
Pydantic schemas for the communication requests (calls) API.

Security note: caller_id is NEVER accepted from the client.
The caller is always resolved from the authenticated JWT.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, field_validator


# ── Nested summary used inside call request responses ────────────────────────

class UserSummary(BaseModel):
    """Minimal user info embedded in call request responses."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str


# ── Inbound ───────────────────────────────────────────────────────────────────

class CreateCallRequest(BaseModel):
    """
    Flutter sends ONLY the receiver_id.
    The backend derives caller_id from the JWT — never trusting client input.
    """

    receiver_id: int

    @field_validator("receiver_id")
    @classmethod
    def receiver_must_be_positive(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("receiver_id must be a positive integer")
        return v


# ── Outbound ──────────────────────────────────────────────────────────────────

class CallRequestResponse(BaseModel):
    """Full call request representation returned by the API."""

    model_config = ConfigDict(from_attributes=True)

    request_id: str
    caller: UserSummary
    receiver: UserSummary
    status: str
    reciprocal_flag: bool
    pair_id: Optional[str]
    request_time: datetime
    expires_at: datetime


class CallRequestListResponse(BaseModel):
    """Wrapper for a list of call requests."""

    requests: list[CallRequestResponse]
    total: int
