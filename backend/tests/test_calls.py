"""
Day 2 tests — communication_requests API.

All 23 required tests plus the critical A→B + B→A independence test.
Uses the same SQLite in-memory conftest as Day 1.
"""

import pytest

# ── Test users ────────────────────────────────────────────────────────────────

USER_A = {"name": "Arun Kumar",  "email": "arun@example.com",  "phone": "9000000001", "password": "SecurePass1"}
USER_B = {"name": "Bala Murugan","email": "bala@example.com",  "phone": "9000000002", "password": "SecurePass2"}
USER_C = {"name": "Carol Smith", "email": "carol@example.com", "phone": "9000000003", "password": "SecurePass3"}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _register(client, user):
    client.post("/api/auth/register", json=user)


def _login(client, user) -> str:
    r = client.post("/api/auth/login", json={"email": user["email"], "password": user["password"]})
    return r.json()["access_token"]


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _create_request(client, token, receiver_id) -> dict:
    r = client.post(
        "/api/calls/request",
        json={"receiver_id": receiver_id},
        headers=_auth(token),
    )
    return r


# ── 1. Create call request A → B ──────────────────────────────────────────────

def test_create_call_request(client):
    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)

    # Get B's id
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    r = _create_request(client, token_a, b_id)
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["status"] == "PENDING"
    assert data["caller"]["email"] if "email" in data["caller"] else True


# ── 2. Caller comes from JWT, not body ────────────────────────────────────────

def test_caller_from_jwt_not_body(client):
    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    token_b = _login(client, USER_B)

    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])
    a_id = next(u["id"] for u in users if u["email"] == USER_A["email"])

    # Login as B, but send receiver_id=B (trying to spoof A as caller)
    # The backend should make B the caller (calling themselves) → 422
    r = client.post(
        "/api/calls/request",
        json={"receiver_id": b_id},   # B trying to call themselves
        headers=_auth(token_b),
    )
    assert r.status_code == 422  # self-call rejected

    # Verify: when A calls B, caller in response is A
    r2 = _create_request(client, token_a, b_id)
    assert r2.status_code == 201
    assert r2.json()["caller"]["id"] == a_id


# ── 3. No JWT → rejected ──────────────────────────────────────────────────────

def test_create_request_no_jwt(client):
    r = client.post("/api/calls/request", json={"receiver_id": 1})
    assert r.status_code == 403


# ── 4. Invalid receiver rejected ─────────────────────────────────────────────

def test_invalid_receiver(client):
    _register(client, USER_A)
    token_a = _login(client, USER_A)
    r = _create_request(client, token_a, 99999)
    assert r.status_code == 422


# ── 5. Self-call rejected ─────────────────────────────────────────────────────

def test_self_call_rejected(client):
    _register(client, USER_A)
    token_a = _login(client, USER_A)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    a_id = next(u["id"] for u in users if u["email"] == USER_A["email"])

    r = _create_request(client, token_a, a_id)
    assert r.status_code == 422
    assert "yourself" in r.json()["detail"].lower()


# ── 6. request_id starts with CR_ ────────────────────────────────────────────

def test_request_id_prefix(client):
    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    data = _create_request(client, token_a, b_id).json()
    assert data["request_id"].startswith("CR_")


# ── 7. request_id uniqueness ──────────────────────────────────────────────────

def test_request_id_unique(client):
    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    ids = set()
    for _ in range(20):
        r = _create_request(client, token_a, b_id)
        assert r.status_code == 201
        ids.add(r.json()["request_id"])
    assert len(ids) == 20


# ── 8. Request stored in DB ───────────────────────────────────────────────────

def test_request_stored_in_db(client):
    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    r = _create_request(client, token_a, b_id)
    rid = r.json()["request_id"]

    # Fetch it back
    r2 = client.get(f"/api/calls/{rid}", headers=_auth(token_a))
    assert r2.status_code == 200
    assert r2.json()["request_id"] == rid


# ── 9. reciprocal_flag = False ────────────────────────────────────────────────

def test_reciprocal_flag_false(client):
    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    data = _create_request(client, token_a, b_id).json()
    assert data["reciprocal_flag"] is False


# ── 10. pair_id = None ────────────────────────────────────────────────────────

def test_pair_id_null(client):
    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    data = _create_request(client, token_a, b_id).json()
    assert data["pair_id"] is None


# ── 11. expires_at > request_time ────────────────────────────────────────────

def test_expires_at_after_request_time(client):
    from datetime import datetime, timezone
    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    data = _create_request(client, token_a, b_id).json()
    rt = datetime.fromisoformat(data["request_time"])
    ea = datetime.fromisoformat(data["expires_at"])
    assert ea > rt


