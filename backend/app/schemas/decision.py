"""
Pydantic schemas for the communication decisions API — Phase 6.
"""

from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, field_validator


class DecisionResponse(BaseModel):
    """Full decision representation returned by the API."""
    model_config = ConfigDict(from_attributes=True)

    pair_id:             str
    decision_id:         str
    decision_type:       str
    selected_request_id: Optional[int]
    reason_code:         str
    status:              str
    context_snapshot:    str
    created_at:          datetime
    updated_at:          datetime


class DecisionRespondRequest(BaseModel):
    """Payload for POST /api/reciprocal-pairs/{pair_id}/decision/respond."""
    action: str

    @field_validator("action")
    @classmethod
    def action_must_be_valid(cls, v: str) -> str:
        valid = {"ALLOW_A_TO_B", "ALLOW_B_TO_A", "BLOCK"}
        if v not in valid:
            raise ValueError(f"action must be one of {sorted(valid)}")
        return v
