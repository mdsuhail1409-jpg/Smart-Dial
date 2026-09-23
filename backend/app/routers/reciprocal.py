"""
Reciprocal pairs router.

  GET /api/reciprocal-pairs                → my pairs (auth required)
  GET /api/reciprocal-pairs/{pair_id}      → single pair (participants only)
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.models.communication_decision import CommunicationDecision
from app.schemas.call import UserSummary
from app.schemas.reciprocal import (
    ReciprocalPairResponse,
    ReciprocalPairListResponse,
    ReciprocalRequestSummary,
)
from app.services.reciprocal_detection_service import (
    get_pair_by_pid,
    get_my_pairs,
)

router = APIRouter(prefix="/api/reciprocal-pairs", tags=["reciprocal-pairs"])


def _pair_to_response(pair, db: Session | None = None) -> ReciprocalPairResponse:
    """Convert a ReciprocalPair ORM object to the response schema with telemetry."""
    decision_type = None
    reason_code = None
    if db is not None:
        dec = db.query(CommunicationDecision).filter(CommunicationDecision.pair_id == pair.pair_id).first()
        if dec:
            decision_type = dec.decision_type.value
            reason_code = dec.reason_code.value

    return ReciprocalPairResponse(
        pair_id    = pair.pair_id,
        request_a  = ReciprocalRequestSummary(
            request_id = pair.request_a.request_id,
            caller     = UserSummary(id=pair.request_a.caller.id,   name=pair.request_a.caller.name),
            receiver   = UserSummary(id=pair.request_a.receiver.id, name=pair.request_a.receiver.name),
        ),
        request_b  = ReciprocalRequestSummary(
            request_id = pair.request_b.request_id,
            caller     = UserSummary(id=pair.request_b.caller.id,   name=pair.request_b.caller.name),
            receiver   = UserSummary(id=pair.request_b.receiver.id, name=pair.request_b.receiver.name),
        ),
        detected_at        = pair.detected_at,
        time_difference_ms = pair.time_difference_ms,
        status             = pair.status.value,
        decision_type      = decision_type,
        reason_code        = reason_code,
    )


@router.get(
    "",
    response_model=ReciprocalPairListResponse,
    summary="My reciprocal pairs (auth required)",
)
def list_my_pairs(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ReciprocalPairListResponse:
    """Return all reciprocal pairs where the current user is a participant."""
    pairs = get_my_pairs(current_user_id=current_user.id, db=db)
    return ReciprocalPairListResponse(
        pairs=[_pair_to_response(p, db=db) for p in pairs],
        total=len(pairs),
    )


@router.get(
    "/{pair_id}",
    response_model=ReciprocalPairResponse,
    summary="Get a reciprocal pair by ID (participants only)",
)
def get_pair(
    pair_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ReciprocalPairResponse:
    """
    Return a single reciprocal pair.
    Only the caller/receiver of either constituent request may access it.
    """
    try:
        pair = get_pair_by_pid(
            pair_id        = pair_id,
            current_user_id = current_user.id,
            db             = db,
        )
    except LookupError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except PermissionError as exc:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))

    return _pair_to_response(pair, db=db)
