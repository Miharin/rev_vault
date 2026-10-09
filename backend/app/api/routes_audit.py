import asyncio
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from typing import List, Dict, Any
from app.core.audit import audit_broadcaster, AuditEvent
from app.config import settings_manager, GuardrailSettings

router = APIRouter(prefix="/api/audit", tags=["Audit & Guardrails"])

@router.get("", response_model=List[Dict[str, Any]])
async def get_audit_history():
    return audit_broadcaster.get_history()

@router.get("/guardrail", response_model=GuardrailSettings)
async def get_guardrail_settings():
    return settings_manager.load_guardrail_settings()

@router.post("/guardrail", response_model=GuardrailSettings)
async def update_guardrail_settings(settings: GuardrailSettings):
    settings_manager.save_guardrail_settings(settings)
    return settings

# WebSocket endpoint for real-time live monitor in Flutter UI
@router.websocket("/ws")
async def audit_websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    queue = audit_broadcaster.subscribe()
    try:
        # First send recent history so UI populates immediately
        history = audit_broadcaster.get_history()
        for item in reversed(history[-20:]):
            await websocket.send_json(item)

        while True:
            event: AuditEvent = await queue.get()
            await websocket.send_json(event.model_dump())
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        audit_broadcaster.unsubscribe(queue)
