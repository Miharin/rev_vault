import json
import logging
from typing import Any, Dict, List, Optional, Tuple
import httpx2

from app.config import settings_manager
from app.core.db_manager import db_manager
from app.core.schema_inspector import schema_inspector
from app.core.guardrail import guardrail
from app.core.audit import audit_broadcaster, AuditEvent

logger = logging.getLogger("revvault.agent")

AGENT_SYSTEM_PROMPT = (
    "You are the RevVault AI Database Assistant, developed by Relva. "
    "Your objective is to assist developers with database exploration, schema inspection, "
    "SQL query construction, performance optimization, and safe data exploration. "
    "You have access to read-only database tools to inspect tables and execute safe queries. "
    "Be precise, objective, and professional. "
    "Format all SQL queries within ```sql markdown code blocks. "
    "Never attempt destructive operations (DROP, DELETE, TRUNCATE, ALTER, UPDATE, INSERT); "
    "only read-only analysis is permitted."
)

DEFAULT_MODEL = "gemma4:e4b"
DEFAULT_OLLAMA_URL = "http://localhost:11434"

AGENT_TOOLS_SCHEMA = [
    {
        "type": "function",
        "function": {
            "name": "list_tables",
            "description": "List all tables and views present in the active database.",
            "parameters": {
                "type": "object",
                "properties": {
                    "include_views": {
                        "type": "boolean",
                        "description": "Whether to include views in the listing",
                        "default": True
                    }
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "describe_table",
            "description": "Get detailed column names, data types, nullability, and keys for a specific table.",
            "parameters": {
                "type": "object",
                "properties": {
                    "table_name": {
                        "type": "string",
                        "description": "The exact name of the table to describe"
                    }
                },
                "required": ["table_name"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_table_relations",
            "description": "Get all Foreign Key relationships and entity associations across tables.",
            "parameters": {
                "type": "object",
                "properties": {}
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "execute_safe_query",
            "description": "Execute a read-only SQL SELECT or EXPLAIN query under AST security guardrails.",
            "parameters": {
                "type": "object",
                "properties": {
                    "sql": {
                        "type": "string",
                        "description": "The SQL query to execute"
                    },
                    "max_rows": {
                        "type": "integer",
                        "description": "Maximum number of rows to return (default: 50, max: 100)",
                        "default": 50
                    }
                },
                "required": ["sql"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_table_preview",
            "description": "Fetch a sample preview of the top rows from a table in the active database.",
            "parameters": {
                "type": "object",
                "properties": {
                    "table_name": {
                        "type": "string",
                        "description": "Name of the table to preview"
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Number of sample rows to fetch (default: 15)",
                        "default": 15
                    }
                },
                "required": ["table_name"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "explain_query",
            "description": "Generate an execution plan and performance analysis for a SQL query.",
            "parameters": {
                "type": "object",
                "properties": {
                    "sql": {
                        "type": "string",
                        "description": "The SQL query to analyze"
                    },
                    "analyze": {
                        "type": "boolean",
                        "description": "Whether to run EXPLAIN ANALYZE (execute query with timing)",
                        "default": False
                    }
                },
                "required": ["sql"]
            }
        }
    }
]


class AgentService:
    """
    In-app database assistant service connecting local Ollama models with RevVault's
    AST guardrail and database engine.
    """

    @staticmethod
    async def check_status(ollama_url: str = DEFAULT_OLLAMA_URL) -> Dict[str, Any]:
        """
        Pings Ollama and returns available models and readiness status.
        """
        clean_url = ollama_url.rstrip("/")
        try:
            async with httpx2.AsyncClient(timeout=4.0) as client:
                res = await client.get(f"{clean_url}/api/tags")
                if res.status_code == 200:
                    data = res.json()
                    models = [m.get("name") for m in data.get("models", []) if m.get("name")]
                    
                    has_default = any(
                        DEFAULT_MODEL in m or m.startswith(DEFAULT_MODEL.split(":")[0])
                        for m in models
                    )
                    
                    return {
                        "online": True,
                        "url": clean_url,
                        "models": models,
                        "default_model": DEFAULT_MODEL,
                        "has_default_model": has_default
                    }
        except Exception as e:
            logger.debug(f"Ollama status check failed: {e}")

        return {
            "online": False,
            "url": clean_url,
            "models": [],
            "default_model": DEFAULT_MODEL,
            "has_default_model": False
        }

    @staticmethod
    async def execute_tool(tool_name: str, args: Dict[str, Any]) -> Tuple[str, bool]:
        """
        Executes a database tool directly in-process and reports audit events.
        Returns (result_text, is_success).
        """
        active_conn = settings_manager.get_active_connection()
        if not active_conn:
            return "No active database connection configured in RevVault.", False

        try:
            if tool_name == "list_tables":
                include_views = args.get("include_views", True)
                tables = await schema_inspector.get_tables(active_conn, include_views=include_views)
                result = [t.to_dict() for t in tables]
                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action="list_tables",
                        status="ALLOWED",
                        message=f"Agent retrieved {len(result)} tables from {active_conn.name}"
                    )
                )
                return json.dumps(result, indent=2), True

            elif tool_name == "describe_table":
                tbl = args.get("table_name", "")
                meta = await schema_inspector.describe_table(active_conn, tbl)
                if not meta:
                    return f"Table '{tbl}' not found in active database '{active_conn.name}'.", False
                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action="describe_table",
                        status="ALLOWED",
                        message=f"Agent described table {tbl} ({len(meta.columns)} cols)"
                    )
                )
                return json.dumps(meta.to_dict(), indent=2), True

            elif tool_name == "get_table_relations":
                relations = await schema_inspector.get_relationships(active_conn)
                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action="get_table_relations",
                        status="ALLOWED",
                        message=f"Agent retrieved {len(relations)} entity relationships"
                    )
                )
                return json.dumps(relations, indent=2), True

            elif tool_name == "execute_safe_query":
                sql = args.get("sql", "")
                max_rows = min(max(1, args.get("max_rows", 50)), 100)
                dialect = "sqlite" if active_conn.engine == "sqlite" else "postgres"

                is_safe, error_msg, sanitized_sql = guardrail.validate_and_sanitize(
                    sql, dialect=dialect, enforce_limit=True, requested_limit=max_rows
                )

                if not is_safe:
                    audit_broadcaster.record_event(
                        AuditEvent(
                            source="REVVAULT_AI_AGENT",
                            action="execute_safe_query",
                            sql=sql,
                            status="BLOCKED",
                            message=error_msg
                        )
                    )
                    return f"SECURITY GUARDRAIL BLOCKED:\n{error_msg}", False

                res = await db_manager.execute_query(active_conn, sanitized_sql, safe_mode=False)
                if res.error:
                    audit_broadcaster.record_event(
                        AuditEvent(
                            source="REVVAULT_AI_AGENT",
                            action="execute_safe_query",
                            sql=sanitized_sql,
                            status="ERROR",
                            execution_time_ms=res.execution_time_ms,
                            message=res.error
                        )
                    )
                    return f"Execution error: {res.error}", False

                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action="execute_safe_query",
                        sql=sanitized_sql,
                        status="ALLOWED",
                        execution_time_ms=res.execution_time_ms,
                        row_count=res.row_count,
                        message=f"Agent executed safe query ({res.row_count} rows)"
                    )
                )
                return json.dumps(res.to_dict(), indent=2), True

            elif tool_name == "get_table_preview":
                tbl = args.get("table_name", "")
                limit = min(max(1, args.get("limit", 15)), 50)
                quoted = f'"{tbl}"' if active_conn.engine == "postgres" else f'`{tbl}`'
                query = f"SELECT * FROM {quoted} LIMIT {limit}"

                res = await db_manager.execute_query(active_conn, query, safe_mode=True, requested_limit=limit)
                if res.error:
                    return f"Error previewing table '{tbl}': {res.error}", False

                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action="get_table_preview",
                        sql=query,
                        status="ALLOWED",
                        execution_time_ms=res.execution_time_ms,
                        row_count=res.row_count,
                        message=f"Agent previewed {res.row_count} rows for {tbl}"
                    )
                )
                return json.dumps(res.to_dict(), indent=2), True

            elif tool_name == "explain_query":
                sql = args.get("sql", "")
                analyze = args.get("analyze", False)
                from app.core.explain_inspector import explain_inspector
                res = await explain_inspector.explain_query(active_conn, sql, analyze=analyze)
                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action="explain_query",
                        sql=sql,
                        status="ERROR" if res.error else "ALLOWED",
                        execution_time_ms=res.execution_time_ms or res.planning_time_ms or 0.0,
                        message=res.error or f"Explained query ({res.engine})"
                    )
                )
                return json.dumps(res.to_dict(), indent=2), True

            return f"Unknown tool: {tool_name}", False

        except Exception as e:
            return f"Error executing tool '{tool_name}': {str(e)}", False

    @classmethod
    async def chat(
        cls,
        user_message: str,
        conversation_history: List[Dict[str, Any]],
        model: str = DEFAULT_MODEL,
        ollama_url: str = DEFAULT_OLLAMA_URL,
        max_turns: int = 5
    ) -> Dict[str, Any]:
        """
        Executes an agent conversation turn with multi-turn tool calling against Ollama.
        """
        clean_url = ollama_url.rstrip("/")

        # Initialize messages with system prompt if absent
        messages: List[Dict[str, Any]] = []
        has_system = any(m.get("role") == "system" for m in conversation_history)
        if not has_system:
            messages.append({"role": "system", "content": AGENT_SYSTEM_PROMPT})

        messages.extend(conversation_history)
        messages.append({"role": "user", "content": user_message})

        executed_tools: List[Dict[str, Any]] = []
        turn_count = 0

        async with httpx2.AsyncClient(timeout=120.0) as client:
            while turn_count < max_turns:
                turn_count += 1
                payload = {
                    "model": model,
                    "messages": messages,
                    "tools": AGENT_TOOLS_SCHEMA,
                    "stream": False
                }

                try:
                    res = await client.post(f"{clean_url}/api/chat", json=payload)
                    if res.status_code != 200:
                        return {
                            "error": f"Ollama returned HTTP {res.status_code}: {res.text}",
                            "content": f"Ollama connection error (HTTP {res.status_code}). Ensure Ollama is running and model '{model}' is installed.",
                            "tool_executions": executed_tools,
                            "history": messages
                        }
                    data = res.json()
                except Exception as req_err:
                    return {
                        "error": str(req_err),
                        "content": f"Failed to connect to Ollama at {clean_url}: {str(req_err)}",
                        "tool_executions": executed_tools,
                        "history": messages
                    }

                msg = data.get("message", {})
                messages.append(msg)

                tool_calls = msg.get("tool_calls", [])
                if not tool_calls:
                    # Final assistant response reached
                    return {
                        "error": None,
                        "content": msg.get("content", ""),
                        "tool_executions": executed_tools,
                        "history": messages
                    }

                # Process each tool call
                for call in tool_calls:
                    fn = call.get("function", {})
                    fn_name = fn.get("name", "")
                    fn_args = fn.get("arguments", {})

                    output_text, success = await cls.execute_tool(fn_name, fn_args)
                    executed_tools.append({
                        "name": fn_name,
                        "arguments": fn_args,
                        "output_preview": output_text[:200] + ("..." if len(output_text) > 200 else ""),
                        "success": success
                    })

                    messages.append({
                        "role": "tool",
                        "content": output_text
                    })

            # If loop finished without content
            final_content = messages[-1].get("content") or "Query executed and inspected."
            return {
                "error": None,
                "content": final_content,
                "tool_executions": executed_tools,
                "history": messages
            }

agent_service = AgentService()
