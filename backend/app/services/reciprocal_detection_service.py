"""
Reciprocal Detection Service — Phase 5

Detects when two communication requests form a reciprocal pair:

    Request A:  caller=A, receiver=B
    Request B:  caller=B, receiver=A
    |request_time_A - request_time_B| <= RECIPROCAL_WINDOW_SECONDS

When detected:
  - Creates ONE ReciprocalPair row with a unique pair_id (RP_XXXXXX)
  - Sets reciprocal_flag=True and pair_id on BOTH communication_requests
  - Commits atomically inside the provided session

Transaction safety:
  PostgreSQL row-level locking (SELECT FOR UPDATE) is used to prevent a
  race condition where two simultaneous requests each detect the other and
  both try to create a pair.  Only the first writer wins; the second hits
  the unique constraint on (request_a_id) / (request_b_id) and raises
  IntegrityError, which is caught and treated as "already paired".

Phase 5 scope:
  Detection + pair creation only.
  No conflict resolution, no SIM-call decision — that is Phase 6.
"""

from datetime import datetime, timezone, timedelta
from typing import Optional

from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from sqlalchemy import select, func

from app.config import get_settings
from app.models.communication_request import CommunicationRequest, RequestStatus
from app.models.reciprocal_pair import ReciprocalPair, PairStatus
from app.utils.ids import generate_pair_id

settings = get_settings()
_MAX_PAIR_ID_RETRIES = 5


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _as_aware(dt: datetime) -> datetime:
    """Ensure a datetime is timezone-aware (SQLite compat)."""
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


def _is_eligible(req: CommunicationRequest) -> bool:
    """
    A request is eligible for reciprocal matching only if it is PENDING.
    CANCELLED, EXPIRED, or already paired requests are excluded.
    """
    if req.status != RequestStatus.PENDING:
        return False
    if req.reciprocal_flag:
        return False
    if req.pair_id is not None:
        return False
    return True


def _within_window(time_a: datetime, time_b: datetime) -> bool:
    """
    Returns True if |time_a - time_b| <= RECIPROCAL_WINDOW_SECONDS.
    Boundary (exactly equal to the window) counts as a match.
    """
    window = timedelta(seconds=settings.RECIPROCAL_WINDOW_SECONDS)
    diff = abs(_as_aware(time_a) - _as_aware(time_b))
    return diff <= window


def _time_diff_ms(time_a: datetime, time_b: datetime) -> int:
    """Return absolute difference in milliseconds."""
    diff = abs(_as_aware(time_a) - _as_aware(time_b))
    return int(diff.total_seconds() * 1000)


# ── Public API ────────────────────────────────────────────────────────────────

class ReciprocalDetectionResult:
    """Returned by detect_reciprocal to inform the caller of the outcome."""

    def __init__(
        self,
        matched: bool,
        pair: Optional[ReciprocalPair] = None,
    ):
        self.matched = matched
        self.pair    = pair


