from fastapi import APIRouter, HTTPException
from typing import List, Dict, Any, Optional
from app.config import settings_manager
from app.core.schema_inspector import schema_inspector

router = APIRouter(prefix="/api/schema", tags=["Schema"])

@router.get("", response_model=List[Dict[str, Any]])
async def get_schema(include_views: bool = True, refresh: bool = False):
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=400, detail="No active database connection configured")
    tables = await schema_inspector.get_tables(conn, include_views=include_views, refresh=refresh)
    return [t.to_dict() for t in tables]

@router.get("/table/{table_name}")
async def describe_table(table_name: str):
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=400, detail="No active database connection configured")
    t = await schema_inspector.describe_table(conn, table_name)
    if not t:
        raise HTTPException(status_code=404, detail=f"Table '{table_name}' not found")
    return t.to_dict()

@router.get("/relationships", response_model=List[Dict[str, Any]])
async def get_relationships(refresh: bool = False):
    """
    Returns all detected Foreign Key entity relationships across active database tables.
    """
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=400, detail="No active database connection configured")
    return await schema_inspector.get_relationships(conn, refresh=refresh)

