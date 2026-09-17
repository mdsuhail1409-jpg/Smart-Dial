"""
Calls router — communication request endpoints.

  POST /api/calls/request              → create call intent
  GET  /api/calls                      → my call requests
  GET  /api/calls/{request_id}         → single request (caller/receiver only)
  POST /api/calls/{request_id}/cancel  → cancel PENDING request (caller only)
"""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.call import (
    CallRequestListResponse,
    CallRequestResponse,
    CreateCallRequest,
    UserSummary,
)
from app.services.call_request_service import (
    cancel_request,
    create_call_request,
    get_my_requests,
    get_request_by_rid,
)
from app.services.reciprocal_detection_service import detect_reciprocal

router = APIRouter(prefix="/api/calls", tags=["calls"])


def _to_response(req) -> CallRequestResponse:
    """Convert a CommunicationRequest ORM object to the response schema."""
    return CallRequestResponse(
        request_id=req.request_id,
        caller=UserSummary(id=req.caller.id, name=req.caller.name),
        receiver=UserSummary(id=req.receiver.id, name=req.receiver.name),
        status=req.status.value,
        reciprocal_flag=req.reciprocal_flag,
        pair_id=req.pair_id,
        request_time=req.request_time,
        expires_at=req.expires_at,
    )


@router.post(
    "/request",
    response_model=CallRequestResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a call request (auth required)",
)
def create_request(
    payload: CreateCallRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> CallRequestResponse:
    """
    Create a new PENDING communication request.

    The caller is always the authenticated JWT user.
    Flutter sends only `receiver_id` — never `caller_id`.
    """
    try:
        req = create_call_request(
            caller=current_user,
            receiver_id=payload.receiver_id,
            db=db,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        )
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )

    # Attempt reciprocal detection — runs in the same DB session.
    # A failure here must NOT prevent the call request from being returned.
    try:
        detect_reciprocal(request=req, db=db)
        db.refresh(req)   # pick up pair_id / reciprocal_flag if matched
    except Exception:
        pass  # detection failure is non-fatal; request is still valid

    return _to_response(req)


@router.get(
    "",
    response_model=CallRequestListResponse,
    summary="My call requests (auth required)",
)
def list_my_requests(
    status: str | None = Query(default=None, description="Filter by status (e.g. PENDING)"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> CallRequestListResponse:
    """
    Return all communication requests where the current user is caller or receiver.
    Optionally filter by status using ?status=PENDING.
    """
    requests = get_my_requests(
        current_user=current_user,
        db=db,
        status_filter=status,
    )
    return CallRequestListResponse(
        requests=[_to_response(r) for r in requests],
        total=len(requests),
    )


@router.get(
    "/{request_id}",
    response_model=CallRequestResponse,
    summary="Get a call request by ID (caller/receiver only)",
)
def get_request(
    request_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> CallRequestResponse:
    """
    Return a single call request.
    Only the caller or receiver may view it; third parties get 403.
    """
    try:
        req = get_request_by_rid(
            request_id=request_id,
            current_user=current_user,
            db=db,
        )
    except LookupError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except PermissionError as exc:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))

    return _to_response(req)


@router.post(
    "/{request_id}/cancel",
    response_model=CallRequestResponse,
    summary="Cancel a PENDING call request (caller only)",
)
def cancel(
    request_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> CallRequestResponse:
    """
    Cancel a PENDING call request.
    Only the original caller may cancel.
    Returns 409 if already cancelled or expired.
    """
    try:
        req = cancel_request(
            request_id=request_id,
            current_user=current_user,
            db=db,
        )
    except LookupError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except PermissionError as exc:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))

    return _to_response(req)
