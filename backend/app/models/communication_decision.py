"""
CommunicationDecision SQLAlchemy model — Phase 6.

Represents the outcome of the Context-Aware Decision Engine for a
reciprocal call event.

Phase 6 is a CLOUD DECISION LAYER only.
This model stores the logical decision — it does NOT place, cancel,
answer, or suppress any actual SIM/cellular call.
That is Phase 7/8.

Decision precedence (documented, deterministic):
  1. BLOCK_RECIPROCAL preference (either user) → BLOCK
  2. ALWAYS_ALLOW preference (either user)     → ALLOW_A_TO_B (first request)
  3. PREFER_OUTGOING (user A)                  → ALLOW_A_TO_B
  4. PREFER_OUTGOING (user B)                  → ALLOW_B_TO_A
  5. PREFER_INCOMING (user A)                  → ALLOW_B_TO_A
  6. PREFER_INCOMING (user B)                  → ALLOW_A_TO_B
  7. Default (both ASK or unknown)             → ASK_USER

Security notes:
  - decision_id is server-generated (D_XXXXXX) — never trusted from clients.
  - context_snapshot is a server-generated JSON blob.
  - selected_request_id is nullable (null for ASK_USER / BLOCK).
"""

import enum
from datetime import datetime
from typing import Optional

from sqlalchemy import (
    Column,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class DecisionType(str, enum.Enum):
    """
    The logical outcome of the conflict resolution engine.

    ALLOW_A_TO_B  — permit the call A→B to proceed
    ALLOW_B_TO_A  — permit the call B→A to proceed
    ASK_USER      — present both options to the user; wait for explicit choice
    BLOCK         — block the reciprocal event entirely

    Phase 7 will translate ALLOW_* into an actual Telecom action.
    Phase 6 only produces the DecisionType.
    """
    ALLOW_A_TO_B = "ALLOW_A_TO_B"
    ALLOW_B_TO_A = "ALLOW_B_TO_A"
    ASK_USER     = "ASK_USER"
    BLOCK        = "BLOCK"


class ReasonCode(str, enum.Enum):
    """
    Explains why the engine produced a particular DecisionType.
    Every decision must carry exactly one ReasonCode.
    """
    DEFAULT_POLICY      = "DEFAULT_POLICY"       # neither user has a special preference
    USER_PREFERENCE     = "USER_PREFERENCE"       # derived from reciprocal_call_preference
    EXPLICIT_USER_CHOICE = "EXPLICIT_USER_CHOICE" # user responded via /respond endpoint
    DND_ACTIVE          = "DND_ACTIVE"            # future: DND integration
    VIP_PRIORITY        = "VIP_PRIORITY"          # future: VIP contacts
    USER_UNAVAILABLE    = "USER_UNAVAILABLE"      # future: presence/availability
    NETWORK_CONDITION   = "NETWORK_CONDITION"     # future: network context


class DecisionStatus(str, enum.Enum):
    """
    Lifecycle status of a decision.

    PENDING   — evaluation requested but not yet complete (reserved; not used in Phase 6)
    RESOLVED  — the engine has produced a decision
    EXPIRED   — the decision is no longer valid (future: TTL)
    """
    PENDING  = "PENDING"
    RESOLVED = "RESOLVED"
    EXPIRED  = "EXPIRED"


class CommunicationDecision(Base):
    __tablename__ = "communication_decisions"

    __table_args__ = (
        # One and only one decision per reciprocal pair (idempotency enforced by DB)
        UniqueConstraint("pair_id", name="uq_communication_decisions_pair_id"),
    )

    id: int = Column(Integer, primary_key=True, index=True)

    # Server-generated unique decision identifier: D_XXXXXX
    decision_id: str = Column(String(20), unique=True, nullable=False, index=True)

    # The reciprocal pair this decision belongs to
    pair_id: str = Column(
        String(20),
        ForeignKey("reciprocal_pairs.pair_id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    decision_type: DecisionType = Column(
        Enum(DecisionType),
        nullable=False,
    )

    # For ALLOW_A_TO_B / ALLOW_B_TO_A: the communication_request.id that should proceed.
    # Null for ASK_USER and BLOCK.
    selected_request_id: Optional[int] = Column(
        Integer,
        ForeignKey("communication_requests.id", ondelete="SET NULL"),
        nullable=True,
    )

    reason_code: ReasonCode = Column(
        Enum(ReasonCode),
        nullable=False,
    )

    # Server-generated JSON snapshot of the context used to make this decision.
    # Stored as Text/JSON; used for audit and explainability.
    context_snapshot: str = Column(Text, nullable=False, default="{}")

    status: DecisionStatus = Column(
        Enum(DecisionStatus),
        nullable=False,
        default=DecisionStatus.RESOLVED,
        server_default=DecisionStatus.RESOLVED.value,
    )

    created_at: datetime = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    updated_at: datetime = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # ── Relationships ─────────────────────────────────────────────────────
    pair = relationship("ReciprocalPair", foreign_keys=[pair_id])
    selected_request = relationship("CommunicationRequest", foreign_keys=[selected_request_id])
