"""
ReciprocalPair SQLAlchemy model.

Represents a matched pair of reciprocal communication intents:
  Request A: caller=A, receiver=B
  Request B: caller=B, receiver=A
  |request_time_A - request_time_B| <= RECIPROCAL_WINDOW_SECONDS

Phase 5: detection only.
Phase 6: decision / conflict resolution (not implemented here).

Security notes:
- pair_id is server-generated (RP_XXXXXX) — never trusted from clients.
- detected_at is server-generated UTC.
- time_difference_ms is computed server-side from stored timestamps.
"""

import enum
from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Column,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class PairStatus(str, enum.Enum):
    """
    Lifecycle status of a reciprocal pair.

    Phase 5 active status: DETECTED
    Future statuses (Phase 6+) reserved but not yet implemented:
      RESOLVED, ALLOWED, BLOCKED
    """
    DETECTED = "DETECTED"
    # Phase 6+ reserved
    RESOLVED = "RESOLVED"
    ALLOWED  = "ALLOWED"
    BLOCKED  = "BLOCKED"


class ReciprocalPair(Base):
    __tablename__ = "reciprocal_pairs"

    __table_args__ = (
        # Each communication request can participate in at most ONE pair
        UniqueConstraint("request_a_id", name="uq_reciprocal_pairs_request_a"),
        UniqueConstraint("request_b_id", name="uq_reciprocal_pairs_request_b"),
    )

    id: int = Column(Integer, primary_key=True, index=True)

    # Human-readable unique pair identifier: RP_XXXXXX
    pair_id: str = Column(String(20), unique=True, nullable=False, index=True)

    # Both foreign keys point to the same table — explicit FK names required
    request_a_id: int = Column(
        Integer,
        ForeignKey("communication_requests.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    request_b_id: int = Column(
        Integer,
        ForeignKey("communication_requests.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # Server-generated timestamp of when the pair was detected
    detected_at: datetime = Column(DateTime(timezone=True), nullable=False)

    # |request_time_A - request_time_B| in milliseconds (server-computed)
    time_difference_ms: int = Column(BigInteger, nullable=False)

    status: PairStatus = Column(
        Enum(PairStatus),
        nullable=False,
        default=PairStatus.DETECTED,
        server_default=PairStatus.DETECTED.value,
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
    request_a = relationship(
        "CommunicationRequest",
        foreign_keys=[request_a_id],
    )
    request_b = relationship(
        "CommunicationRequest",
        foreign_keys=[request_b_id],
    )
