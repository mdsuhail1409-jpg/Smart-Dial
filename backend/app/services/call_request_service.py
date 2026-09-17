"""
Call request business logic.

Centralises:
- Request creation with server-side timestamps and TTL
- Expiration checking (lazy: applied when a request is fetched/processed)
- Cancellation rules

Keeping logic here (not in the router) means Day 3 can reuse these
functions without touching the HTTP layer.
"""

from datetime import datetime, timezone, timedelta

from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from app.config import get_settings
from app.models.communication_request import CommunicationRequest, RequestStatus
from app.models.user import User
from app.utils.ids import generate_request_id

settings = get_settings()

# Maximum retry attempts on the (extremely rare) request_id collision
_MAX_ID_RETRIES = 5


def _now_utc() -> datetime:
    """Return the current UTC time as a timezone-aware datetime."""
    return datetime.now(timezone.utc)


def _as_aware(dt: datetime) -> datetime:
    """
    Ensure a datetime is timezone-aware.
    SQLite returns naive datetimes; PostgreSQL returns aware ones.
    We treat naive datetimes as UTC.
    """
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


# ── Expiration ────────────────────────────────────────────────────────────────

def expire_if_needed(request: CommunicationRequest, db: Session) -> CommunicationRequest:
    """
    Lazily expire a request if it is PENDING and past its expires_at.

    Called whenever a request is fetched or processed — no background worker
    needed for Day 2. Day 3 can move this to a scheduled task if desired.

    Returns the (possibly updated) request object.
    """
    if (
        request.status == RequestStatus.PENDING
        and _now_utc() >= _as_aware(request.expires_at)
    ):
        request.status = RequestStatus.EXPIRED
        db.commit()
        db.refresh(request)
    return request


# ── Creation ──────────────────────────────────────────────────────────────────

def create_call_request(
    caller: User,
    receiver_id: int,
    db: Session,
) -> CommunicationRequest:
    """
    Create and persist a new PENDING communication request.

    Security guarantees:
    - caller is always the authenticated JWT user, never client-supplied.
    - All timestamps are server-generated.
    - request_id is generated server-side using cryptographic randomness.

    Raises:
        ValueError: if receiver does not exist, or caller == receiver.
    """
    # Validate receiver exists
    receiver = db.query(User).filter(User.id == receiver_id).first()
    if receiver is None:
        raise ValueError(f"Receiver with id {receiver_id} does not exist")

    # Prevent self-call
    if caller.id == receiver_id:
        raise ValueError("You cannot call yourself")

    # Server-side timestamps — never trust client
    now = _now_utc()
    expires = now + timedelta(seconds=settings.REQUEST_TTL_SECONDS)

    # Generate a unique request_id — retry on the rare collision
    for attempt in range(_MAX_ID_RETRIES):
        rid = generate_request_id()
        existing = db.query(CommunicationRequest).filter(
            CommunicationRequest.request_id == rid
        ).first()
        if existing is None:
            break
    else:
        # All retries collided — extremely unlikely
        raise RuntimeError("Failed to generate a unique request ID")

    call_req = CommunicationRequest(
        request_id=rid,
        caller_id=caller.id,
        receiver_id=receiver_id,
        request_time=now,
        status=RequestStatus.PENDING,
        reciprocal_flag=False,   # Day 3 will set this
        pair_id=None,            # Day 3 will set this
        expires_at=expires,
    )
    db.add(call_req)

    try:
        db.commit()
        db.refresh(call_req)
    except IntegrityError:
        db.rollback()
        raise RuntimeError("Failed to persist call request due to a database error")

    # Eagerly load relationships so response serialisation works
    db.refresh(call_req)
    return call_req


# ── Lookup ────────────────────────────────────────────────────────────────────

def get_request_by_rid(
    request_id: str,
    current_user: User,
    db: Session,
) -> CommunicationRequest:
    """
    Fetch a request by its string request_id.

    Authorization: only the caller or receiver may view it.

    Raises:
        LookupError: if the request does not exist.
        PermissionError: if current_user is neither caller nor receiver.
    """
    req = db.query(CommunicationRequest).filter(
        CommunicationRequest.request_id == request_id
    ).first()

    if req is None:
        raise LookupError(f"Call request {request_id!r} not found")

    if current_user.id not in (req.caller_id, req.receiver_id):
        raise PermissionError("You are not authorised to view this request")

    # Lazily expire before returning
    req = expire_if_needed(req, db)
    return req


# ── My requests ───────────────────────────────────────────────────────────────

def get_my_requests(
    current_user: User,
    db: Session,
    status_filter: str | None = None,
) -> list[CommunicationRequest]:
    """
    Return all requests where current_user is caller OR receiver.

    Optional status_filter: e.g. "PENDING" (case-insensitive).
    Lazily expires PENDING requests before returning.
    """
    query = db.query(CommunicationRequest).filter(
        (CommunicationRequest.caller_id == current_user.id)
        | (CommunicationRequest.receiver_id == current_user.id)
    )

    if status_filter:
        try:
            status_enum = RequestStatus(status_filter.upper())
            query = query.filter(CommunicationRequest.status == status_enum)
        except ValueError:
            pass  # Unknown status filter → return unfiltered

    requests = query.order_by(CommunicationRequest.created_at.desc()).all()

    # Lazy expiration pass — update any PENDING-but-expired requests
    for req in requests:
        expire_if_needed(req, db)

    # Re-fetch after potential expiration updates
    return query.all()


# ── Cancellation ──────────────────────────────────────────────────────────────

def cancel_request(
    request_id: str,
    current_user: User,
    db: Session,
) -> CommunicationRequest:
    """
    Cancel a PENDING call request.

    Rules:
    - Only the original caller may cancel.
    - Only PENDING requests can be cancelled.

    Raises:
        LookupError: request not found.
        PermissionError: current_user is not the caller.
        ValueError: request is not in a cancellable state.
    """
    req = db.query(CommunicationRequest).filter(
        CommunicationRequest.request_id == request_id
    ).first()

    if req is None:
        raise LookupError(f"Call request {request_id!r} not found")

    if req.caller_id != current_user.id:
        raise PermissionError("Only the caller can cancel this request")

    # Lazily expire before checking cancellability
    req = expire_if_needed(req, db)

    if req.status != RequestStatus.PENDING:
        raise ValueError(
            f"Cannot cancel a request with status '{req.status.value}'"
        )

    req.status = RequestStatus.CANCELLED
    db.commit()
    db.refresh(req)
    return req
