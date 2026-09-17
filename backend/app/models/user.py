"""
User SQLAlchemy model.

Security notes:
- password_hash stores only the bcrypt hash, never the plaintext password.
- status defaults to ACTIVE; future states (SUSPENDED, DELETED) can be added.
"""

import enum
from datetime import datetime, timezone

from sqlalchemy import Column, Integer, String, Enum, DateTime
from sqlalchemy.sql import func

from app.database import Base


class UserStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    SUSPENDED = "SUSPENDED"


class ReciprocalCallPreference(str, enum.Enum):
    """
    User's preference for handling reciprocal call events.

    ASK              — default; show the user a prompt to choose (Phase 6 default)
    PREFER_OUTGOING  — favour the call this user placed (A→B when A has this pref)
    PREFER_INCOMING  — favour the call the other user placed (B→A when A has this pref)
    ALWAYS_ALLOW     — allow the event without asking
    BLOCK_RECIPROCAL — block reciprocal events silently
    """
    ASK              = "ASK"
    PREFER_OUTGOING  = "PREFER_OUTGOING"
    PREFER_INCOMING  = "PREFER_INCOMING"
    ALWAYS_ALLOW     = "ALWAYS_ALLOW"
    BLOCK_RECIPROCAL = "BLOCK_RECIPROCAL"


class User(Base):
    __tablename__ = "users"

    id: int = Column(Integer, primary_key=True, index=True)
    name: str = Column(String(100), nullable=False)
    email: str = Column(String(255), unique=True, nullable=False, index=True)
    phone: str = Column(String(20), unique=True, nullable=False, index=True)

    # Never store plaintext passwords — only the hash lives here
    password_hash: str = Column(String(255), nullable=False)

    status: UserStatus = Column(
        Enum(UserStatus),
        default=UserStatus.ACTIVE,
        nullable=False,
        server_default=UserStatus.ACTIVE.value,
    )

    # Phase 6: user preference for handling reciprocal call events
    reciprocal_call_preference: ReciprocalCallPreference = Column(
        Enum(ReciprocalCallPreference),
        nullable=False,
        default=ReciprocalCallPreference.ASK,
        server_default=ReciprocalCallPreference.ASK.value,
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
