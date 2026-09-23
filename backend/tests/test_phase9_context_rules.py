"""
Unit tests for Phase 9 — VIP Contacts, DND Modes & Contextual Collision Rules.
"""

import pytest
from datetime import datetime, timezone
from unittest.mock import MagicMock

from app.models.user import User, ReciprocalCallPreference, UserStatus
from app.models.communication_request import CommunicationRequest, RequestStatus
from app.models.communication_decision import DecisionType, ReasonCode
from app.services.context_engine import ContextSnapshot, build_context
from app.services.conflict_resolution_engine import resolve


def make_mock_request(req_id: int, caller_id: int, receiver_id: int) -> CommunicationRequest:
    req = MagicMock(spec=CommunicationRequest)
    req.id = req_id
    req.caller_id = caller_id
    req.receiver_id = receiver_id
    req.caller_phone = f"+123456789{caller_id}"
    req.receiver_phone = f"+123456789{receiver_id}"
    req.status = RequestStatus.PENDING
    req.request_time = datetime.now(timezone.utc)
    return req


def test_phase9_mutual_dnd_without_vip():
    """Mutual DND with no VIPs blocks both calls."""
    ctx = ContextSnapshot(
        user_a_id=1,
        user_a_status="ACTIVE",
        user_a_preference="ASK",
        user_b_id=2,
        user_b_status="ACTIVE",
        user_b_preference="ASK",
        dnd_a="TRUE",
        dnd_b="TRUE",
        vip_a_in_b_contacts="FALSE",
        vip_b_in_a_contacts="FALSE",
    )
    req_a = make_mock_request(101, 1, 2)
    req_b = make_mock_request(102, 2, 1)

    result = resolve(ctx, req_a, req_b)
    assert result.decision_type == DecisionType.BLOCK
    assert result.reason_code == ReasonCode.DND_ACTIVE
    assert result.selected_request is None


def test_phase9_dnd_b_vip_a_bypass():
    """User B has DND active, but User A is VIP -> VIP call breaks through."""
    ctx = ContextSnapshot(
        user_a_id=1,
        user_a_status="ACTIVE",
        user_a_preference="ASK",
        user_b_id=2,
        user_b_status="ACTIVE",
        user_b_preference="ASK",
        dnd_a="FALSE",
        dnd_b="TRUE",
        vip_a_in_b_contacts="TRUE",
        vip_b_in_a_contacts="FALSE",
    )
    req_a = make_mock_request(101, 1, 2)
    req_b = make_mock_request(102, 2, 1)

    result = resolve(ctx, req_a, req_b)
    assert result.decision_type == DecisionType.ALLOW_A_TO_B
    assert result.reason_code == ReasonCode.VIP_PRIORITY
    assert result.selected_request == req_a


def test_phase9_dnd_b_non_vip_routed_to_a():
    """User B has DND active and A is not VIP -> B's outgoing call to A can proceed."""
    ctx = ContextSnapshot(
        user_a_id=1,
        user_a_status="ACTIVE",
        user_a_preference="ASK",
        user_b_id=2,
        user_b_status="ACTIVE",
        user_b_preference="ASK",
        dnd_a="FALSE",
        dnd_b="TRUE",
        vip_a_in_b_contacts="FALSE",
        vip_b_in_a_contacts="FALSE",
    )
    req_a = make_mock_request(101, 1, 2)
    req_b = make_mock_request(102, 2, 1)

    result = resolve(ctx, req_a, req_b)
    assert result.decision_type == DecisionType.ALLOW_B_TO_A
    assert result.reason_code == ReasonCode.DND_ACTIVE
    assert result.selected_request == req_b


def test_phase9_dnd_a_vip_b_bypass():
    """User A has DND active, User B is VIP -> B breaks through to A."""
    ctx = ContextSnapshot(
        user_a_id=1,
        user_a_status="ACTIVE",
        user_a_preference="ASK",
        user_b_id=2,
        user_b_status="ACTIVE",
        user_b_preference="ASK",
        dnd_a="TRUE",
        dnd_b="FALSE",
        vip_a_in_b_contacts="FALSE",
        vip_b_in_a_contacts="TRUE",
    )
    req_a = make_mock_request(101, 1, 2)
    req_b = make_mock_request(102, 2, 1)

    result = resolve(ctx, req_a, req_b)
    assert result.decision_type == DecisionType.ALLOW_B_TO_A
    assert result.reason_code == ReasonCode.VIP_PRIORITY
    assert result.selected_request == req_b


def test_phase9_vip_asymmetry_without_dnd():
    """When neither user is on DND, VIP status prioritizes the favored caller."""
    ctx = ContextSnapshot(
        user_a_id=1,
        user_a_status="ACTIVE",
        user_a_preference="ASK",
        user_b_id=2,
        user_b_status="ACTIVE",
        user_b_preference="ASK",
        dnd_a="FALSE",
        dnd_b="FALSE",
        vip_a_in_b_contacts="TRUE",
        vip_b_in_a_contacts="FALSE",
    )
    req_a = make_mock_request(101, 1, 2)
    req_b = make_mock_request(102, 2, 1)

    result = resolve(ctx, req_a, req_b)
    assert result.decision_type == DecisionType.ALLOW_A_TO_B
    assert result.reason_code == ReasonCode.VIP_PRIORITY
    assert result.selected_request == req_a


def test_phase9_preferences_api_update(client):
    """Test PATCH /api/users/me/preferences updates DND and VIP fields."""
    user_payload = {
        "name": "Phase 9 User",
        "email": "p9@example.com",
        "phone": "+19990001111",
        "password": "Password123!",
    }
    client.post("/api/auth/register", json=user_payload)
    login_resp = client.post("/api/auth/login", json={
        "email": user_payload["email"],
        "password": user_payload["password"],
    })
    token = login_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    update_data = {
        "reciprocal_call_preference": "PREFER_OUTGOING",
        "dnd_enabled": True,
        "vip_contacts": "+19998887777, +18887776666",
    }
    resp = client.patch("/api/users/me/preferences", json=update_data, headers=headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["reciprocal_call_preference"] == "PREFER_OUTGOING"
    assert data["dnd_enabled"] is True
    assert "+19998887777" in data["vip_contacts"]

    # Verify GET /api/users/me reflects changes
    me_resp = client.get("/api/users/me", headers=headers)
    assert me_resp.status_code == 200
    assert me_resp.json()["dnd_enabled"] is True
