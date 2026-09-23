"""
WebSocket Connection Manager — Phase 7.

Manages real-time WebSocket connections for active SmartDial users.
Enables pushing instantaneous events (reciprocal detected, decision resolved)
to connected client apps without polling.
"""

import asyncio
import json
import logging
from typing import Dict, List, Set
from fastapi import WebSocket

logger = logging.getLogger(__name__)


class ConnectionManager:
    """Thread-safe WebSocket connection registry indexed by user_id."""

    def __init__(self) -> None:
        # user_id -> set of active WebSockets (allows multiple devices/tabs per user)
        self._active_connections: Dict[int, Set[WebSocket]] = {}
        self._lock = asyncio.Lock()
        self.loop: asyncio.AbstractEventLoop | None = None

    async def connect(self, user_id: int, websocket: WebSocket) -> None:
        """Register a newly accepted WebSocket connection for a user."""
        await websocket.accept()
        try:
            self.loop = asyncio.get_running_loop()
        except RuntimeError:
            pass
        async with self._lock:
            if user_id not in self._active_connections:
                self._active_connections[user_id] = set()
            self._active_connections[user_id].add(websocket)
        logger.info("User %s connected via WebSocket (active sessions: %d)", user_id, len(self._active_connections[user_id]))

    async def disconnect(self, user_id: int, websocket: WebSocket) -> None:
        """Remove a closed WebSocket connection."""
        async with self._lock:
            if user_id in self._active_connections:
                self._active_connections[user_id].discard(websocket)
                if not self._active_connections[user_id]:
                    del self._active_connections[user_id]
        logger.info("User %s disconnected WebSocket session", user_id)

    async def send_to_user(self, user_id: int, message: dict) -> None:
        """Send a JSON message to all active connections for a given user."""
        async with self._lock:
            sockets = list(self._active_connections.get(user_id, set()))

        payload = json.dumps(message)
        dead_sockets: List[WebSocket] = []

        for ws in sockets:
            try:
                await ws.send_text(payload)
            except Exception as exc:
                logger.warning("Failed to send WebSocket message to user %s: %s", user_id, exc)
                dead_sockets.append(ws)

        if dead_sockets:
            async with self._lock:
                if user_id in self._active_connections:
                    for dead in dead_sockets:
                        self._active_connections[user_id].discard(dead)
                    if not self._active_connections[user_id]:
                        del self._active_connections[user_id]

    async def broadcast_to_users(self, user_ids: List[int], message: dict) -> None:
        """Broadcast a JSON message to a list of users concurrently."""
        tasks = [self.send_to_user(uid, message) for uid in user_ids]
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    def is_user_online(self, user_id: int) -> bool:
        """Return whether the user has at least one active connection."""
        return user_id in self._active_connections and bool(self._active_connections[user_id])

    def publish_to_user_threadsafe(self, user_id: int, message: dict) -> None:
        """Publish message from any thread to the event loop running WebSockets."""
        target_loop = self.loop
        if target_loop and not target_loop.is_closed():
            asyncio.run_coroutine_threadsafe(self.send_to_user(user_id, message), target_loop)

    def publish_to_users_threadsafe(self, user_ids: List[int], message: dict) -> None:
        """Publish message to multiple users from any thread to the event loop."""
        target_loop = self.loop
        if target_loop and not target_loop.is_closed():
            asyncio.run_coroutine_threadsafe(self.broadcast_to_users(user_ids, message), target_loop)


# Global singleton instance for application-wide push notifications
manager = ConnectionManager()
