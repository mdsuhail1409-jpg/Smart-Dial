"""
Phase 2 Unit Tests: Google E.164 Normalization & Phone OTP Verification
"""

import pytest
from app.utils.phone_normalizer import normalize_to_e164, is_valid_phone
from app.services.otp_service import send_otp, verify_otp


def test_normalize_indian_phone_numbers():
    """Verify various common Indian dialing formats resolve to identical +91 E.164."""
    variants = [
        "9876543210",
        "09876543210",
        "+91 98765 43210",
        "+91-98765-43210",
        "+919876543210",
    ]
    for v in variants:
        assert normalize_to_e164(v) == "+919876543210"


def test_normalize_international_phone_numbers():
    """Verify international prefix parsing."""
    us_phone = "+1 202 555 0123"
    assert normalize_to_e164(us_phone) == "+12025550123"


def test_invalid_phone_numbers():
    """Verify malformed or impossible phone numbers raise ValueError."""
    invalid = ["123", "abcdef", "", "+99999999999999999999"]
    for inv in invalid:
        with pytest.raises(ValueError):
            normalize_to_e164(inv)
        assert is_valid_phone(inv) is False


def test_otp_generation_and_verification():
    """Verify OTP dispatch and validation flow."""
    phone = "+919876543210"
    res = send_otp(phone)
    assert res["status"] == "sent"
    code = res["dev_code"]
    assert len(code) == 6
    assert code.isdigit()

    # Wrong code should fail
    assert verify_otp(phone, "000000") is False

    # Correct code should succeed
    assert verify_otp(phone, code) is True

    # Consumed code cannot be reused
    assert verify_otp(phone, code) is False


def test_otp_endpoints(client):
    """Verify REST endpoints /api/auth/otp/send and /api/auth/otp/verify."""
    phone = "9876543210"

    # Send OTP
    r1 = client.post("/api/auth/otp/send", json={"phone": phone})
    assert r1.status_code == 200
    data1 = r1.json()
    assert data1["phone"] == "+919876543210"
    code = data1["dev_code"]

    # Verify with wrong code
    r2 = client.post("/api/auth/otp/verify", json={"phone": phone, "code": "999999"})
    assert r2.status_code == 400

    # Verify with correct code
    r3 = client.post("/api/auth/otp/verify", json={"phone": phone, "code": code})
    assert r3.status_code == 200
    assert r3.json()["verified"] is True