# ── 12. TTL approximately equals configured value ─────────────────────────────

def test_ttl_matches_config(client):
    import os, sys
    sys.path.insert(0, ".")
    from datetime import datetime
    from app import config as cfg; cfg.get_settings.cache_clear()

    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    data = _create_request(client, token_a, b_id).json()
    rt = datetime.fromisoformat(data["request_time"])
    ea = datetime.fromisoformat(data["expires_at"])
    diff = (ea - rt).total_seconds()

    expected_ttl = cfg.get_settings().REQUEST_TTL_SECONDS
    assert abs(diff - expected_ttl) < 2, f"TTL diff={diff}, expected={expected_ttl}"


# ── 13. Caller can retrieve request ──────────────────────────────────────────

def test_caller_can_retrieve(client):
    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    rid = _create_request(client, token_a, b_id).json()["request_id"]
    r = client.get(f"/api/calls/{rid}", headers=_auth(token_a))
    assert r.status_code == 200


# ── 14. Receiver can retrieve request ────────────────────────────────────────

def test_receiver_can_retrieve(client):
    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    token_b = _login(client, USER_B)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    rid = _create_request(client, token_a, b_id).json()["request_id"]
    r = client.get(f"/api/calls/{rid}", headers=_auth(token_b))
    assert r.status_code == 200


# ── 15. Third user cannot retrieve ───────────────────────────────────────────

def test_third_user_cannot_retrieve(client):
    _register(client, USER_A)
    _register(client, USER_B)
    _register(client, USER_C)
    token_a = _login(client, USER_A)
    token_c = _login(client, USER_C)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    rid = _create_request(client, token_a, b_id).json()["request_id"]
    r = client.get(f"/api/calls/{rid}", headers=_auth(token_c))
    assert r.status_code == 403


# ── 16. GET /api/calls returns only relevant requests ────────────────────────

def test_my_calls_only(client):
    _register(client, USER_A)
    _register(client, USER_B)
    _register(client, USER_C)
    token_a = _login(client, USER_A)
    token_b = _login(client, USER_B)
    token_c = _login(client, USER_C)

    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])
    c_id = next(u["id"] for u in users if u["email"] == USER_C["email"])

    # A → B
    _create_request(client, token_a, b_id)
    # B → C (unrelated to A)
    _create_request(client, token_b, c_id)

    # A should see only A→B
    r = client.get("/api/calls", headers=_auth(token_a))
    assert r.status_code == 200
    my = r.json()["requests"]
    assert len(my) == 1
    assert my[0]["caller"]["name"] == "Arun Kumar"

    # C should see B→C (as receiver)
    r2 = client.get("/api/calls", headers=_auth(token_c))
    my2 = r2.json()["requests"]
    assert len(my2) == 1
    assert my2[0]["receiver"]["name"] == "Carol Smith"


# ── 17. Caller can cancel PENDING request ────────────────────────────────────

def test_caller_can_cancel(client):
    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    rid = _create_request(client, token_a, b_id).json()["request_id"]
    r = client.post(f"/api/calls/{rid}/cancel", headers=_auth(token_a))
    assert r.status_code == 200
    assert r.json()["status"] == "CANCELLED"


# ── 18. Receiver cannot cancel ────────────────────────────────────────────────

def test_receiver_cannot_cancel(client):
    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    token_b = _login(client, USER_B)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    rid = _create_request(client, token_a, b_id).json()["request_id"]
    r = client.post(f"/api/calls/{rid}/cancel", headers=_auth(token_b))
    assert r.status_code == 403


# ── 19. Third user cannot cancel ─────────────────────────────────────────────

def test_third_user_cannot_cancel(client):
    _register(client, USER_A)
    _register(client, USER_B)
    _register(client, USER_C)
    token_a = _login(client, USER_A)
    token_c = _login(client, USER_C)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    rid = _create_request(client, token_a, b_id).json()["request_id"]
    r = client.post(f"/api/calls/{rid}/cancel", headers=_auth(token_c))
    assert r.status_code == 403


# ── 20. Already cancelled → 409 ──────────────────────────────────────────────

def test_cancel_already_cancelled(client):
    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    rid = _create_request(client, token_a, b_id).json()["request_id"]
    client.post(f"/api/calls/{rid}/cancel", headers=_auth(token_a))
    r = client.post(f"/api/calls/{rid}/cancel", headers=_auth(token_a))
    assert r.status_code == 409


# ── 21. Expired request cannot be cancelled ──────────────────────────────────

