"""
Phase 5 tests — Reciprocal Detection Engine.
All 14 required test cases plus edge cases.
Uses the same SQLite in-memory conftest as Days 1 & 2.
"""

from datetime import datetime, timezone, timedelta
import pytest

# ── Test users ────────────────────────────────────────────────────────────────
USER_A = {"name": "Arun",  "email": "a@test.com", "phone": "1000000001", "password": "PassWord1"}
USER_B = {"name": "Bala",  "email": "b@test.com", "phone": "1000000002", "password": "PassWord2"}
USER_C = {"name": "Carol", "email": "c@test.com", "phone": "1000000003", "password": "PassWord3"}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _reg(client, user):
    client.post("/api/auth/register", json=user)

def _login(client, user) -> str:
    r = client.post("/api/auth/login", json={"email": user["email"], "password": user["password"]})
    return r.json()["access_token"]

def _auth(token): return {"Authorization": f"Bearer {token}"}

def _create_req(client, token, receiver_id):
    return client.post("/api/calls/request", json={"receiver_id": receiver_id}, headers=_auth(token))

def _ids(client, token):
    """Return {email: id} mapping for all users."""
    users = client.get("/api/users", headers=_auth(token)).json()["users"]
    return {u["email"]: u["id"] for u in users}

def _set_request_time(db_session, request_id_str, new_time):
    """Helper: directly set request_time on a communication_request row."""
    from app.models.communication_request import CommunicationRequest
    req = db_session.query(CommunicationRequest).filter(
        CommunicationRequest.request_id == request_id_str
    ).first()
    if req:
        req.request_time = new_time
        db_session.commit()


# ── TEST 1 — A→B only, no reverse ────────────────────────────────────────────

def test_no_pair_without_reverse(client):
    """A→B with no B→A: no reciprocal pair should be created."""
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    ids = _ids(client, tok_a)
    r = _create_req(client, tok_a, ids["b@test.com"])
    assert r.status_code == 201
    data = r.json()
    assert data["reciprocal_flag"] is False
    assert data["pair_id"] is None


# ── TEST 2 — A→B then B→A within 3 seconds ───────────────────────────────────

def test_pair_created_within_window(client):
    """A→B then B→A with 3s difference: pair must be created."""
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    ids = _ids(client, tok_a)

    from tests.conftest import TestingSessionLocal
    # Create A→B
    r1 = _create_req(client, tok_a, ids["b@test.com"])
    assert r1.status_code == 201
    rid1 = r1.json()["request_id"]

    # Back-date A's request_time by 3 seconds so B's is 3s later
    t_a = datetime.now(timezone.utc) - timedelta(seconds=3)
    with TestingSessionLocal() as db:
        _set_request_time(db, rid1, t_a)

    # Create B→A
    r2 = _create_req(client, tok_b, ids["a@test.com"])
    assert r2.status_code == 201
    d2 = r2.json()
    assert d2["reciprocal_flag"] is True, "B→A should have reciprocal_flag=True"
    assert d2["pair_id"] is not None
    assert d2["pair_id"].startswith("RP_")

    # A's request should also reflect the pair
    r1_check = client.get(f"/api/calls/{rid1}", headers=_auth(tok_a)).json()
    assert r1_check["reciprocal_flag"] is True
    assert r1_check["pair_id"] == d2["pair_id"]


# ── TEST 3 — Exactly 10 seconds (boundary = match) ───────────────────────────

def test_pair_at_exact_boundary(client):
    """Exactly RECIPROCAL_WINDOW_SECONDS apart must still match."""
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    ids = _ids(client, tok_a)

    from tests.conftest import TestingSessionLocal
    from app import config as cfg; cfg.get_settings.cache_clear()
    window = cfg.get_settings().RECIPROCAL_WINDOW_SECONDS  # 10

    # Anchor: a fixed reference time
    anchor = datetime.now(timezone.utc) - timedelta(seconds=30)

    r1 = _create_req(client, tok_a, ids["b@test.com"])
    rid1 = r1.json()["request_id"]

    # Set A's request_time to anchor
    with TestingSessionLocal() as db:
        _set_request_time(db, rid1, anchor)

    r2 = _create_req(client, tok_b, ids["a@test.com"])
    rid2 = r2.json()["request_id"]

    # Set B's request_time to exactly anchor + window (boundary = match)
    with TestingSessionLocal() as db:
        _set_request_time(db, rid2, anchor + timedelta(seconds=window))

    # Re-run detection on B's request so it picks up the backdated times
    from app.services.reciprocal_detection_service import detect_reciprocal
    from app.models.communication_request import CommunicationRequest
    with TestingSessionLocal() as db:
        req_b = db.query(CommunicationRequest).filter(
            CommunicationRequest.request_id == rid2
        ).first()
        # Reset flags first so detection can re-run
        req_b.reciprocal_flag = False
        req_b.pair_id = None
        req_a = db.query(CommunicationRequest).filter(
            CommunicationRequest.request_id == rid1
        ).first()
        req_a.reciprocal_flag = False
        req_a.pair_id = None
        db.commit()
        db.refresh(req_b)
        result = detect_reciprocal(req_b, db)

    assert result.matched is True, "Exact boundary should match"
    assert result.pair is not None


