"""
Users router: /api/users  (authentication required).
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.user import UserResponse, UserListResponse

router = APIRouter(prefix="/api/users", tags=["users"])


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