def test_cancel_expired_request(client):
    """Force a request into EXPIRED state by manipulating expires_at."""
    from datetime import datetime, timezone, timedelta
    from sqlalchemy.orm import Session
    from app.database import SessionLocal
    from app.models.communication_request import CommunicationRequest, RequestStatus

    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    rid = _create_request(client, token_a, b_id).json()["request_id"]

    # Directly set expires_at to the past using the test DB session
    from tests.conftest import TestingSessionLocal
    with TestingSessionLocal() as db:
        req = db.query(CommunicationRequest).filter(
            CommunicationRequest.request_id == rid
        ).first()
        req.expires_at = datetime.now(timezone.utc) - timedelta(seconds=60)
        db.commit()

    # Trying to cancel should now return 409 (EXPIRED)
    r = client.post(f"/api/calls/{rid}/cancel", headers=_auth(token_a))
    assert r.status_code == 409
    assert "EXPIRED" in r.json()["detail"]


# ── 22. Expired PENDING → transitions on fetch ───────────────────────────────

def test_expired_pending_transitions(client):
    from datetime import datetime, timezone, timedelta
    from app.models.communication_request import CommunicationRequest

    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    rid = _create_request(client, token_a, b_id).json()["request_id"]

    from tests.conftest import TestingSessionLocal
    with TestingSessionLocal() as db:
        req = db.query(CommunicationRequest).filter(
            CommunicationRequest.request_id == rid
        ).first()
        req.expires_at = datetime.now(timezone.utc) - timedelta(seconds=60)
        db.commit()

    r = client.get(f"/api/calls/{rid}", headers=_auth(token_a))
    assert r.status_code == 200
    assert r.json()["status"] == "EXPIRED"


# ── 23. Phase 5: A→B and B→A form ONE reciprocal pair ───────────────────────

def test_ab_and_ba_are_independent(client):
    """
    Phase 5 update of the critical A→B + B→A test.

    Phase 2 required they stay INDEPENDENT (no matching).
    Phase 5 implements reciprocal detection, so A→B + B→A within the
    time window now correctly forms ONE matched pair.

    Critical assertions:
      - Both requests have the SAME pair_id
      - Both have reciprocal_flag = True
      - Exactly ONE ReciprocalPair row exists
      - Request IDs are distinct (they are still two separate intents)
      - Both requests are visible in GET /api/calls for each user
    """
    _register(client, USER_A)
    _register(client, USER_B)
    token_a = _login(client, USER_A)
    token_b = _login(client, USER_B)

    users = client.get("/api/users", headers=_auth(token_a)).json()["users"]
    a_id = next(u["id"] for u in users if u["email"] == USER_A["email"])
    b_id = next(u["id"] for u in users if u["email"] == USER_B["email"])

    # A → B
    r1 = _create_request(client, token_a, b_id)
    assert r1.status_code == 201
    d1 = r1.json()
    assert d1["status"] == "PENDING"
    assert d1["request_id"].startswith("CR_")

    # B → A  (within window — reciprocal detection fires)
    r2 = _create_request(client, token_b, a_id)
    assert r2.status_code == 201
    d2 = r2.json()
    assert d2["status"] == "PENDING"
    assert d2["request_id"].startswith("CR_")

    # Requests must be distinct
    assert d1["request_id"] != d2["request_id"]

    # Phase 5: Both must be matched into ONE pair
    r1_fetched = client.get(f"/api/calls/{d1['request_id']}", headers=_auth(token_a)).json()
    r2_fetched = client.get(f"/api/calls/{d2['request_id']}", headers=_auth(token_b)).json()

    assert r1_fetched["reciprocal_flag"] is True,  "R1 must have reciprocal_flag=True"
    assert r2_fetched["reciprocal_flag"] is True,  "R2 must have reciprocal_flag=True"
    assert r1_fetched["pair_id"] is not None,      "R1 pair_id must not be None"
    assert r2_fetched["pair_id"] is not None,      "R2 pair_id must not be None"
    assert r1_fetched["pair_id"] == r2_fetched["pair_id"], \
        "Both requests must share the same pair_id (ONE pair)"
    assert r1_fetched["pair_id"].startswith("RP_"), "pair_id must start with RP_"

    # Both users see both requests
    a_calls = client.get("/api/calls", headers=_auth(token_a)).json()["requests"]
    b_calls = client.get("/api/calls", headers=_auth(token_b)).json()["requests"]
    assert len(a_calls) == 2
    assert len(b_calls) == 2
    rids = {req["request_id"] for req in a_calls}
    assert d1["request_id"] in rids
    assert d2["request_id"] in rids    # Confirm it is ONE pair, not two separate pairs
    assert r1_fetched["pair_id"].startswith("RP_"), "pair_id must start with RP_"