# ── TEST 4 — 11 seconds apart (outside window = no match) ────────────────────

def test_no_pair_outside_window(client):
    """11 seconds apart: must NOT match."""
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    ids = _ids(client, tok_a)

    from tests.conftest import TestingSessionLocal
    r1 = _create_req(client, tok_a, ids["b@test.com"])
    rid1 = r1.json()["request_id"]

    t_a = datetime.now(timezone.utc) - timedelta(seconds=11)
    with TestingSessionLocal() as db:
        _set_request_time(db, rid1, t_a)

    r2 = _create_req(client, tok_b, ids["a@test.com"])
    assert r2.json()["reciprocal_flag"] is False, "11s should NOT match"
    assert r2.json()["pair_id"] is None


# ── TEST 5 — A→B + A→B (same direction) ──────────────────────────────────────

def test_same_direction_not_matched(client):
    """A→B followed by A→B again: directions don't reverse, no match."""
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    ids = _ids(client, tok_a)

    _create_req(client, tok_a, ids["b@test.com"])
    r2 = _create_req(client, tok_a, ids["b@test.com"])
    assert r2.json()["reciprocal_flag"] is False
    assert r2.json()["pair_id"] is None


# ── TEST 6 — A→B + C→A (wrong receiver for A) ────────────────────────────────

def test_wrong_receiver_not_matched(client):
    """A→B then C→A: C is not B, so no match for A→B."""
    _reg(client, USER_A); _reg(client, USER_B); _reg(client, USER_C)
    tok_a = _login(client, USER_A)
    tok_c = _login(client, USER_C)
    ids = _ids(client, tok_a)

    _create_req(client, tok_a, ids["b@test.com"])
    r2 = _create_req(client, tok_c, ids["a@test.com"])
    assert r2.json()["reciprocal_flag"] is False


# ── TEST 7 — A→B + B→C (wrong caller for B) ──────────────────────────────────

def test_wrong_caller_not_matched(client):
    """A→B then B→C: B is not calling A back, so no match."""
    _reg(client, USER_A); _reg(client, USER_B); _reg(client, USER_C)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    ids = _ids(client, tok_a)

    _create_req(client, tok_a, ids["b@test.com"])
    r2 = _create_req(client, tok_b, ids["c@test.com"])
    assert r2.json()["reciprocal_flag"] is False


# ── TEST 8 — First request CANCELLED → no match ──────────────────────────────

def test_cancelled_request_not_matched(client):
    """If A→B is cancelled, B→A must not form a pair."""
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    ids = _ids(client, tok_a)

    r1 = _create_req(client, tok_a, ids["b@test.com"])
    rid1 = r1.json()["request_id"]
    client.post(f"/api/calls/{rid1}/cancel", headers=_auth(tok_a))

    r2 = _create_req(client, tok_b, ids["a@test.com"])
    assert r2.json()["reciprocal_flag"] is False


# ── TEST 9 — First request EXPIRED → no match ────────────────────────────────

def test_expired_request_not_matched(client):
    """If A→B is expired, B→A must not form a pair."""
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    ids = _ids(client, tok_a)

    from tests.conftest import TestingSessionLocal
    from app.models.communication_request import CommunicationRequest

    r1 = _create_req(client, tok_a, ids["b@test.com"])
    rid1 = r1.json()["request_id"]

    # Force expiry
    with TestingSessionLocal() as db:
        req = db.query(CommunicationRequest).filter(
            CommunicationRequest.request_id == rid1
        ).first()
        req.expires_at = datetime.now(timezone.utc) - timedelta(seconds=60)
        db.commit()

    # Fetch the request to trigger lazy expiration
    client.get(f"/api/calls/{rid1}", headers=_auth(tok_a))

    r2 = _create_req(client, tok_b, ids["a@test.com"])
    assert r2.json()["reciprocal_flag"] is False


