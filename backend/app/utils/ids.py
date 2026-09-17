"""
Request ID generation for communication requests.

Format: CR_XXXXXX  (6 uppercase alphanumeric characters)
Example: CR_98AB71

Rules:
- Prefix is always CR_
- The random portion uses secrets.token_hex for cryptographic randomness
- Caller identity is never embedded in the ID
- Collision handling: the service layer should retry on the extremely
  unlikely event of a duplicate (enforced by the DB unique constraint).
"""

import secrets
import string

_ALPHABET = string.ascii_uppercase + string.digits  # A-Z 0-9
_RANDOM_LENGTH = 6


def generate_request_id() -> str:
    """
    Generate a unique, human-readable call request ID.

    Returns a string of the form ``CR_XXXXXX`` where X is a random
    uppercase alphanumeric character.
    """
    random_part = "".join(
        secrets.choice(_ALPHABET) for _ in range(_RANDOM_LENGTH)
    )
    return f"CR_{random_part}"


def generate_pair_id() -> str:
    """Returns a string of the form ``RP_XXXXXX``."""
    random_part = "".join(
        secrets.choice(_ALPHABET) for _ in range(_RANDOM_LENGTH)
    )
    return f"RP_{random_part}"


def generate_decision_id() -> str:
    """
    Generate a unique, human-readable decision ID.

    Returns a string of the form ``D_XXXXXX`` where X is a random
    uppercase alphanumeric character.

    Example: D_7BF93A
    """
    random_part = "".join(
        secrets.choice(_ALPHABET) for _ in range(_RANDOM_LENGTH)
    )
    return f"D_{random_part}"
