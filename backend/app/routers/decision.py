"""
Decision router — Phase 6 endpoints.

  POST /api/reciprocal-pairs/{pair_id}/decision         → evaluate/create decision
  GET  /api/reciprocal-pairs/{pair_id}/decision         → get existing decision
  POST /api/reciprocal-pairs/{pair_id}/decision/respond → user responds (ASK_USER)
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.decision import DecisionResponse, DecisionRespondRequest
from app.services.decision_service import (
    evaluate_decision,
    get_decision,
    respond_to_decision,
)

router = APIRouter(prefix="/api/reciprocal-pairs", tags=["decisions"])


def _to_response(d) -> DecisionResponse:
    return DecisionResponse(
        pair_id             = d.pair_id,
        decision_id         = d.decision_id,
        decision_type       = d.decision_type.value,
        selected_request_id = d.selected_request_id,
        reason_code         = d.reason_code.value,
        status              = d.status.value,
        context_snapshot    = d.context_snapshot,
        created_at          = d.created_at,
        updated_at          = d.updated_at,
    )


@router.post(
    "/{pair_id}/decision",
    response_model=DecisionResponse,
    status_code=status.HTTP_200_OK,
    summary="Evaluate or return existing decision for a reciprocal pair",
)
def create_or_get_decision(
    pair_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> DecisionResponse:
    """
    Evaluate the context and produce a decision for the reciprocal pair.
    Idempotent: returns the existing decision if already evaluated.
    Only participants may call this endpoint.
    This endpoint does NOT place, cancel, or suppress any SIM/cellular call.
    """
    try:
        decision = evaluate_decision(
            pair_id      = pair_id,
            current_user = current_user,
            db           = db,
        )
    except LookupError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except PermissionError as exc:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(exc))

    return _to_response(decision)


@router.get(
    "/{pair_id}/decision",
    response_model=DecisionResponse,
    summary="Get the decision for a reciprocal pair (participants only)",
)
def fetch_decision(
    pair_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> DecisionResponse:
    """
    Return the existing decision for a pair.
    Returns 404 if no decision has been evaluated yet.
    """
    try:
        decision = get_decision(
            pair_id      = pair_id,
            current_user = current_user,
            db           = db,
        )
    except LookupError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except PermissionError as exc:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))

    return _to_response(decision)


@router.post(
    "/{pair_id}/decision/respond",
    response_model=DecisionResponse,
    summary="Record user's explicit choice for an ASK_USER decision",
)
def respond(
    pair_id: str,
    payload: DecisionRespondRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> DecisionResponse:
    """
    Record the user's explicit response to a decision.
    Valid actions: ALLOW_A_TO_B | ALLOW_B_TO_A | BLOCK
    Only participants may respond.
    This endpoint does NOT place or cancel any SIM/cellular call.
    """
    try:
        decision = respond_to_decision(
            pair_id      = pair_id,
            action       = payload.action,
            current_user = current_user,
            db           = db,
        )
    except LookupError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except PermissionError as exc:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc))

    return _to_response(decision)
