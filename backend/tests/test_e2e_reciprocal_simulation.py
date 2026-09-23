"""
Phase 11 — Dual-Client Reciprocal Call End-to-End Simulation Harness.

Simulates two real concurrent users (User A and User B) connecting over WebSockets
and making simultaneous cellular intent calls within the reciprocal window.
Validates the full stack:
  Intent A + Intent B → Pair Detection → Decision Resolution → Real-Time Push.
"""

import json
import pytest
from starlette.testclient import TestClient

from app.main import app


def _create_user(client: TestClient, name: str, email: str, phone: str, pref: str = "ASK") -> dict:
    pwd = "TestPassword123!"
    reg_resp = client.post("/api/auth/register", json={
        "name": name,
        "email": email,
        "phone": phone,
        "password": pwd,
    })
    assert reg_resp.status_code == 201, reg_resp.text
    user_id = reg_resp.json()["id"]

    login_resp = client.post("/api/auth/login", json={
        "email": email,
        "password": pwd,
    })
    assert login_resp.status_code == 200, login_resp.text
    token = login_resp.json()["access_token"]

    if pref != "ASK":
        client.patch(
            "/api/users/me/preferences",
            json={"reciprocal_call_preference": pref},
            headers={"Authorization": f"Bearer {token}"},
        )

    return {
        "id": user_id,
        "name": name,
        "email": email,
        "phone": phone,
        "token": token,
        "headers": {"Authorization": f"Bearer {token}"},
    }


def test_e2e_reciprocal_simulation_bidirectional():
    """
    Simulate full reciprocal loop between User A (PREFER_OUTGOING) and User B (ASK).
    Verifies that:
    1. Both users receive RECIPROCAL_DETECTED over WebSockets.
    2. Decision engine resolves to ALLOW_A_TO_B.
    3. User A receives PROCEED; User B receives STANDBY.
    4. History endpoint records telemetry.
    """
    with TestClient(app) as client:
        # 1. Setup users: Alice prefers outgoing; Bob is default
        user_a = _create_user(client, "Alice", "alice_e2e@example.com", "14155550001", pref="PREFER_OUTGOING")
        user_b = _create_user(client, "Bob", "bob_e2e@example.com", "14155550002", pref="ASK")

        # 2. Connect both to real-time WebSockets
        with client.websocket_connect(f"/ws/calls?token={user_a['token']}") as ws_a:
            with client.websocket_connect(f"/ws/calls?token={user_b['token']}") as ws_b:

                # Consume initial connection confirmation
                init_a = json.loads(ws_a.receive_text())
                init_b = json.loads(ws_b.receive_text())
                assert init_a["event"] == "CONNECTION_ESTABLISHED"
                assert init_b["event"] == "CONNECTION_ESTABLISHED"

                # 3. Alice initiates call to Bob
                req_a_resp = client.post(
                    "/api/calls/request",
                    json={"receiver_id": user_b["id"]},
                    headers=user_a["headers"],
                )
                assert req_a_resp.status_code == 201

                # 4. Bob initiates reciprocal call to Alice (within 10s window)
                req_b_resp = client.post(
                    "/api/calls/request",
                    json={"receiver_id": user_a["id"]},
                    headers=user_b["headers"],
                )
                assert req_b_resp.status_code == 201

                # 5. Check real-time RECIPROCAL_DETECTED events
                evt_a_reciprocal = json.loads(ws_a.receive_text())
                evt_b_reciprocal = json.loads(ws_b.receive_text())
                assert evt_a_reciprocal["event"] == "RECIPROCAL_DETECTED"
                assert evt_b_reciprocal["event"] == "RECIPROCAL_DETECTED"
                assert evt_a_reciprocal["pair_id"] == evt_b_reciprocal["pair_id"]
                pair_id = evt_a_reciprocal["pair_id"]

                # 6. Trigger decision evaluation
                dec_resp = client.post(
                    f"/api/reciprocal-pairs/{pair_id}/decision",
                    headers=user_a["headers"],
                )
                assert dec_resp.status_code == 200

                # 7. Check real-time DECISION_RESOLVED events
                evt_a_decision = json.loads(ws_a.receive_text())
                evt_b_decision = json.loads(ws_b.receive_text())
                assert evt_a_decision["event"] == "DECISION_RESOLVED"
                assert evt_b_decision["event"] == "DECISION_RESOLVED"

                # Alice has PREFER_OUTGOING, so Alice's action is PROCEED
                assert evt_a_decision["action"] == "PROCEED"
                assert evt_a_decision["decision_type"] == "ALLOW_A_TO_B"

                # Bob's action is STANDBY to receive Alice's carrier call
                assert evt_b_decision["action"] == "STANDBY"
                assert evt_b_decision["decision_type"] == "ALLOW_A_TO_B"

                # 8. Verify history endpoint records the resolved pair with full telemetry
                history_resp = client.get("/api/reciprocal-pairs", headers=user_a["headers"])
                assert history_resp.status_code == 200
                history_data = history_resp.json()
                assert history_data["total"] >= 1
                matched = [p for p in history_data["pairs"] if p["pair_id"] == pair_id][0]
                assert matched["decision_type"] == "ALLOW_A_TO_B"
                assert matched["reason_code"] == "USER_PREFERENCE"
                assert matched["time_difference_ms"] >= 0
