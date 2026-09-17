"""
Pydantic schemas for the reciprocal-pairs API.
"""

from datetime import datetime
from pydantic import BaseModel, ConfigDict
from app.schemas.call import UserSummary


class ReciprocalRequestSummary(BaseModel):
    """Minimal call-request info embedded in pair responses."""
    model_config = ConfigDict(from_attributes=True)

    request_id: str
    caller: UserSummary
    receiver: UserSummary


class ReciprocalPairResponse(BaseModel):
    """Full reciprocal pair representation."""
    model_config = ConfigDict(from_attributes=True)

    pair_id: str
    request_a: ReciprocalRequestSummary
    request_b: ReciprocalRequestSummary
    detected_at: datetime
    time_difference_ms: int
    status: str


class ReciprocalPairListResponse(BaseModel):
    pairs: list[ReciprocalPairResponse]
    total: int
