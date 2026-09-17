"""
Password hashing and verification using bcrypt via passlib.

Plaintext passwords never leave this module — only hashes are returned.
"""

from passlib.context import CryptContext

# bcrypt is the recommended algorithm; deprecated schemes trigger auto-rehashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(plaintext: str) -> str:
    """Return the bcrypt hash of a plaintext password."""
    return pwd_context.hash(plaintext)


def verify_password(plaintext: str, hashed: str) -> bool:
    """
    Safely compare a plaintext password against a stored hash.

    Returns True if they match, False otherwise.
    Never raises — an invalid hash string returns False.
    """
    try:
        return pwd_context.verify(plaintext, hashed)
    except Exception:
        return False