def detect_reciprocal(
    request: CommunicationRequest,
    db: Session,
) -> ReciprocalDetectionResult:
    """
    Attempt to find and record a reciprocal match for the given request.

    Algorithm:
    1. Check the current request is eligible.
    2. Lock the current request row with SELECT FOR UPDATE (skip on SQLite).
    3. Search for a PENDING reverse request: caller=receiver, receiver=caller.
    4. For each candidate (ordered by request_time asc for determinism):
       a. Verify within the time window.
       b. Lock the candidate row.
       c. Double-check it is still eligible after locking (avoid TOCTOU).
    5. Generate a pair_id, create ReciprocalPair, update both requests.
    6. Commit atomically.  On IntegrityError (race condition), roll back
       and return already_matched=True if one of the requests now has a pair_id.

    Returns:
        ReciprocalDetectionResult(matched=True, pair=...) if a pair was created.
        ReciprocalDetectionResult(matched=False)          if no match found.
    """
    # ── 1. Eligibility check ─────────────────────────────────────────────
    if not _is_eligible(request):
        return ReciprocalDetectionResult(matched=False)

    # ── 2. Lock current row (PostgreSQL only; SQLite ignores with_for_update) ──
    try:
        db.execute(
            select(CommunicationRequest)
            .where(CommunicationRequest.id == request.id)
            .with_for_update(skip_locked=False)
        )
    except Exception:
        pass  # SQLite does not support FOR UPDATE — safe in test environment

    # Re-fetch after lock to get latest state
    request = db.get(CommunicationRequest, request.id)
    if request is None or not _is_eligible(request):
        return ReciprocalDetectionResult(matched=False)

    # ── 3. Search for reverse candidate ─────────────────────────────────
    candidates = (
        db.query(CommunicationRequest)
        .filter(
            CommunicationRequest.caller_id   == request.receiver_id,
            CommunicationRequest.receiver_id == request.caller_id,
            CommunicationRequest.id          != request.id,
            CommunicationRequest.status      == RequestStatus.PENDING,
            CommunicationRequest.reciprocal_flag == False,  # noqa: E712
            CommunicationRequest.pair_id     == None,       # noqa: E711
        )
        .order_by(CommunicationRequest.request_time.asc())
        .all()
    )

    # ── 4. Find the best candidate within the window ──────────────────────
    best: Optional[CommunicationRequest] = None
    for candidate in candidates:
        if not _within_window(request.request_time, candidate.request_time):
            continue
        best = candidate
        break  # ordered by request_time — take the earliest eligible one

    if best is None:
        return ReciprocalDetectionResult(matched=False)

    # ── 4b. Lock candidate row ────────────────────────────────────────────
    try:
        db.execute(
            select(CommunicationRequest)
            .where(CommunicationRequest.id == best.id)
            .with_for_update(skip_locked=False)
        )
    except Exception:
        pass

    # Re-fetch after lock — guard against TOCTOU
    best = db.get(CommunicationRequest, best.id)
    if best is None or not _is_eligible(best):
        return ReciprocalDetectionResult(matched=False)

    # ── 5. Create the reciprocal pair ─────────────────────────────────────
    # Determine canonical ordering: the request with the earlier request_time
    # is request_a; the later one is request_b.
    if _as_aware(request.request_time) <= _as_aware(best.request_time):
        req_a, req_b = request, best
    else:
        req_a, req_b = best, request

    # Generate unique pair_id with collision retry
    pair_id_str: Optional[str] = None
    for _ in range(_MAX_PAIR_ID_RETRIES):
        candidate_pid = generate_pair_id()
        if db.query(ReciprocalPair).filter(
            ReciprocalPair.pair_id == candidate_pid
        ).first() is None:
            pair_id_str = candidate_pid
            break

    if pair_id_str is None:
        raise RuntimeError("Failed to generate a unique pair ID")

    now = _now_utc()
    diff_ms = _time_diff_ms(req_a.request_time, req_b.request_time)

    pair = ReciprocalPair(
        pair_id          = pair_id_str,
        request_a_id     = req_a.id,
        request_b_id     = req_b.id,
        detected_at      = now,
        time_difference_ms = diff_ms,
        status           = PairStatus.DETECTED,
    )
    db.add(pair)

    # Update both requests atomically in the same transaction
    req_a.reciprocal_flag = True
    req_a.pair_id         = pair_id_str
    req_b.reciprocal_flag = True
    req_b.pair_id         = pair_id_str

    try:
        db.commit()
        db.refresh(pair)
        db.refresh(req_a)
        db.refresh(req_b)
        return ReciprocalDetectionResult(matched=True, pair=pair)

    except IntegrityError:
        # Race condition: another transaction created the pair first.
        db.rollback()
        # Refresh the request — it may now have a pair_id
        db.refresh(request)
        if request.pair_id is not None:
            existing_pair = db.query(ReciprocalPair).filter(
                ReciprocalPair.pair_id == request.pair_id
            ).first()
            return ReciprocalDetectionResult(matched=True, pair=existing_pair)
        return ReciprocalDetectionResult(matched=False)


# ── Lookup helpers ────────────────────────────────────────────────────────────

def get_pair_by_pid(
    pair_id: str,
    current_user_id: int,
    db: Session,
) -> ReciprocalPair:
    """
    Fetch a reciprocal pair.
    Only users who are caller/receiver of either request may access it.

    Raises:
        LookupError: pair not found.
        PermissionError: current user is not a participant.
    """
    pair = db.query(ReciprocalPair).filter(
        ReciprocalPair.pair_id == pair_id
    ).first()

    if pair is None:
        raise LookupError(f"Reciprocal pair {pair_id!r} not found")

    # Authorisation: user must be caller or receiver of either request
    participants = {
        pair.request_a.caller_id,
        pair.request_a.receiver_id,
        pair.request_b.caller_id,
        pair.request_b.receiver_id,
    }
    if current_user_id not in participants:
        raise PermissionError("You are not authorised to view this reciprocal pair")

    return pair


def get_my_pairs(
    current_user_id: int,
    db: Session,
) -> list[ReciprocalPair]:
    """
    Return all reciprocal pairs where the authenticated user is a participant
    (caller or receiver of either request in the pair).
    """
    from app.models.communication_request import CommunicationRequest as CR
    from sqlalchemy import select as sa_select

    # Find all request IDs where the user participated
    user_request_ids_q = sa_select(CR.id).where(
        (CR.caller_id == current_user_id) | (CR.receiver_id == current_user_id)
    )

    pairs = db.query(ReciprocalPair).filter(
        (ReciprocalPair.request_a_id.in_(user_request_ids_q)) |
        (ReciprocalPair.request_b_id.in_(user_request_ids_q))
    ).order_by(ReciprocalPair.detected_at.desc()).all()

    return pairs
