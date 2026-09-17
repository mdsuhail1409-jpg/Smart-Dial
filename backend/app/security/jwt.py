"""
JWT creation and verification.

The secret key comes exclusively from environment configuration.
User identity is encoded as the 'sub' (subject) claim using the user's
integer ID converted to a string — never trusted raw from the client.
"""

from datetime import datetime, timedelta, timezone
from typing import Any

from jose import JWTError, jwt

from app.config import get_settings

settings = get_settings()


def create_access_token(subject: int) -> str:
    """
    Create a signed JWT whose 'sub' claim is the user's database ID.

    Args:
        subject: The authenticated user's integer primary key.

    Returns:
        Signed JWT string.
    """
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
    )
    payload: dict[str, Any] = {
        "sub": str(subject),
        "exp": expire,
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def decode_access_token(token: str) -> dict[str, Any] | None:
    """
    Decode and verify a JWT.

    Returns the payload dict if valid, or None if the token is
    expired, malformed, or uses the wrong signature.
    """
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
        )
        return payload
    except JWTError:
        return None
