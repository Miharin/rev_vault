import json
from typing import Dict, Any, List, Optional
from mcp.server.mcpserver import MCPServer
from app.config import settings_manager
from app.core.db_manager import db_manager
from app.core.schema_inspector import schema_inspector
from app.core.guardrail import guardrail
from app.core.audit import audit_broadcaster, AuditEvent

mcp = MCPServer("revvault-mcp")

@mcp.tool()
async def list_tables(include_views: bool = True) -> str:
    """
    List all tables and views present in the active RevVault database.
    """
    active_conn = settings_manager.get_active_connection()
    if not active_conn:
        return "No active database connection configured in RevVault. Please configure a connection first."

    tables = await schema_inspector.get_tables(active_conn, include_views=include_views)
    result = [t.to_dict() for t in tables]

    audit_broadcaster.record_event(
        AuditEvent(
            source="ANTIGRAVITY_MCP",
            action="list_tables",
            status="ALLOWED",
            message=f"Retrieved {len(result)} tables/views from {active_conn.name}"
        )
    )
    return json.dumps(result, indent=2)

@mcp.tool()
async def describe_table(table_name: str) -> str:
    """
    Get detailed column information, data types, and primary key status for a specific table.
    """
    active_conn = settings_manager.get_active_connection()
    if not active_conn:
        return "No active database connection configured in RevVault."

    table_meta = await schema_inspector.describe_table(active_conn, table_name)
    if not table_meta:
        return f"Table '{table_name}' not found in active database '{active_conn.name}'."

    audit_broadcaster.record_event(
        AuditEvent(
            source="ANTIGRAVITY_MCP",
            action="describe_table",
            status="ALLOWED",
            message=f"Described table {table_name} ({len(table_meta.columns)} columns)"
        )
    )
    return json.dumps(table_meta.to_dict(), indent=2)

@mcp.tool()
async def get_table_relations() -> str:
    """
    Get all Foreign Key relationships and entity connections across tables in the active database.
    Essential for determining accurate JOIN conditions.
    """
    active_conn = settings_manager.get_active_connection()
    if not active_conn:
        return "No active database connection configured in RevVault."

    relations = await schema_inspector.get_relationships(active_conn)
    audit_broadcaster.record_event(
        AuditEvent(
            source="ANTIGRAVITY_MCP",
            action="get_table_relations",
            status="ALLOWED",
            message=f"Retrieved {len(relations)} entity relationships from {active_conn.name}"
        )
    )
    return json.dumps(relations, indent=2)

@mcp.tool()
async def execute_safe_query(sql: str, max_rows: int = 50) -> str:
    """
    Safely execute a read-only SQL query (SELECT, EXPLAIN) on the active database.
    Destructive operations (DROP, DELETE, TRUNCATE, ALTER, UPDATE, INSERT) are strictly intercepted and blocked by the AST Guardrail.
    """
    active_conn = settings_manager.get_active_connection()
    if not active_conn:
        return "No active database connection configured in RevVault."

    dialect = "sqlite" if active_conn.engine == "sqlite" else "postgres"

    # AST Guardrail Inspection
    is_safe, error_msg, sanitized_sql = guardrail.validate_and_sanitize(
        sql, dialect=dialect, enforce_limit=True, requested_limit=max_rows
    )

    if not is_safe:
        audit_broadcaster.record_event(
            AuditEvent(
                source="ANTIGRAVITY_MCP",
                action="execute_safe_query",
                sql=sql,
                status="BLOCKED",
                message=error_msg
            )
        )
        return f"SECURITY GUARDRAIL REJECTION:\n{error_msg}"

    # Execute Safe Query
    res = await db_manager.execute_query(active_conn, sanitized_sql, safe_mode=False)

    if res.error:
        audit_broadcaster.record_event(
            AuditEvent(
                source="ANTIGRAVITY_MCP",
                action="execute_safe_query",
                sql=sanitized_sql,
                status="ERROR",
                execution_time_ms=res.execution_time_ms,
                message=res.error
            )
        )
        return f"Execution error: {res.error}"

    audit_broadcaster.record_event(
        AuditEvent(
            source="ANTIGRAVITY_MCP",
            action="execute_safe_query",
            sql=sanitized_sql,
            status="ALLOWED",
            execution_time_ms=res.execution_time_ms,
            row_count=res.row_count,
            message="Query executed successfully"
        )
    )

    return json.dumps(res.to_dict(), indent=2)

@mcp.tool()
async def get_table_preview(table_name: str, limit: int = 20) -> str:
    """
    Fetch a sample preview (top N rows) from a table in the active database.
    """
    active_conn = settings_manager.get_active_connection()
    if not active_conn:
        return "No active database connection configured in RevVault."

    safe_limit = min(max(1, limit), 100)
    # Quote identifier safely
    quoted_table = f'"{table_name}"' if active_conn.engine == "postgres" else f'`{table_name}`'
    query = f"SELECT * FROM {quoted_table} LIMIT {safe_limit}"

    res = await db_manager.execute_query(active_conn, query, safe_mode=True, requested_limit=safe_limit)
    if res.error:
        return f"Error previewing table '{table_name}': {res.error}"

    audit_broadcaster.record_event(
        AuditEvent(
            source="ANTIGRAVITY_MCP",
            action="get_table_preview",
            sql=query,
            status="ALLOWED",
            execution_time_ms=res.execution_time_ms,
            row_count=res.row_count,
            message=f"Previewed {res.row_count} rows for {table_name}"
        )
    )
    return json.dumps(res.to_dict(), indent=2)

@mcp.tool()
async def explain_query(sql: str, analyze: bool = False) -> str:
    """
    Generate an execution plan, total costs, and performance optimization recommendations for a SQL query.
    """
    active_conn = settings_manager.get_active_connection()
    if not active_conn:
        return "No active database connection configured in RevVault."

    from app.core.explain_inspector import explain_inspector
    result = await explain_inspector.explain_query(active_conn, sql, analyze=analyze)

    audit_broadcaster.record_event(
        AuditEvent(
            source="ANTIGRAVITY_MCP",
            action="explain_query",
            sql=sql,
            status="ERROR" if result.error else "ALLOWED",
            execution_time_ms=result.execution_time_ms or result.planning_time_ms or 0.0,
            message=result.error or f"Explained query ({result.engine})"
        )
    )
    return json.dumps(result.to_dict(), indent=2)

