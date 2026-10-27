# (__)
# (˶ᵔ ᵕ ᵔ˶) < "Lunar Territory."
# / >[CRIMSON+]> "Hands off, unless you're Miharin."

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
async def list_tables(
    schema: Optional[str] = None,
    search: Optional[str] = None,
    include_views: bool = True,
    limit: Optional[int] = 100
) -> str:
    """
    List tables and views present in the active RevVault database.
    Returns database-wide schema distribution, total counts, and lightweight summaries.
    Supports filtering by schema name or search keyword.
    """
    active_conn = settings_manager.get_active_connection()
    if not active_conn:
        return "No active database connection configured in RevVault. Please configure a connection first."

    if limit == 0:
        limit = None

    tables = await schema_inspector.get_tables(active_conn, include_views=include_views)
    summary = schema_inspector.format_tables_summary(
        tables=tables,
        schema=schema,
        search=search,
        limit=limit
    )

    audit_broadcaster.record_event(
        AuditEvent(
            source="ANTIGRAVITY_MCP",
            action="list_tables",
            status="ALLOWED",
            message=f"Retrieved {summary['returned_tables_count']}/{summary['total_database_tables']} tables from {active_conn.name}"
        )
    )
    return json.dumps(summary, indent=2)

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
async def get_table_relations(
    table_name: Optional[str] = None,
    schema: Optional[str] = None,
    search: Optional[str] = None,
    limit: Optional[int] = 50
) -> str:
    """
    Get Foreign Key relationships and entity connections across tables in the active database.
    Essential for determining accurate JOIN conditions.
    Supports filtering by table name (matching source or target), schema, or search keyword.
    """
    active_conn = settings_manager.get_active_connection()
    if not active_conn:
        return "No active database connection configured in RevVault."

    if limit == 0:
        limit = None

    relations = await schema_inspector.get_relationships(active_conn)
    summary = schema_inspector.format_relations_summary(
        relations=relations,
        table_name=table_name,
        schema=schema,
        search=search,
        limit=limit
    )

    audit_broadcaster.record_event(
        AuditEvent(
            source="ANTIGRAVITY_MCP",
            action="get_table_relations",
            status="ALLOWED",
            message=f"Retrieved {summary['returned_relations_count']}/{summary['total_database_relations']} relationships from {active_conn.name}"
        )
    )
    return json.dumps(summary, indent=2)

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

@mcp.tool()
async def inspect_schema(table_name: Optional[str] = None, schema: Optional[str] = None) -> str:
    """
    Deeply inspect complete schema metadata for a table or database schema,
    including columns, nullability, primary keys, foreign keys, inbound relationships, and indexes.
    """
    active_conn = settings_manager.get_active_connection()
    if not active_conn:
        return "No active database connection configured in RevVault."

    data = await schema_inspector.inspect_schema(
        active_conn,
        table_name=table_name,
        schema=schema
    )
    audit_broadcaster.record_event(
        AuditEvent(
            source="ANTIGRAVITY_MCP",
            action="inspect_schema",
            status="ALLOWED",
            message=f"Inspected schema for '{table_name or schema or 'database'}' in {active_conn.name}"
        )
    )
    return json.dumps(data, indent=2)

@mcp.tool()
async def explain_query_plan(sql: str, analyze: bool = False) -> str:
    """
    Analyze query execution plan, estimated node costs, sequential scans, and indexing recommendations.
    """
    return await explain_query(sql=sql, analyze=analyze)

@mcp.tool()
async def data_profilling(table_name: str, columns: Optional[List[str]] = None, sample_size: int = 1000) -> str:
    """
    Compute statistical profile and data quality metrics for columns in a table
    (null rates, cardinality/distinct values, min/max, average, and sample frequency distribution).
    """
    active_conn = settings_manager.get_active_connection()
    if not active_conn:
        return "No active database connection configured in RevVault."

    from app.core.agent_service import agent_service
    profile = await agent_service.profile_data(
        active_conn,
        table_name=table_name,
        columns=columns,
        sample_size=sample_size
    )
    audit_broadcaster.record_event(
        AuditEvent(
            source="ANTIGRAVITY_MCP",
            action="data_profilling",
            status="ERROR" if "error" in profile else "ALLOWED",
            message=profile.get("error") or f"Profiled columns for {table_name}"
        )
    )
    return json.dumps(profile, indent=2)

@mcp.tool()
async def natural_language_to_sql(query_intent: str, target_tables: Optional[List[str]] = None) -> str:
    """
    Synthesize an optimal, guardrail-compliant SQL query from natural language intent with relational join reasoning.
    """
    active_conn = settings_manager.get_active_connection()
    if not active_conn:
        return "No active database connection configured in RevVault."

    from app.core.agent_service import agent_service
    res = await agent_service.natural_language_to_sql(
        active_conn,
        query_intent=query_intent,
        target_tables=target_tables
    )
    audit_broadcaster.record_event(
        AuditEvent(
            source="ANTIGRAVITY_MCP",
            action="natural_language_to_sql",
            status="ALLOWED" if res.get("is_safe") else "BLOCKED",
            message=f"Synthesized SQL for intent: '{query_intent[:60]}...'"
        )
    )
    return json.dumps(res, indent=2)

@mcp.tool()
async def evaluate_and_plan_query(sql: str) -> str:
    """
    Perform pre-execution validation, AST security inspection, query complexity scoring, and execution plan evaluation.
    """
    active_conn = settings_manager.get_active_connection()
    if not active_conn:
        return "No active database connection configured in RevVault."

    from app.core.agent_service import agent_service
    res = await agent_service.evaluate_and_plan_query(active_conn, sql)
    audit_broadcaster.record_event(
        AuditEvent(
            source="ANTIGRAVITY_MCP",
            action="evaluate_and_plan_query",
            sql=sql,
            status="ALLOWED" if res.get("is_safe") else "BLOCKED",
            message=f"Evaluated query (Risk: {res.get('risk_level')})"
        )
    )
    return json.dumps(res, indent=2)

@mcp.tool()
async def run_async_streaming_query(sql: str, chunk_size: int = 50, max_rows: int = 100) -> str:
    """
    Asynchronously execute a read-only SQL query with chunked streaming result batches and execution timing.
    """
    active_conn = settings_manager.get_active_connection()
    if not active_conn:
        return "No active database connection configured in RevVault."

    from app.core.agent_service import agent_service
    res = await agent_service.run_async_streaming_query(
        active_conn,
        sql=sql,
        chunk_size=chunk_size,
        max_rows=max_rows
    )
    audit_broadcaster.record_event(
        AuditEvent(
            source="ANTIGRAVITY_MCP",
            action="run_async_streaming_query",
            sql=sql,
            status="ALLOWED" if res.get("success") else "ERROR",
            execution_time_ms=res.get("execution_time_ms", 0.0),
            row_count=res.get("total_rows", 0),
            message=f"Streamed {res.get('total_rows', 0)} rows in {res.get('chunks_count', 0)} chunks"
        )
    )
    return json.dumps(res, indent=2)

