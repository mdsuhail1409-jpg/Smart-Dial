"""
CommunicationRequest SQLAlchemy model.

Represents a one-directional call intent from caller → receiver.

Day 2 notes:
- pair_id and reciprocal_flag are defined here but remain NULL/False for Day 2.
- The enum includes future status values (MATCHED, ALLOWED, BLOCKED, COMPLETED)
  so the DB type is ready; business logic for those states comes in later days.
- Timestamps are always server-generated — client-supplied times are never trusted.
"""

import enum
from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    String,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class RequestStatus(str, enum.Enum):
    """
    Lifecycle states for a communication request.

    Day 2 active states: PENDING, CANCELLED, EXPIRED
    Future states (schema-ready, logic not yet implemented):
      MATCHED, ALLOWED, BLOCKED, COMPLETED
    """

    PENDING = "PENDING"
    CANCELLED = "CANCELLED"
    EXPIRED = "EXPIRED"
    # Reserved for Day 3+ — do not add business logic today
    MATCHED = "MATCHED"
    ALLOWED = "ALLOWED"
    BLOCKED = "BLOCKED"
    COMPLETED = "COMPLETED"


class CommunicationRequest(Base):
    __tablename__ = "communication_requests"

    id: int = Column(Integer, primary_key=True, index=True)

    # Human-readable unique request identifier, e.g. CR_98AB71
    request_id: str = Column(
        String(20), unique=True, nullable=False, index=True
    )

    # Caller — identity always derived from JWT, never from client payload
    caller_id: int = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    # Receiver
    receiver_id: int = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    # Server-generated timestamp of when the request was created
    request_time: datetime = Column(
        DateTime(timezone=True), nullable=False
    )

    status: RequestStatus = Column(
        Enum(RequestStatus),
        nullable=False,
        default=RequestStatus.PENDING,
        server_default=RequestStatus.PENDING.value,
    )

    # Day 3+ — always False for Day 2 requests
    reciprocal_flag: bool = Column(Boolean, nullable=False, default=False)

    # Day 3+ — always NULL for Day 2 requests
    pair_id: str | None = Column(String(50), nullable=True)

    # Server-generated: request_time + REQUEST_TTL_SECONDS
    expires_at: datetime = Column(DateTime(timezone=True), nullable=False)

    created_at: datetime = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # ── Relationships (lazy for now — used for response building) ─────────
    caller = relationship("User", foreign_keys=[caller_id])
    receiver = relationship("User", foreign_keys=[receiver_id])
