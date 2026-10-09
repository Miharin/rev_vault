from fastapi import APIRouter, HTTPException
from typing import List
from pydantic import BaseModel
from app.config import ConnectionConfig, settings_manager
from app.core.db_manager import db_manager
from app.core.schema_inspector import schema_inspector

router = APIRouter(prefix="/api/connections", tags=["Connections"])

class TestConnectionRequest(BaseModel):
    config: ConnectionConfig

@router.get("", response_model=List[ConnectionConfig])
async def list_connections():
    return settings_manager.load_connections()

@router.post("", response_model=ConnectionConfig)
async def save_connection(conn: ConnectionConfig):
    conns = settings_manager.load_connections()
    existing_idx = next((i for i, c in enumerate(conns) if c.id == conn.id), None)
    if existing_idx is not None:
        conns[existing_idx] = conn
    else:
        # If this is the first connection, make it active
        if not conns:
            conn.is_active = True
        conns.append(conn)
    settings_manager.save_connections(conns)
    return conn

@router.delete("/{conn_id}")
async def delete_connection(conn_id: str):
    schema_inspector.invalidate_cache(conn_id)
    conns = settings_manager.load_connections()
    conns = [c for c in conns if c.id != conn_id]
    settings_manager.save_connections(conns)
    return {"status": "success", "message": f"Connection {conn_id} removed"}

@router.post("/test")
async def test_connection(req: TestConnectionRequest):
    success, message = await db_manager.test_connection(req.config)
    return {"success": success, "message": message}

@router.post("/active/{conn_id}", response_model=ConnectionConfig)
async def set_active_connection(conn_id: str):
    schema_inspector.invalidate_cache(conn_id)
    conn = settings_manager.set_active_connection(conn_id)
    if not conn:
        raise HTTPException(status_code=404, detail="Connection ID not found")
    return conn

@router.get("/active", response_model=ConnectionConfig)
async def get_active_connection():
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=404, detail="No active database connection configured")
    return conn
