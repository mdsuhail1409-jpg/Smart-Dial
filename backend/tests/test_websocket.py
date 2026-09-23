"""
Phase 7 tests — Real-time WebSocket event streaming.
Tests WebSocket handshake, authentication, heartbeats, and real-time push
of RECIPROCAL_DETECTED and DECISION_RESOLVED events to connected clients.
"""

import json
import pytest
from starlette.testclient import TestClient

USER_A = {"name": "Arun",  "email": "a@test.com", "phone": "1000000001", "password": "PassWord1"}
USER_B = {"name": "Bala",  "email": "b@test.com", "phone": "1000000002", "password": "PassWord2"}


def _reg(client, user): client.post("/api/auth/register", json=user)
def _login(client, user) -> str: return client.post("/api/auth/login", json={"email": user["email"], "password": user["password"]}).json()["access_token"]
def _auth(token): return {"Authorization": f"Bearer {token}"}
def _ids(client, token): return {u["email"]: u["id"] for u in client.get("/api/users", headers=_auth(token)).json()["users"]}


def test_websocket_rejects_missing_token(client: TestClient):
    """Connecting without token is rejected."""
    with pytest.raises(Exception):
        with client.websocket_connect("/ws/calls"):
            pass


def test_websocket_rejects_invalid_token(client: TestClient):
    """Connecting with garbage token is rejected."""
    with pytest.raises(Exception):
        with client.websocket_connect("/ws/calls?token=invalid.token.here"):
            pass


def test_websocket_connect_and_heartbeat(client: TestClient):
    """Valid token connects, receives welcome frame, and replies to PING with PONG."""
    _reg(client, USER_A)
    tok_a = _login(client, USER_A)

    with client.websocket_connect(f"/ws/calls?token={tok_a}") as ws:
        msg = json.loads(ws.receive_text())
        assert msg["event"] == "CONNECTION_ESTABLISHED"

        ws.send_text(json.dumps({"type": "PING"}))
        reply = json.loads(ws.receive_text())
        assert reply["type"] == "PONG"


def test_websocket_receives_reciprocal_and_decision_push(client: TestClient):
    """
    When User A and User B connect, and reciprocal calls occur:
    Both clients immediately receive RECIPROCAL_DETECTED and DECISION_RESOLVED.
    """
    _reg(client, USER_A); _reg(client, USER_B)
    tok_a = _login(client, USER_A)
    tok_b = _login(client, USER_B)
    ids = _ids(client, tok_a)

    with client.websocket_connect(f"/ws/calls?token={tok_a}") as ws_a:
        with client.websocket_connect(f"/ws/calls?token={tok_b}") as ws_b:
            # Consume CONNECTION_ESTABLISHED
            init_a = json.loads(ws_a.receive_text())
            init_b = json.loads(ws_b.receive_text())
            assert init_a["event"] == "CONNECTION_ESTABLISHED"
            assert init_b["event"] == "CONNECTION_ESTABLISHED"

            # User A calls User B
            client.post("/api/calls/request", json={"receiver_id": ids["b@test.com"]}, headers=_auth(tok_a))

            # User B calls User A (triggers reciprocal detection and decision)
            client.post("/api/calls/request", json={"receiver_id": ids["a@test.com"]}, headers=_auth(tok_b))

            # Both should receive RECIPROCAL_DETECTED
            event_a_1 = json.loads(ws_a.receive_text())
            event_b_1 = json.loads(ws_b.receive_text())
            assert event_a_1["event"] == "RECIPROCAL_DETECTED"
            assert event_b_1["event"] == "RECIPROCAL_DETECTED"
            assert event_a_1["pair_id"] == event_b_1["pair_id"]
            pair_id = event_a_1["pair_id"]

            # Evaluate decision
            client.post(f"/api/reciprocal-pairs/{pair_id}/decision", headers=_auth(tok_a))

            # Both should receive DECISION_RESOLVED with their respective actions
            event_a_2 = json.loads(ws_a.receive_text())
            event_b_2 = json.loads(ws_b.receive_text())
            assert event_a_2["event"] == "DECISION_RESOLVED"
            assert event_b_2["event"] == "DECISION_RESOLVED"
            assert "action" in event_a_2
            assert "action" in event_b_2
