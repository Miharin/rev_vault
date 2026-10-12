from fastapi import APIRouter, HTTPException
from typing import Optional, Dict, Any, List
from pydantic import BaseModel
from app.config import settings_manager, SavedQueryConfig
from app.core.db_manager import db_manager
from app.core.audit import audit_broadcaster, AuditEvent
from app.core.history_manager import history_manager, MutationRecord

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

class MutateRowRequest(BaseModel):
    table_name: str
    operation: str  # "update" | "delete" | "insert"
    primary_keys: Optional[Dict[str, Any]] = None
    updated_values: Optional[Dict[str, Any]] = None

def _format_sql_literal(val: Any) -> str:
    if val is None:
        return "NULL"
    if isinstance(val, bool):
        return "TRUE" if val else "FALSE"
    if isinstance(val, (int, float)):
        return str(val)
    # String escaping: replace ' with ''
    sanitized = str(val).replace("'", "''")
    return f"'{sanitized}'"

def _quote_col_ident(col: str, engine: str) -> str:
    clean = col.strip('"`')
    return f'"{clean}"' if engine == "postgres" else f'`{clean}`'

@router.post("/row/mutate", response_model=Dict[str, Any])
async def mutate_row(req: MutateRowRequest):
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=400, detail="No active database connection configured")

    op = req.operation.lower()
    table_quoted = quote_table_name(req.table_name, conn.engine)
    old_row_values: Dict[str, Any] = {}

    if op in ("update", "delete"):
        if not req.primary_keys:
            raise HTTPException(status_code=400, detail="primary_keys must not be empty to safely target a row")

        where_clauses = []
        for k, v in req.primary_keys.items():
            col_quoted = _quote_col_ident(k, conn.engine)
            if v is None:
                where_clauses.append(f"{col_quoted} IS NULL")
            else:
                where_clauses.append(f"{col_quoted} = {_format_sql_literal(v)}")
        where_str = " AND ".join(where_clauses)

        # Fetch prior row snapshot before mutation for disaster recovery and undo log
        select_sql = f"SELECT * FROM {table_quoted} WHERE {where_str} LIMIT 1;"
        prior_res = await db_manager.execute_query(conn, select_sql, safe_mode=False)
        if prior_res.rows and len(prior_res.rows) > 0:
            row_data = prior_res.rows[0]
            old_row_values = {
                col: (row_data[i] if i < len(row_data) else None)
                for i, col in enumerate(prior_res.columns)
            }

        if op == "delete":
            sql = f"DELETE FROM {table_quoted} WHERE {where_str};"
        else:
            if not req.updated_values:
                raise HTTPException(status_code=400, detail="updated_values cannot be empty for an update operation")
            set_clauses = []
            for k, v in req.updated_values.items():
                col_quoted = _quote_col_ident(k, conn.engine)
                set_clauses.append(f"{col_quoted} = {_format_sql_literal(v)}")
            set_str = ", ".join(set_clauses)
            sql = f"UPDATE {table_quoted} SET {set_str} WHERE {where_str};"
    elif op == "insert":
        if not req.updated_values:
            raise HTTPException(status_code=400, detail="updated_values cannot be empty for an insert operation")
        col_names = [_quote_col_ident(k, conn.engine) for k in req.updated_values.keys()]
        val_literals = [_format_sql_literal(v) for v in req.updated_values.values()]
        cols_str = ", ".join(col_names)
        vals_str = ", ".join(val_literals)
        sql = f"INSERT INTO {table_quoted} ({cols_str}) VALUES ({vals_str});"
    else:
        raise HTTPException(status_code=400, detail=f"Unsupported mutation operation: {req.operation}")

    result = await db_manager.execute_query(conn, sql, safe_mode=False)

    status = "ERROR" if result.error else "ALLOWED"
    audit_broadcaster.record_event(
        AuditEvent(
            source="FLUTTER_UI",
            action=f"row_{op}",
            sql=sql,
            status=status,
            execution_time_ms=result.execution_time_ms,
            row_count=result.row_count,
            message=result.error or f"Mutated {result.row_count} row(s) in {req.table_name}"
        )
    )

    if result.error:
        return {
            "success": False,
            "error": result.error,
            "sql": sql,
            "affected_rows": 0
        }

    # Record mutation into persistent history for disaster recovery
    history_id = None
    if not result.error and (result.row_count > 0 or op in ("insert", "update", "delete")):
        if op == "delete":
            snapshot_old = old_row_values
            new_vals = None
            pk_record = req.primary_keys or {}
        elif op == "update":
            snapshot_old = {
                k: old_row_values.get(k)
                for k in req.updated_values.keys()
            } if req.updated_values else {}
            new_vals = req.updated_values
            pk_record = req.primary_keys or {}
        else:  # insert
            snapshot_old = {}
            new_vals = req.updated_values
            pk_record = req.primary_keys or (req.updated_values or {})

        record = history_manager.record_mutation(
            table_name=req.table_name,
            operation=req.operation,
            primary_keys=pk_record,
            old_values=snapshot_old,
            new_values=new_vals,
            engine=conn.engine
        )
        history_id = record.id

    return {
        "success": True,
        "affected_rows": result.row_count,
        "sql": sql,
        "execution_time_ms": result.execution_time_ms,
        "history_id": history_id
    }

@router.get("/history", response_model=List[Dict[str, Any]])
async def get_mutation_history():
    records = history_manager.load_history()
    # Return newest first
    return [r.model_dump() for r in reversed(records)]

@router.post("/history/recover/{history_id}", response_model=Dict[str, Any])
async def recover_mutation(history_id: str):
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=400, detail="No active database connection configured")
    res = await history_manager.recover(history_id, conn)
    if not res.get("success"):
        raise HTTPException(status_code=400, detail=res.get("error", "Failed to recover mutation"))
    return res