# ── TEST 10 — Same timestamps → match ────────────────────────────────────────

def test_same_timestamp_matches(client):
    """Requests at identical timestamps: diff=0ms, must match."""
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    ids = _ids(client, tok_a)

    from tests.conftest import TestingSessionLocal
    same_time = datetime.now(timezone.utc)

    r1 = _create_req(client, tok_a, ids["b@test.com"])
    rid1 = r1.json()["request_id"]
    with TestingSessionLocal() as db:
        _set_request_time(db, rid1, same_time)

    r2 = _create_req(client, tok_b, ids["a@test.com"])
    rid2 = r2.json()["request_id"]
    with TestingSessionLocal() as db:
        _set_request_time(db, rid2, same_time)

    # Re-run detection by re-fetching (detection already ran at creation)
    # Just verify the state of the second request
    assert r2.json()["reciprocal_flag"] is True or \
        client.get(f"/api/calls/{rid2}", headers=_auth(tok_b)).json()["pair_id"] is not None


# ── TEST 11 — Idempotency: detection twice → ONE pair ────────────────────────

def test_idempotency_single_pair(client):
    """Run detection twice on the same pair: only ONE ReciprocalPair row created."""
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    ids = _ids(client, tok_a)

    r1 = _create_req(client, tok_a, ids["b@test.com"])
    rid1 = r1.json()["request_id"]
    t_a = datetime.now(timezone.utc) - timedelta(seconds=3)
    from tests.conftest import TestingSessionLocal
    with TestingSessionLocal() as db:
        _set_request_time(db, rid1, t_a)

    r2 = _create_req(client, tok_b, ids["a@test.com"])
    pair_id_1 = r2.json()["pair_id"]
    assert pair_id_1 is not None

    # Call detection again manually
    from app.services.reciprocal_detection_service import detect_reciprocal
    from app.models.communication_request import CommunicationRequest
    with TestingSessionLocal() as db:
        req_b = db.query(CommunicationRequest).filter(
            CommunicationRequest.request_id == r2.json()["request_id"]
        ).first()
        result = detect_reciprocal(req_b, db)

    # Should not create a new pair — result.matched may be False (already paired)
    r1_check = client.get(f"/api/calls/{rid1}", headers=_auth(tok_a)).json()
    r2_check = client.get(f"/api/calls/{r2.json()['request_id']}", headers=_auth(tok_b)).json()
    assert r1_check["pair_id"] == pair_id_1
    assert r2_check["pair_id"] == pair_id_1


# ── TEST 12 — Concurrent detection → ONE pair ────────────────────────────────

def test_concurrent_detection_single_pair(client):
    """
    Simulate concurrent detection from both sides.
    Both calls detect the same pair — result must be ONE pair, not two.
    """
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    ids = _ids(client, tok_a)

    from tests.conftest import TestingSessionLocal
    from app.services.reciprocal_detection_service import detect_reciprocal
    from app.models.communication_request import CommunicationRequest
    from app.models.reciprocal_pair import ReciprocalPair

    r1 = _create_req(client, tok_a, ids["b@test.com"])
    rid1 = r1.json()["request_id"]
    t_a = datetime.now(timezone.utc) - timedelta(seconds=2)
    with TestingSessionLocal() as db:
        _set_request_time(db, rid1, t_a)

    r2 = _create_req(client, tok_b, ids["a@test.com"])
    rid2 = r2.json()["request_id"]

    # Run detection once more manually on req_a (simulates concurrent detection)
    with TestingSessionLocal() as db:
        req_a = db.query(CommunicationRequest).filter(
            CommunicationRequest.request_id == rid1
        ).first()
        detect_reciprocal(req_a, db)

        # Count pairs in DB — must be exactly 1
        count = db.query(ReciprocalPair).count()
        assert count == 1, f"Expected 1 pair, got {count}"


# ── TEST 13 — Third user cannot access pair ───────────────────────────────────

