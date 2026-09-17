"""
SmartDial Integration Smoke Test
=================================
Tests Day 1 + Day 2 features against a LIVE FastAPI server.

Usage:
    uvicorn app.main:app --host 127.0.0.1 --port 8000
    python tests/integration_smoke_test.py

Idempotent: safe to re-run; seed users are registered only if absent (409 = ok).
"""

import sys
import json
import urllib.request
import urllib.error
import os

BASE = "http://127.0.0.1:8000"
GREEN = ""
RED   = ""
RESET = ""
errors: list[str] = []


# ?? Shared helpers ????????????????????????????????????????????????????????????

def _request(method: str, path: str, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    headers: dict[str, str] = {}
    if data:
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(
        f"{BASE}{path}", data=data, headers=headers, method=method
    )
    try:
        resp = urllib.request.urlopen(req, timeout=10)
        return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


def post(path, body=None, token=None):
    return _request("POST", path, body, token)


def get(path, token=None):
    return _request("GET", path, token=token)


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  {GREEN}PASS{RESET}  {label}")
    else:
        print(f"  {RED}FAIL{RESET}  {label}  {detail}")
        errors.append(label)


def db_connect():
    """Return a SQLAlchemy engine pointed at the dev DB."""
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
    from app import config as cfg
    cfg.get_settings.cache_clear()
    from app.config import get_settings
    from sqlalchemy import create_engine
    return create_engine(get_settings().DATABASE_URL)


# ?? Day 1 ? Authentication & Users ????????????????????????????????????????????

def run_day1():
    print("\n?? Day 1: Health, Auth, Users ????????????????????????????????????")

    # Health
    s, b = get("/health")
    check("GET /health -> 200",        s == 200,          f"got {s}")
    check("health.status = ok",        b.get("status") == "ok")
    check("health.service = SmartDial API", b.get("service") == "SmartDial API")

    # Register (idempotent) — phones match what's in the DB after Phase 3 update
    seed_users = [
        {"name": "Arun Kumar",  "email": "arun@smartdial.dev",  "phone": "9600194757",    "password": "SecurePass1"},
        {"name": "Bala Murugan","email": "bala@smartdial.dev",  "phone": "+919629363934", "password": "SecurePass2"},
    ]
    for u in seed_users:
        s, _ = post("/api/auth/register", u)
        assert s in (201, 409), f"Unexpected register status {s}"

    # Duplicate rejection — use actual registered values
    s, _ = post("/api/auth/register", {**seed_users[0], "phone": "0000000000"})
    check("Duplicate email -> 409", s == 409, f"got {s}")
    s, _ = post("/api/auth/register", {**seed_users[0], "email": "other@x.dev"})
    check("Duplicate phone -> 409", s == 409, f"got {s}")

    # Login
    s, b = post("/api/auth/login", {"email": "arun@smartdial.dev", "password": "SecurePass1"})
    check("Login -> 200",           s == 200,          f"got {s}")
    token = b.get("access_token", "")
    check("access_token present",   bool(token))
    check("password_hash not in login response", "password_hash" not in str(b))

    # Wrong password
    s, _ = post("/api/auth/login", {"email": "arun@smartdial.dev", "password": "Wrong!"})
    check("Wrong password -> 401",  s == 401,          f"got {s}")

    # GET /api/users auth checks
    s, _ = get("/api/users")
    check("No token -> 403",        s == 403,          f"got {s}")
    s, _ = get("/api/users", token="bad.token.here")
    check("Bad token -> 401",       s == 401,          f"got {s}")
    s, b = get("/api/users", token=token)
    check("Valid token -> 200",     s == 200,          f"got {s}")
    names = [u["name"] for u in b.get("users", [])]
    check("Arun in list",           "Arun Kumar"   in names)
    check("Bala in list",           "Bala Murugan" in names)
    check("password_hash not in users response",
          not any("password_hash" in u for u in b.get("users", [])))

    # DB verification
    try:
        from sqlalchemy import text
        engine = db_connect()
        with engine.connect() as conn:
            rows = conn.execute(text("SELECT id, name, password_hash FROM users ORDER BY id")).fetchall()
            check("password_hash in DB (bcrypt)", all(r[2].startswith("$2b$") for r in rows))
            print(f"  ({len(rows)} users in DB)")
    except Exception as e:
        print(f"  DB check skipped: {e}")


# ?? Day 2 ? Communication Requests ???????????????????????????????????????????

def run_day2():
    print("\n?? Day 2: Communication Requests ?????????????????????????????????")

    # Use dedicated integration-test users (avoid touching seed user phone numbers)
    INT_A = {"name": "IntTestA", "email": "int_a@smartdial.dev", "phone": "8100000001", "password": "IntPass_A1"}
    INT_B = {"name": "IntTestB", "email": "int_b@smartdial.dev", "phone": "8100000002", "password": "IntPass_B2"}

    for u in (INT_A, INT_B):
        s, _ = post("/api/auth/register", u)
        assert s in (201, 409), f"Unexpected status {s}"

    s, b = post("/api/auth/login", {"email": INT_A["email"], "password": INT_A["password"]})
    check("Login IntTestA", s == 200, f"got {s}")
    tok_a = b.get("access_token", "")

    s, b = post("/api/auth/login", {"email": INT_B["email"], "password": INT_B["password"]})
    check("Login IntTestB", s == 200, f"got {s}")
    tok_b = b.get("access_token", "")

    # Resolve IDs
    s, b = get("/api/users", token=tok_a)
    users = b.get("users", [])
    a_id = next((u["id"] for u in users if u["email"] == INT_A["email"]), None)
    b_id = next((u["id"] for u in users if u["email"] == INT_B["email"]), None)
    check("Resolved A id", a_id is not None)
    check("Resolved B id", b_id is not None)

    # Create A -> B
    s, b = post("/api/calls/request", {"receiver_id": b_id}, token=tok_a)
    check("POST /api/calls/request -> 201", s == 201,            f"got {s}: {b}")
    rid = b.get("request_id", "")
    check("request_id starts with CR_",     rid.startswith("CR_"), f"got {rid!r}")
    check("status = PENDING",               b.get("status") == "PENDING")
    check("reciprocal_flag = False",        b.get("reciprocal_flag") is False)
    check("pair_id = None",                 b.get("pair_id") is None)
    check("caller.id = A",                  b.get("caller", {}).get("id") == a_id)
    check("receiver.id = B",               b.get("receiver", {}).get("id") == b_id)
    check("expires_at > request_time",
          b.get("expires_at", "") > b.get("request_time", ""))

    # DB check
    try:
        from sqlalchemy import text
        engine = db_connect()
        with engine.connect() as conn:
            row = conn.execute(text(
                "SELECT caller_id, receiver_id, status, reciprocal_flag, pair_id "
                "FROM communication_requests WHERE request_id = :rid"
            ), {"rid": rid}).fetchone()
            check("Row in DB",               row is not None)
            if row:
                check("DB caller_id = A",    row[0] == a_id,  f"got {row[0]}")
                check("DB receiver_id = B",  row[1] == b_id,  f"got {row[1]}")
                check("DB status = PENDING", row[2] == "PENDING")
                check("DB reciprocal_flag",  row[3] is False)
                check("DB pair_id = None",   row[4] is None)
                print(f"  DB: {rid}  {row[0]}->{row[1]}  {row[2]}")
    except Exception as e:
        print(f"  DB check skipped: {e}")

    # Retrieve
    s, _ = get(f"/api/calls/{rid}", token=tok_a)
    check("Caller fetches request -> 200",   s == 200, f"got {s}")
    s, _ = get(f"/api/calls/{rid}", token=tok_b)
    check("Receiver fetches request -> 200", s == 200, f"got {s}")

    # My requests
    s, b = get("/api/calls", token=tok_a)
    check("GET /api/calls -> 200",           s == 200, f"got {s}")
    check("A sees own request",
          any(r["request_id"] == rid for r in b.get("requests", [])))

    # B -> A (independent, no matching)
    s, b2 = post("/api/calls/request", {"receiver_id": a_id}, token=tok_b)
    check("B -> A POST -> 201",              s == 201, f"got {s}")
    rid2 = b2.get("request_id", "")
    check("R2 different request_id",         rid2 != rid)
    # Phase 5: B->A matches A->B within the window -> reciprocal pair created
    check("R2 reciprocal_flag = True (Phase 5)",
          b2.get("reciprocal_flag") is True, f"got {b2.get('reciprocal_flag')}")
    check("R2 pair_id starts RP_ (Phase 5)",
          str(b2.get("pair_id", "")).startswith("RP_"), f"got {b2.get('pair_id')}")

    # R1 is also updated with the pair
    s, r1 = get(f"/api/calls/{rid}", token=tok_a)
    check("R1 reciprocal_flag = True (Phase 5)", r1.get("reciprocal_flag") is True)
    check("R1 pair_id matches R2",               r1.get("pair_id") == b2.get("pair_id"))

    # Cancel R1
    s, b = post(f"/api/calls/{rid}/cancel", token=tok_a)
    check("Cancel R1 -> 200",                s == 200, f"got {s}")
    check("R1 status = CANCELLED",           b.get("status") == "CANCELLED")

    # DB: R1 cancelled
    try:
        with engine.connect() as conn:
            row = conn.execute(text(
                "SELECT status FROM communication_requests WHERE request_id = :rid"
            ), {"rid": rid}).fetchone()
            check("DB R1 = CANCELLED", row and row[0] == "CANCELLED")
            print(f"  DB after cancel: {rid}  {row[0] if row else 'N/A'}")
    except Exception as e:
        print(f"  DB cancel check skipped: {e}")

    # Double cancel
    s, _ = post(f"/api/calls/{rid}/cancel", token=tok_a)
    check("Double-cancel -> 409",           s == 409, f"got {s}")


# ?? Phase 5 - Reciprocal Detection ?????????????????????????????????????????????

def run_phase5():
    print("\n-- Phase 5: Reciprocal Detection --------------------------------------")

    # Use fresh integration-test users for Phase 5
    USER_P = {"name": "P5UserA", "email": "p5a@smartdial.dev", "phone": "7200000001", "password": "P5Pass_A1"}
    USER_Q = {"name": "P5UserB", "email": "p5b@smartdial.dev", "phone": "7200000002", "password": "P5Pass_B2"}

    for u in (USER_P, USER_Q):
        s, _ = post("/api/auth/register", u)
        assert s in (201, 409), f"Register failed: {s}"

    s, b = post("/api/auth/login", {"email": USER_P["email"], "password": USER_P["password"]})
    check("Login P5UserA", s == 200, f"got {s}")
    tok_a = b.get("access_token", "")

    s, b = post("/api/auth/login", {"email": USER_Q["email"], "password": USER_Q["password"]})
    check("Login P5UserB", s == 200, f"got {s}")
    tok_b = b.get("access_token", "")

    # Resolve IDs
    s, b = get("/api/users", token=tok_a)
    users = b.get("users", [])
    a_id = next((u["id"] for u in users if u["email"] == USER_P["email"]), None)
    b_id = next((u["id"] for u in users if u["email"] == USER_Q["email"]), None)
    check("Resolved P5UserA id", a_id is not None)
    check("Resolved P5UserB id", b_id is not None)

    # Create A -> B
    s, d1 = post("/api/calls/request", {"receiver_id": b_id}, token=tok_a)
    check("A->B request created", s == 201, f"got {s}")
    rid1 = d1.get("request_id", "")
    # A->B alone: no match yet
    check("A->B: reciprocal_flag=False (no reverse yet)", d1.get("reciprocal_flag") is False)
    check("A->B: pair_id=None (no reverse yet)", d1.get("pair_id") is None)

    # Create B -> A (reciprocal, within window)
    s, d2 = post("/api/calls/request", {"receiver_id": a_id}, token=tok_b)
    check("B->A request created", s == 201, f"got {s}")
    rid2 = d2.get("request_id", "")
    check("B->A: reciprocal_flag=True", d2.get("reciprocal_flag") is True,
          f"got {d2.get('reciprocal_flag')}")
    check("B->A: pair_id starts with RP_",
          str(d2.get("pair_id", "")).startswith("RP_"),
          f"got {d2.get('pair_id')}")
    pair_id = d2.get("pair_id", "")

    # Verify A's request is also updated
    s, r1check = get(f"/api/calls/{rid1}", token=tok_a)
    check("A->B: reciprocal_flag now True", r1check.get("reciprocal_flag") is True)
    check("A->B: pair_id matches", r1check.get("pair_id") == pair_id)

    # Consistency: both have the same pair_id
    check("Same pair_id on both requests",
          r1check.get("pair_id") == d2.get("pair_id"))

    # GET /api/reciprocal-pairs/{pair_id}
    s, pr = get(f"/api/reciprocal-pairs/{pair_id}", token=tok_a)
    check("GET /api/reciprocal-pairs/{pair_id} -> 200", s == 200, f"got {s}")
    check("Pair status = DETECTED", pr.get("status") == "DETECTED")
    check("time_difference_ms >= 0", pr.get("time_difference_ms", -1) >= 0)

    # Third user cannot access
    s, _ = get("/api/auth/register", token=tok_a)  # just reuse existing tok from Day 1
    # Login as Arun (seed user — not P5UserA or P5UserB)
    s2, b2 = post("/api/auth/login", {"email": "arun@smartdial.dev", "password": "SecurePass1"})
    if s2 == 200:
        tok_third = b2.get("access_token", "")
        s3, _ = get(f"/api/reciprocal-pairs/{pair_id}", token=tok_third)
        check("Third user cannot access pair -> 403", s3 == 403, f"got {s3}")

    # GET /api/reciprocal-pairs (my pairs)
    s, my_pairs = get("/api/reciprocal-pairs", token=tok_a)
    check("GET /api/reciprocal-pairs -> 200", s == 200, f"got {s}")
    check("A sees at least 1 pair", my_pairs.get("total", 0) >= 1)

    # Verify in PostgreSQL
    try:
        from sqlalchemy import text as sqla_text
        engine = db_connect()
        with engine.connect() as conn:
            # Check reciprocal_pairs table
            row = conn.execute(sqla_text(
                "SELECT pair_id, time_difference_ms, status "
                "FROM reciprocal_pairs WHERE pair_id=:pid"
            ), {"pid": pair_id}).fetchone()
            check("Pair row in DB", row is not None)
            if row:
                check("DB status=DETECTED", row[2] == "DETECTED")
                check("DB time_difference_ms >= 0", row[1] >= 0)
                print(f"  DB pair: {row[0]}  diff={row[1]}ms  status={row[2]}")

            # Both requests have correct pair_id in DB
            rows = conn.execute(sqla_text(
                "SELECT request_id, reciprocal_flag, pair_id "
                "FROM communication_requests "
                "WHERE request_id IN (:r1, :r2)"
            ), {"r1": rid1, "r2": rid2}).fetchall()
            for r in rows:
                check(f"DB {r[0]}: reciprocal_flag=True", r[1] is True)
                check(f"DB {r[0]}: pair_id={pair_id}", r[2] == pair_id)
    except Exception as e:
        print(f"  DB check skipped: {e}")


# ?? Main ??????????????????????????????????????????????????????????????????????

if __name__ == "__main__":
    print("\n=== SmartDial Integration Smoke Test ===")
    print(f"Target: {BASE}")

    run_day1()
    run_day2()
    run_phase5()

    print()
    total = len(errors)
    if total:
        print(f"=== {total} check(s) FAILED: {errors} ===")
        sys.exit(1)
    else:
        print("=== All checks PASSED ===")
        sys.exit(0)

    print()
    total = len(errors)
    if total:
        print(f"{RED}=== {total} check(s) FAILED: {errors} ==={RESET}")
        sys.exit(1)
    else:
        print(f"{GREEN}=== All checks PASSED ==={RESET}")
        sys.exit(0)
