"""
Phase 6 tests — Decision Engine & Conflict Resolution.
Tests all priority tiers, authorization, idempotency, and user responses.
"""

import pytest
from app.models.user import ReciprocalCallPreference

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
    users = client.get("/api/users", headers=_auth(token)).json()["users"]
    return {u["email"]: u["id"] for u in users}

def _setup_pair(client):
    """Register A & B, place reciprocal calls, return (pair_id, tok_a, tok_b)."""
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    ids = _ids(client, tok_a)

    r_a = _create_req(client, tok_a, ids["b@test.com"])
    r_b = _create_req(client, tok_b, ids["a@test.com"])
    assert r_b.status_code == 201
    pair_id = r_b.json()["pair_id"]
    assert pair_id is not None
    return pair_id, tok_a, tok_b

def _set_user_pref(db_session, user_email: str, pref: ReciprocalCallPreference):
    from app.models.user import User
    u = db_session.query(User).filter(User.email == user_email).first()
    if u:
        u.reciprocal_call_preference = pref
        db_session.commit()


# ── Priority 1: BLOCK_RECIPROCAL ──────────────────────────────────────────────

def test_priority_1_block_reciprocal(client):
    """If either user prefers BLOCK_RECIPROCAL -> decision is BLOCK."""
    from app.database import get_db
    pair_id, tok_a, _ = _setup_pair(client)

    db = next(client.app.dependency_overrides[get_db]())
    _set_user_pref(db, "a@test.com", ReciprocalCallPreference.BLOCK_RECIPROCAL)

    r = client.post(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_a))
    assert r.status_code == 200
    data = r.json()
    assert data["decision_type"] == "BLOCK"
    assert data["reason_code"] == "USER_PREFERENCE"
    assert data["selected_request_id"] is None


# ── Priority 2: ALWAYS_ALLOW ──────────────────────────────────────────────────

def test_priority_2_always_allow(client):
    """If user prefers ALWAYS_ALLOW -> decision is ALLOW_A_TO_B (first request)."""
    from app.database import get_db
    pair_id, tok_a, _ = _setup_pair(client)

    db = next(client.app.dependency_overrides[get_db]())
    _set_user_pref(db, "b@test.com", ReciprocalCallPreference.ALWAYS_ALLOW)

    r = client.post(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_a))
    assert r.status_code == 200
    data = r.json()
    assert data["decision_type"] == "ALLOW_A_TO_B"
    assert data["reason_code"] == "USER_PREFERENCE"
    assert data["selected_request_id"] is not None


# ── Priority 3: User A PREFER_OUTGOING ────────────────────────────────────────

def test_priority_3_prefer_outgoing_user_a(client):
    """User A prefers outgoing -> ALLOW_A_TO_B."""
    from app.database import get_db
    pair_id, tok_a, _ = _setup_pair(client)

    db = next(client.app.dependency_overrides[get_db]())
    _set_user_pref(db, "a@test.com", ReciprocalCallPreference.PREFER_OUTGOING)

    r = client.post(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_a))
    assert r.status_code == 200
    data = r.json()
    assert data["decision_type"] == "ALLOW_A_TO_B"


# ── Priority 4: User B PREFER_OUTGOING ────────────────────────────────────────

def test_priority_4_prefer_outgoing_user_b(client):
    """User B prefers outgoing -> ALLOW_B_TO_A."""
    from app.database import get_db
    pair_id, tok_a, _ = _setup_pair(client)

    db = next(client.app.dependency_overrides[get_db]())
    _set_user_pref(db, "b@test.com", ReciprocalCallPreference.PREFER_OUTGOING)

    r = client.post(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_a))
    assert r.status_code == 200
    data = r.json()
    assert data["decision_type"] == "ALLOW_B_TO_A"


# ── Priority 5: User A PREFER_INCOMING ────────────────────────────────────────

def test_priority_5_prefer_incoming_user_a(client):
    """User A prefers incoming -> ALLOW_B_TO_A."""
    from app.database import get_db
    pair_id, tok_a, _ = _setup_pair(client)

    db = next(client.app.dependency_overrides[get_db]())
    _set_user_pref(db, "a@test.com", ReciprocalCallPreference.PREFER_INCOMING)

    r = client.post(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_a))
    assert r.status_code == 200
    data = r.json()
    assert data["decision_type"] == "ALLOW_B_TO_A"


# ── Priority 6: User B PREFER_INCOMING ────────────────────────────────────────

def test_priority_6_prefer_incoming_user_b(client):
    """User B prefers incoming -> ALLOW_A_TO_B."""
    from app.database import get_db
    pair_id, tok_a, _ = _setup_pair(client)

    db = next(client.app.dependency_overrides[get_db]())
    _set_user_pref(db, "b@test.com", ReciprocalCallPreference.PREFER_INCOMING)

    r = client.post(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_a))
    assert r.status_code == 200
    data = r.json()
    assert data["decision_type"] == "ALLOW_A_TO_B"


# ── Priority 7: Default Policy ────────────────────────────────────────────────

def test_priority_7_default_ask_user(client):
    """Default preferences -> ASK_USER / DEFAULT_POLICY."""
    pair_id, tok_a, _ = _setup_pair(client)

    r = client.post(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_a))
    assert r.status_code == 200
    data = r.json()
    assert data["decision_type"] == "ASK_USER"
    assert data["reason_code"] == "DEFAULT_POLICY"
    assert data["selected_request_id"] is None


# ── Idempotency & Retrieval ───────────────────────────────────────────────────

def test_decision_idempotency(client):
    """Subsequent POST /decision calls return the exact same decision."""
    pair_id, tok_a, tok_b = _setup_pair(client)

    r1 = client.post(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_a))
    r2 = client.post(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_b))
    assert r1.status_code == 200
    assert r2.status_code == 200
    assert r1.json()["decision_id"] == r2.json()["decision_id"]


def test_fetch_existing_decision(client):
    """GET /decision returns the created decision."""
    pair_id, tok_a, tok_b = _setup_pair(client)

    client.post(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_a))
    r = client.get(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_b))
    assert r.status_code == 200
    assert r.json()["pair_id"] == pair_id


def test_fetch_nonexistent_decision_404(client):
    """GET /decision before evaluation returns 404."""
    pair_id, tok_a, _ = _setup_pair(client)

    r = client.get(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_a))
    assert r.status_code == 404


# ── Authorization ─────────────────────────────────────────────────────────────

def test_third_user_cannot_access_decision(client):
    """Non-participant receives 403 Forbidden."""
    pair_id, _, _ = _setup_pair(client)
    _reg(client, USER_C)
    tok_c = _login(client, USER_C)

    r = client.post(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_c))
    assert r.status_code == 403

    r_get = client.get(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_c))
    assert r_get.status_code == 403


# ── User Response ─────────────────────────────────────────────────────────────

def test_user_respond_endpoint(client):
    """User responds to ASK_USER with ALLOW_A_TO_B -> resolves decision."""
    pair_id, tok_a, _ = _setup_pair(client)

    # Initial decision is ASK_USER
    client.post(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_a))

    # Respond
    r = client.post(
        f"/api/reciprocal-pairs/{pair_id}/decision/respond",
        json={"action": "ALLOW_A_TO_B"},
        headers=_auth(tok_a),
    )
    assert r.status_code == 200
    data = r.json()
    assert data["decision_type"] == "ALLOW_A_TO_B"
    assert data["reason_code"] == "EXPLICIT_USER_CHOICE"
    assert data["status"] == "RESOLVED"