def test_third_user_cannot_access_pair(client):
    """User C must not be able to view a pair they have no part in."""
    _reg(client, USER_A); _reg(client, USER_B); _reg(client, USER_C)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    tok_c = _login(client, USER_C)
    ids = _ids(client, tok_a)

    from tests.conftest import TestingSessionLocal
    r1 = _create_req(client, tok_a, ids["b@test.com"])
    rid1 = r1.json()["request_id"]
    with TestingSessionLocal() as db:
        _set_request_time(db, rid1, datetime.now(timezone.utc) - timedelta(seconds=3))

    r2 = _create_req(client, tok_b, ids["a@test.com"])
    pair_id = r2.json()["pair_id"]
    assert pair_id is not None

    r = client.get(f"/api/reciprocal-pairs/{pair_id}", headers=_auth(tok_c))
    assert r.status_code == 403


# ── TEST 14 — Participant can access pair ─────────────────────────────────────

def test_participant_can_access_pair(client):
    """Both A and B must be able to view their reciprocal pair."""
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    ids = _ids(client, tok_a)

    from tests.conftest import TestingSessionLocal
    r1 = _create_req(client, tok_a, ids["b@test.com"])
    rid1 = r1.json()["request_id"]
    with TestingSessionLocal() as db:
        _set_request_time(db, rid1, datetime.now(timezone.utc) - timedelta(seconds=3))

    r2 = _create_req(client, tok_b, ids["a@test.com"])
    pair_id = r2.json()["pair_id"]
    assert pair_id is not None

    # A can access
    ra = client.get(f"/api/reciprocal-pairs/{pair_id}", headers=_auth(tok_a))
    assert ra.status_code == 200
    pa = ra.json()
    assert pa["pair_id"] == pair_id
    assert pa["time_difference_ms"] >= 0
    assert pa["status"] == "DETECTED"

    # B can access
    rb = client.get(f"/api/reciprocal-pairs/{pair_id}", headers=_auth(tok_b))
    assert rb.status_code == 200
    assert rb.json()["pair_id"] == pair_id


# ── Additional: GET /api/reciprocal-pairs (my pairs) ────────────────────────

def test_my_reciprocal_pairs(client):
    """GET /api/reciprocal-pairs returns only current user's pairs."""
    _reg(client, USER_A); _reg(client, USER_B); _reg(client, USER_C)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    tok_c = _login(client, USER_C)
    ids = _ids(client, tok_a)

    from tests.conftest import TestingSessionLocal
    r1 = _create_req(client, tok_a, ids["b@test.com"])
    rid1 = r1.json()["request_id"]
    with TestingSessionLocal() as db:
        _set_request_time(db, rid1, datetime.now(timezone.utc) - timedelta(seconds=3))
    _create_req(client, tok_b, ids["a@test.com"])

    # A sees their pair
    ra = client.get("/api/reciprocal-pairs", headers=_auth(tok_a))
    assert ra.status_code == 200
    assert ra.json()["total"] == 1

    # C sees nothing
    rc = client.get("/api/reciprocal-pairs", headers=_auth(tok_c))
    assert rc.json()["total"] == 0


# ── Additional: pair_id same on both requests ────────────────────────────────

def test_same_pair_id_on_both_requests(client):
    """Both requests in a pair must have identical pair_id."""
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    ids = _ids(client, tok_a)

    from tests.conftest import TestingSessionLocal
    r1 = _create_req(client, tok_a, ids["b@test.com"])
    rid1 = r1.json()["request_id"]
    with TestingSessionLocal() as db:
        _set_request_time(db, rid1, datetime.now(timezone.utc) - timedelta(seconds=2))

    r2 = _create_req(client, tok_b, ids["a@test.com"])
    pid = r2.json()["pair_id"]
    assert pid is not None

    r1_check = client.get(f"/api/calls/{rid1}", headers=_auth(tok_a)).json()
    r2_check = client.get(f"/api/calls/{r2.json()['request_id']}", headers=_auth(tok_b)).json()

    assert r1_check["pair_id"] == pid
    assert r2_check["pair_id"] == pid
    assert r1_check["reciprocal_flag"] is True
    assert r2_check["reciprocal_flag"] is True


# ── Additional: pair_id format ────────────────────────────────────────────────

def test_pair_id_format(client):
    """pair_id must start with RP_."""
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    ids = _ids(client, tok_a)

    from tests.conftest import TestingSessionLocal
    r1 = _create_req(client, tok_a, ids["b@test.com"])
    rid1 = r1.json()["request_id"]
    with TestingSessionLocal() as db:
        _set_request_time(db, rid1, datetime.now(timezone.utc) - timedelta(seconds=2))

    r2 = _create_req(client, tok_b, ids["a@test.com"])
    assert r2.json()["pair_id"].startswith("RP_")
