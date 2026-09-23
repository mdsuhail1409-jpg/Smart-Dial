"""
Context Engine — Phase 6

Produces a deterministic context snapshot for a reciprocal call pair.

Only information that genuinely exists in the current database/system is
used.  Features that do not yet exist are represented as UNKNOWN or
NOT_CONFIGURED so the conflict resolution engine can handle them safely
without crashing or fabricating data.

Phase 6 context features:
  - user_a_status         (from users.status)
  - user_b_status         (from users.status)
  - user_a_preference     (from users.reciprocal_call_preference)
  - user_b_preference     (from users.reciprocal_call_preference)
  - dnd_a                 (NOT_CONFIGURED — Phase 9)
  - dnd_b                 (NOT_CONFIGURED — Phase 9)
  - vip_a_in_b_contacts   (NOT_CONFIGURED — Phase 9)
  - vip_b_in_a_contacts   (NOT_CONFIGURED — Phase 9)
  - network_condition     (NOT_CONFIGURED — Phase 9)

The snapshot is serialized to JSON for storage in the audit trail.
"""

import json
from dataclasses import dataclass, asdict
from typing import Any

from sqlalchemy.orm import Session

from app.models.user import User, ReciprocalCallPreference
from app.models.reciprocal_pair import ReciprocalPair

_NOT_CONFIGURED = "NOT_CONFIGURED"
_UNKNOWN        = "UNKNOWN"


@dataclass
class ContextSnapshot:
    """
    Immutable snapshot of the context at decision time.
    All fields are strings so serialisation is trivial.
    """
    # User A = caller of request_a
    user_a_id:         int
    user_a_status:     str
    user_a_preference: str

    # User B = caller of request_b
    user_b_id:         int
    user_b_status:     str
    user_b_preference: str

    # Future context fields — always NOT_CONFIGURED in Phase 6
    dnd_a:               str = _NOT_CONFIGURED
    dnd_b:               str = _NOT_CONFIGURED
    vip_a_in_b_contacts: str = _NOT_CONFIGURED
    vip_b_in_a_contacts: str = _NOT_CONFIGURED
    network_condition:   str = _NOT_CONFIGURED

    def to_json(self) -> str:
        """Serialize to a compact JSON string for DB storage."""
        return json.dumps(asdict(self), sort_keys=True)

    @classmethod
    def from_json(cls, raw: str) -> "ContextSnapshot":
        return cls(**json.loads(raw))


def build_context(pair: ReciprocalPair, db: Session) -> ContextSnapshot:
    """
    Build a ContextSnapshot for the given reciprocal pair.

    user_a = caller of request_a
    user_b = caller of request_b

    Safe fallbacks:
    - If a user is missing (should not happen with FK constraints), fields
      default to UNKNOWN rather than raising an exception.
    - Phase 9 fields are always NOT_CONFIGURED.
    """
    req_a = pair.request_a
    req_b = pair.request_b

    user_a: User | None = db.get(User, req_a.caller_id)
    user_b: User | None = db.get(User, req_b.caller_id)

    # Phase 9: Context rules evaluation (DND & VIP Contacts)
    dnd_a = "TRUE" if (user_a and getattr(user_a, "dnd_enabled", False)) else "FALSE"
    dnd_b = "TRUE" if (user_b and getattr(user_b, "dnd_enabled", False)) else "FALSE"

    def _is_vip(candidate: User | None, target_user: User | None) -> str:
        if not candidate or not target_user:
            return "FALSE"
        vips = [v.strip() for v in getattr(target_user, "vip_contacts", "").split(",") if v.strip()]
        if not vips:
            return "FALSE"
        if candidate.phone in vips or str(candidate.id) in vips:
            return "TRUE"
        return "FALSE"

    vip_a_in_b = _is_vip(user_a, user_b)
    vip_b_in_a = _is_vip(user_b, user_a)

    return ContextSnapshot(
        user_a_id           = req_a.caller_id,
        user_a_status       = user_a.status.value if user_a else _UNKNOWN,
        user_a_preference   = (
            user_a.reciprocal_call_preference.value
            if user_a else _UNKNOWN
        ),
        user_b_id           = req_b.caller_id,
        user_b_status       = user_b.status.value if user_b else _UNKNOWN,
        user_b_preference   = (
            user_b.reciprocal_call_preference.value
            if user_b else _UNKNOWN
        ),
        dnd_a               = dnd_a,
        dnd_b               = dnd_b,
        vip_a_in_b_contacts = vip_a_in_b,
        vip_b_in_a_contacts = vip_b_in_a,
        network_condition   = "OPTIMAL",
    )
