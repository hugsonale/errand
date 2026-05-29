import json
import asyncio
from typing import Dict, Set
from fastapi import WebSocket
import redis.asyncio as aioredis
from app.config import settings


class ConnectionManager:
    """
    Manages WebSocket connections for real-time location tracking.

    Architecture:
    - Each task has a "room" identified by task_id
    - Agent connects to room: broadcasts location updates
    - Client connects to same room: receives location updates
    - Redis pub/sub ensures this works across multiple server instances

    Connection types:
    - ws://host/api/v1/ws/track/{task_id}  → client tracking feed
    - ws://host/api/v1/ws/location         → agent location updates
    """

    def __init__(self):
        # task_id → set of client WebSocket connections
        self._task_rooms: Dict[str, Set[WebSocket]] = {}
        # user_id → WebSocket (one active connection per agent)
        self._agent_connections: Dict[str, WebSocket] = {}
        self._redis: aioredis.Redis | None = None
        self._pubsub_task: asyncio.Task | None = None

    async def startup(self):
        """Called on app startup — connects to Redis pub/sub."""
        try:
            self._redis = await aioredis.from_url(
                settings.REDIS_URL, decode_responses=True
            )
            self._pubsub_task = asyncio.create_task(self._redis_listener())
            print("✅ WebSocket Redis pub/sub connected")
        except Exception as e:
            print(f"⚠️  WebSocket Redis unavailable (single-instance mode): {e}")

    async def shutdown(self):
        """Called on app shutdown."""
        if self._pubsub_task:
            self._pubsub_task.cancel()
        if self._redis:
            await self._redis.aclose()

    # ─── Client tracking ──────────────────────────────────────────────────

    async def join_task_room(self, task_id: str, websocket: WebSocket):
        """Client joins the room to receive agent location updates."""
        await websocket.accept()
        if task_id not in self._task_rooms:
            self._task_rooms[task_id] = set()
        self._task_rooms[task_id].add(websocket)

    async def leave_task_room(self, task_id: str, websocket: WebSocket):
        """Client disconnects from task room."""
        if task_id in self._task_rooms:
            self._task_rooms[task_id].discard(websocket)
            if not self._task_rooms[task_id]:
                del self._task_rooms[task_id]

    # ─── Agent location broadcast ──────────────────────────────────────────

    async def register_agent(self, agent_id: str, websocket: WebSocket):
        """Agent registers their WebSocket for sending location updates."""
        await websocket.accept()
        self._agent_connections[agent_id] = websocket

    async def unregister_agent(self, agent_id: str):
        """Agent disconnects."""
        self._agent_connections.pop(agent_id, None)

    async def broadcast_location(
        self,
        task_id: str,
        lat: float,
        lng: float,
        agent_id: str,
        extra: dict | None = None,
    ):
        """
        Broadcasts agent location to all clients watching a task.
        Also publishes to Redis so other server instances receive it.
        """
        payload = json.dumps({
            "type": "location_update",
            "task_id": task_id,
            "agent_id": agent_id,
            "lat": lat,
            "lng": lng,
            "timestamp": __import__("datetime").datetime.utcnow().isoformat(),
            **(extra or {}),
        })

        # Broadcast to local connections
        await self._broadcast_to_room(task_id, payload)

        # Publish to Redis for other instances
        if self._redis:
            try:
                await self._redis.publish(f"location:{task_id}", payload)
            except Exception:
                pass  # Non-fatal — local broadcast already happened

    async def broadcast_task_event(self, task_id: str, event_type: str, data: dict):
        """
        Broadcasts task lifecycle events (started, completed, disputed)
        to all connected clients watching the task.
        """
        payload = json.dumps({
            "type": event_type,
            "task_id": task_id,
            **data,
        })
        await self._broadcast_to_room(task_id, payload)
        if self._redis:
            try:
                await self._redis.publish(f"task:{task_id}", payload)
            except Exception:
                pass

    async def _broadcast_to_room(self, task_id: str, message: str):
        """Sends message to all WebSocket connections in a task room."""
        connections = self._task_rooms.get(task_id, set()).copy()
        dead = set()
        for ws in connections:
            try:
                await ws.send_text(message)
            except Exception:
                dead.add(ws)
        # Clean up dead connections
        for ws in dead:
            self._task_rooms.get(task_id, set()).discard(ws)

    async def _redis_listener(self):
        """
        Listens to Redis pub/sub for location updates from other instances.
        Broadcasts them to local WebSocket connections.
        """
        if not self._redis:
            return
        pubsub = self._redis.pubsub()
        await pubsub.psubscribe("location:*", "task:*")
        try:
            async for message in pubsub.listen():
                if message["type"] != "pmessage":
                    continue
                channel = message.get("channel", "")
                data = message.get("data", "")
                if not isinstance(data, str):
                    continue
                # Extract task_id from channel name
                parts = channel.split(":", 1)
                if len(parts) == 2:
                    task_id = parts[1]
                    await self._broadcast_to_room(task_id, data)
        except asyncio.CancelledError:
            pass
        finally:
            await pubsub.unsubscribe()


# Global singleton
ws_manager = ConnectionManager()
