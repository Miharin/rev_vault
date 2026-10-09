from fastapi import APIRouter, HTTPException
from typing import Optional, Dict, Any, List
from pydantic import BaseModel
from app.config import settings_manager, SavedQueryConfig
from app.core.db_manager import db_manager
from app.core.audit import audit_broadcaster, AuditEvent

router = APIRouter(prefix="/api/query", tags=["Query"])

class ExecuteQueryRequest(BaseModel):
    sql: str
    safe_mode: bool = True
    requested_limit: Optional[int] = None

@router.post("", response_model=Dict[str, Any])
async def execute_query(req: ExecuteQueryRequest):
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=400, detail="No active database connection configured")

    result = await db_manager.execute_query(
        conn,
        sql=req.sql,
        safe_mode=req.safe_mode,
        requested_limit=req.requested_limit
    )

    audit_broadcaster.record_event(
        AuditEvent(
            source="FLUTTER_UI",
            action="execute_query",
            sql=req.sql,
            status="BLOCKED" if (result.error and "GUARDRAIL BLOCKED" in result.error) else ("ERROR" if result.error else "ALLOWED"),
            execution_time_ms=result.execution_time_ms,
            row_count=result.row_count,
            message=result.error or f"Executed in {result.execution_time_ms}ms"
        )
    )

    return result.to_dict()

class ExplainQueryRequest(BaseModel):
    sql: str
    analyze: bool = False

@router.post("/explain", response_model=Dict[str, Any])
async def explain_query(req: ExplainQueryRequest):
    """
    Analyzes query execution plan, costs, and heuristic optimization recommendations.
    """
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=400, detail="No active database connection configured")

    from app.core.explain_inspector import explain_inspector
    explain_res = await explain_inspector.explain_query(conn, req.sql, analyze=req.analyze)

    audit_broadcaster.record_event(
        AuditEvent(
            source="FLUTTER_UI",
            action="explain_query",
            sql=req.sql,
            status="ERROR" if explain_res.error else "ALLOWED",
            execution_time_ms=explain_res.execution_time_ms or explain_res.planning_time_ms or 0.0,
            message=explain_res.error or f"Explain completed ({explain_res.engine})"
        )
    )

    return explain_res.to_dict()

def quote_table_name(table_name: str, engine: str) -> str:
    parts = [p.strip('"`') for p in table_name.split(".")]
    if engine == "postgres":
        return ".".join(f'"{p}"' for p in parts)
    return ".".join(f'`{p}`' for p in parts)

@router.get("/preview/{table_name:path}")
async def preview_table(
    table_name: str,
    page: int = 1,
    page_size: int = 25,
    limit: Optional[int] = None,
    offset: Optional[int] = None
):
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=400, detail="No active database connection configured")

    actual_page_size = limit if limit is not None else page_size
    actual_page_size = max(1, min(actual_page_size, 200))
    actual_page = max(1, page)

    actual_offset = offset if offset is not None else (actual_page - 1) * actual_page_size
    actual_offset = max(0, actual_offset)

    quoted = quote_table_name(table_name, conn.engine)
    query = f"SELECT * FROM {quoted} LIMIT {actual_page_size} OFFSET {actual_offset}"
    result = await db_manager.execute_query(conn, query, safe_mode=True)

    parts = [p.strip('"`') for p in table_name.split(".")]
    if len(parts) >= 2:
        schema_name, raw_table = parts[0], parts[1]
    else:
        schema_name, raw_table = ("public" if conn.engine == "postgres" else "main"), parts[0]

    total_rows = await db_manager.get_table_row_count(conn, schema_name, raw_table)

    res_dict = result.to_dict()
    res_dict["total_rows"] = total_rows
    res_dict["page"] = actual_page
    res_dict["page_size"] = actual_page_size
    return res_dict

@router.get("/saved", response_model=List[SavedQueryConfig])
async def get_saved_queries():
    return settings_manager.load_saved_queries()

@router.post("/saved", response_model=SavedQueryConfig)
async def save_query(query: SavedQueryConfig):
    if not query.title.strip():
        raise HTTPException(status_code=400, detail="Query title cannot be empty")
    if not query.sql.strip():
        raise HTTPException(status_code=400, detail="Query SQL cannot be empty")
    return settings_manager.save_query(query)

@router.delete("/saved/{query_id}")
async def delete_saved_query(query_id: str):
    success = settings_manager.delete_query(query_id)
    if not success:
        raise HTTPException(status_code=404, detail="Saved query not found")
    return {"status": "ok", "deleted_id": query_id}

