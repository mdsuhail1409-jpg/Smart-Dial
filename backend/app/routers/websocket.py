"""
WebSocket router — Phase 7 real-time sync.

Allows Android/Flutter dialer clients to open a persistent duplex connection
for receiving instant push events when reciprocal pairs are detected or
when call coordination decisions are resolved.
"""

import json
import logging
from typing import Optional

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect, status

from app.security.jwt import decode_access_token
from app.services.connection_manager import manager

logger = logging.getLogger(__name__)

router = APIRouter(tags=["websockets"])


@router.websocket("/ws/calls")
async def websocket_call_events(
    websocket: WebSocket,
    token: Optional[str] = Query(None),
) -> None:
    """
    WebSocket endpoint for real-time call coordination events.

    Authentication:
        Must provide valid JWT access token as query param: ?token=<access_token>
    """
    if not token:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Missing authentication token")
        return

    payload = decode_access_token(token)
    if not payload or "sub" not in payload:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Invalid or expired token")
        return

    try:
        user_id = int(payload["sub"])
    except (ValueError, TypeError):
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Malformed token subject")
        return

    await manager.connect(user_id, websocket)

    try:
        # Send initial confirmation event
        await websocket.send_text(json.dumps({
            "event": "CONNECTION_ESTABLISHED",
            "user_id": user_id,
            "message": "Connected to SmartDial Real-time Coordination Bus",
        }))

        while True:
            data = await websocket.receive_text()
            try:
                msg = json.loads(data)
                # Handle heartbeat / ping
                if msg.get("type") == "PING":
                    await websocket.send_text(json.dumps({"type": "PONG"}))
            except json.JSONDecodeError:
                pass

    except WebSocketDisconnect:
        await manager.disconnect(user_id, websocket)
    except Exception as exc:
        logger.warning("Unexpected WebSocket error for user %s: %s", user_id, exc)
        await manager.disconnect(user_id, websocket)
