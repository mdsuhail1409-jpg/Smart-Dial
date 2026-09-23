"""
Users router: /api/users  (authentication required).
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User, ReciprocalCallPreference
from app.schemas.user import UserResponse, UserListResponse, UserPreferenceUpdate

router = APIRouter(prefix="/api/users", tags=["users"])


@router.get(
    "/me",
    response_model=UserResponse,
    summary="Get current user profile (auth required)",
)
def get_me(
    current_user: User = Depends(get_current_user),
) -> UserResponse:
    """Return the currently authenticated user."""
    return UserResponse.model_validate(current_user)


@router.patch(
    "/me/preferences",
    response_model=UserResponse,
    summary="Update reciprocal call and context preferences (auth required)",
)
def update_preferences(
    payload: UserPreferenceUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> UserResponse:
    """
    Update reciprocal calling preferences, DND mode, or VIP contacts.
    """
    if payload.reciprocal_call_preference is not None:
        try:
            current_user.reciprocal_call_preference = ReciprocalCallPreference(
                payload.reciprocal_call_preference
            )
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Invalid reciprocal_call_preference: {payload.reciprocal_call_preference}",
            )

    if payload.dnd_enabled is not None:
        current_user.dnd_enabled = payload.dnd_enabled

    if payload.vip_contacts is not None:
        current_user.vip_contacts = payload.vip_contacts.strip()

    db.add(current_user)
    db.commit()
    db.refresh(current_user)
    return UserResponse.model_validate(current_user)


@router.get(
    "",
    response_model=UserListResponse,
    summary="List all registered users (auth required)",
)
def list_users(
    db: Session = Depends(get_db),
    _current_user: User = Depends(get_current_user),
) -> UserListResponse:
    """
    Return all registered users.

    - Requires a valid JWT Bearer token.
    - password_hash is never included in the response.
    """
    users = db.query(User).order_by(User.name).all()
    return UserListResponse(
        users=[UserResponse.model_validate(u) for u in users],
        total=len(users),
    )


@router.get(
    "/{user_id}",
    response_model=UserResponse,
    summary="Get a single user by ID (auth required)",
)
def get_user(
    user_id: int,
    db: Session = Depends(get_db),
    _current_user: User = Depends(get_current_user),
) -> UserResponse:
    """
    Return a single user by their database ID.

    - Requires a valid JWT Bearer token.
    - password_hash is never included in the response.
    """
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"User with id {user_id} not found",
        )
    return UserResponse.model_validate(user)
