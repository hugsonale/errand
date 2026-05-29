import json
import uuid
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.core.security import decode_access_token
from app.models.user import User, UserRole
from app.models.task import Task, TaskStatus
from app.models.agent_profile import AgentProfile
from app.websockets.connection_manager import ws_manager
from jose import JWTError

router = APIRouter(prefix="/ws", tags=["WebSockets"])


async def _authenticate_ws(token: str) -> User | None:
    """Validates JWT from WebSocket query param. Returns User or None."""
    try:
        payload = decode_access_token(token)
        user_id = payload.get("sub")
        if not user_id:
            return None
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(User).where(User.id == uuid.UUID(user_id))
            )
            return result.scalar_one_or_none()
    except (JWTError, ValueError):
        return None


@router.websocket("/track/{task_id}")
async def client_task_tracking(
    websocket: WebSocket,
    task_id: str,
    token: str = Query(...),
):
    """
    Client WebSocket — subscribe to live location updates for a task.

    Connect: ws://host/api/v1/ws/track/{task_id}?token={access_token}

    Receives JSON messages:
    {
        "type": "location_update",
        "task_id": "...",
        "agent_id": "...",
        "lat": 6.5244,
        "lng": 3.3792,
        "timestamp": "2025-01-01T12:00:00"
    }

    Also receives task lifecycle events:
    { "type": "task_started" | "proof_submitted" | "task_completed" }
    """
    user = await _authenticate_ws(token)
    if not user:
        await websocket.close(code=4001, reason="Unauthorized")
        return

    # Verify user is the client for this task
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Task).where(Task.id == uuid.UUID(task_id))
        )
        task = result.scalar_one_or_none()

    if not task:
        await websocket.close(code=4004, reason="Task not found")
        return

    if task.client_id != user.id and user.role != UserRole.ADMIN:
        await websocket.close(code=4003, reason="Forbidden")
        return

    if task.status not in (
        TaskStatus.ACCEPTED, TaskStatus.IN_PROGRESS, TaskStatus.PROOF_SUBMITTED
    ):
        await websocket.close(code=4400, reason="Task not active")
        return

    await ws_manager.join_task_room(task_id, websocket)
    try:
        # Send current task state immediately on connect
        await websocket.send_json({
            "type": "connected",
            "task_id": task_id,
            "task_status": task.status.value,
            "message": "Connected to live tracking",
        })

        # Keep connection alive — client sends pings
        while True:
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_text("pong")

    except WebSocketDisconnect:
        await ws_manager.leave_task_room(task_id, websocket)
    except Exception:
        await ws_manager.leave_task_room(task_id, websocket)


@router.websocket("/location")
async def agent_location_sender(
    websocket: WebSocket,
    token: str = Query(...),
):
    """
    Agent WebSocket — send live location updates.

    Connect: ws://host/api/v1/ws/location?token={access_token}

    Send JSON:
    {
        "task_id": "...",
        "lat": 6.5244,
        "lng": 3.3792
    }

    Receive acknowledgement:
    { "type": "ack", "received": true }
    """
    user = await _authenticate_ws(token)
    if not user or user.role != UserRole.AGENT:
        await websocket.close(code=4001, reason="Unauthorized — agents only")
        return

    agent_id = str(user.id)
    await ws_manager.register_agent(agent_id, websocket)

    try:
        await websocket.send_json({
            "type": "connected",
            "message": "Location channel ready. Send location updates.",
        })

        while True:
            raw = await websocket.receive_text()

            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_json({"type": "error", "message": "Invalid JSON"})
                continue

            task_id = data.get("task_id")
            lat = data.get("lat")
            lng = data.get("lng")

            if not all([task_id, lat is not None, lng is not None]):
                await websocket.send_json({
                    "type": "error",
                    "message": "Required: task_id, lat, lng",
                })
                continue

            # Validate this agent is assigned to this task
            async with AsyncSessionLocal() as db:
                profile_result = await db.execute(
                    select(AgentProfile).where(AgentProfile.user_id == user.id)
                )
                profile = profile_result.scalar_one_or_none()

                task_result = await db.execute(
                    select(Task).where(Task.id == uuid.UUID(task_id))
                )
                task = task_result.scalar_one_or_none()

                if not profile or not task or task.agent_id != profile.id:
                    await websocket.send_json({
                        "type": "error",
                        "message": "Not assigned to this task",
                    })
                    continue

                if task.status != TaskStatus.IN_PROGRESS:
                    await websocket.send_json({
                        "type": "error",
                        "message": "Task is not in progress",
                    })
                    continue

                # Update agent location in DB
                profile.current_lat = lat
                profile.current_lng = lng
                await db.commit()

            # Broadcast to all clients watching this task
            await ws_manager.broadcast_location(
                task_id=task_id,
                lat=lat,
                lng=lng,
                agent_id=agent_id,
            )

            await websocket.send_json({"type": "ack", "received": True})

    except WebSocketDisconnect:
        await ws_manager.unregister_agent(agent_id)
    except Exception as e:
        await ws_manager.unregister_agent(agent_id)
