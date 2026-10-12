"""
Phone Number Normalizer — Google E.164 Standard

Normalizes user inputs, contact entries, and call intents into
canonical international E.164 format (+<country_code><national_number>).
Guarantees consistent matching across carriers, dialers, and formats.
"""

import phonenumbers
from typing import Optional


def normalize_to_e164(phone: str, default_region: str = "IN") -> str:
    """
    Convert any valid phone number string into canonical E.164 format.

    Examples:
        "9876543210"        -> "+919876543210"
        "09876543210"       -> "+919876543210"
        "+91 98765 43210"   -> "+919876543210"
        "+91-98765-43210"   -> "+919876543210"
        "+1 202 555 0123"   -> "+12025550123"

    Raises:
        ValueError if the phone number cannot be parsed or is not a possible number.
    """
    if not phone or not isinstance(phone, str):
        raise ValueError("Phone number must be a non-empty string.")

    cleaned = phone.strip()
    # If starts with +, parse without forcing default region
    try:
        parsed = phonenumbers.parse(cleaned, default_region if not cleaned.startswith("+") else None)
    except phonenumbers.NumberParseException as exc:
        raise ValueError(f"Unable to parse phone number '{phone}': {exc}")

    if not phonenumbers.is_possible_number(parsed):
        raise ValueError(f"Phone number '{phone}' is not a possible telephone number.")

    return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)


def is_valid_phone(phone: str, default_region: str = "IN") -> bool:
    """Check if a phone number string can be normalized to valid E.164."""
    try:
        normalize_to_e164(phone, default_region=default_region)
        return True
    except Exception:
        return False
