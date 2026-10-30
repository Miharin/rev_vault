import json
import logging
import re
from typing import Any, Dict, List, Optional, Tuple
try:
    import httpx2 as httpx
except ImportError:
    import httpx

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
    "only read-only analysis is permitted.\n\n"
    "CRITICAL DATA QUERY WORKFLOW (HIGHEST PRIORITY):\n"
    "1. When the user asks to see, get, give, or query rows of data (e.g. 'show rows from...', 'select...', 'preview...'):\n"
    "   - YOUR PRIMARY OBJECTIVE IS TO EXECUTE THE SQL QUERY WITH `execute_safe_query`.\n"
    "   - DO NOT call `list_tables` when specific table names are provided in the user request. Calling `list_tables` is strictly forbidden for data queries.\n"
    "   - Step 1: Call `describe_table` for the target tables to inspect their columns if not already known.\n"
    "   - Step 2: Formulate the SQL query using discovered columns and join keys.\n"
    "   - Step 3: YOU MUST CALL `execute_safe_query` to fetch the real data rows!\n"
    "   - Step 4: The full dataset is automatically streamed and rendered into RevVault's interactive UI Data Matrix directly from the database engine.\n"
    "   - DO NOT waste tokens printing the full dataset as a huge markdown table; provide a clear, concise summary of the result and key column insights.\n"
    "   - NEVER substitute requested data rows with a database overview or schema table listing.\n\n"
    "DATABASE EXPLORATION GUIDELINES:\n"
    "2. ONLY when the user explicitly asks to explore the entire database or list all tables (e.g. 'what tables exist?', 'list schemas'):\n"
    "   - Review total table count and the schemas_summary breakdown.\n"
    "   - If the database contains many tables (>30) across multiple schemas, provide the high-level schema breakdown with counts first.\n"
    "   - If the user asks for a specific schema or topic (e.g. 'master', 'antrian', 'patients'), use the `schema` or `search` parameter in `list_tables`.\n"
    "3. When asked about Foreign Keys, entity relationships, or table joins:\n"
    "   - If the user asks about a specific table (e.g. 'foreign keys for users' or 'cara_keluar'), ALWAYS pass `table_name` to `get_table_relations` or use `describe_table`.\n"
    "   - If exploring relationships across the entire database, first review the total relations count and schema_distribution summary, highlighting key linked modules.\n\n"
    "AESTHETIC PRESENTATION & REAL DATA TABLES:\n"
    "4. When presenting database records, query previews, table schemas, column summaries, or relationship connections:\n"
    "   - The client UI Data Matrix automatically renders full interactive data tables directly from tool execution data.\n"
    "   - Only format lightweight summaries or small schemas (< 10 rows) as clean Markdown tables if helpful.\n"
    "   - Never dump raw unformatted text blocks, tab-separated lists, or raw JSON dictionaries in your final conversational response when presenting multi-record data.\n\n"
    "SQL GENERATION & RELATIONAL JOIN RULES (ZERO-GUESS PROTOCOL):\n"
    "5. When constructing SQL queries involving JOIN:\n"
    "   - ZERO-GUESS SCHEMA COMPARISON: When the user asks to join tables without providing the explicit 'ON' condition "
    "(e.g., 'table_a join table_b join table_c'):\n"
    "     * ALWAYS call `describe_table` for all tables being joined to fetch their actual column lists and types.\n"
    "     * NEVER guess generic textbook column names like `id` or `user_id`.\n"
    "     * Compare columns between the tables:\n"
    "       a) Match catalog Foreign Keys if defined.\n"
    "       b) Match exact domain identifier columns (e.g. `kd_user` = `kd_user`, `no_transaksi` = `no_transaksi`, `no_kunjungan` = `no_kunjungan`).\n"
    "       c) Match entity code heuristics (e.g. `users.unit` = `unit.kd_unit`, or `order.user_id` = `users.id`).\n"
    "       d) Bridge Transitive Joins: If two tables share no keys directly (e.g. `cara_keluar` and `unit`), traverse through the intermediary table (e.g. `cara_keluar.kd_user = users.kd_user JOIN unit ON users.unit = unit.kd_unit`).\n"
    "   - DEFAULT PROJECTION: Default to selecting ALL columns from the primary / base table: `<main_table>.*` (or `<alias>.*`), unless the user explicitly requested specific columns for it.\n"
    "   - JOINED TABLE SPECIFIC KEYS: If the user specifies exact keys or columns to show for a joined table (for example: 'rawat_inap_rme.cara_keluar join public.users and public.unit and in users show only name, and in the unit show nama_unit'):\n"
    "     * Keep ALL columns from the primary table: `rawat_inap_rme.cara_keluar.*`\n"
    "     * Map requested column synonyms to real schema columns (e.g., 'name' -> `public.users.nama_user AS name`, 'nama_unit' -> `public.unit.nama_unit`)\n"
    "     * Example:\n"
    "       ```sql\n"
    "       SELECT\n"
    "         c.*,\n"
    "         u.nama_user AS name,\n"
    "         un.nama_unit\n"
    "       FROM rawat_inap_rme.cara_keluar AS c\n"
    "       JOIN public.users AS u ON c.kd_user = u.kd_user\n"
    "       JOIN public.unit AS un ON u.unit = un.kd_unit;\n"
    "       ```\n"
    "   - NO SPECIFIC KEYS: If the user does not specify any specific keys for either table, default to selecting all columns (`<main_table>.*, <joined_table>.*` or `*`).\n"
    "   - SPECIFIC KEYS ON BOTH: If the user specifies specific columns for both tables, select only those requested columns.\n"
    "   - QUALIFICATION: Always explicitly qualify joined column names with their table name or alias to prevent ambiguous column reference collisions."
)
LUNAR_AGENT_SYSTEM_PROMPT = AGENT_SYSTEM_PROMPT

DEFAULT_MODEL = "gemma4:e4b"
DEFAULT_OLLAMA_URL = "http://localhost:11434"
LUNAR_AGENT_TIMEOUT_SECONDS: float = 3600.0  # 1 hour response window for deep reasoning & data exploration

def lunar_normalize_ollama_url(lunar_raw_url: str) -> str:
    """Normalizes Ollama endpoint URL by stripping whitespace, trailing slashes, and ensuring http/https scheme."""
    lunar_clean = (lunar_raw_url or DEFAULT_OLLAMA_URL).strip().rstrip("/")
    if not lunar_clean.startswith("http://") and not lunar_clean.startswith("https://"):
        lunar_clean = f"http://{lunar_clean}"
    return lunar_clean


# (__)
# (˶ᵔ ᵕ ᵔ˶) < "Lunar Territory."
# / >[CRIMSON+]> "Hands off, unless you're Miharin."

def lunar_is_safe_model_entry(lunar_model_entry: Any, lunar_include_unsafe: bool = False) -> bool:
    """
    Evaluates whether an Ollama model entry is safe to display and use.
    Filters out models where name, tag, or metadata contains 'unsafe' or flags indicating unsafe,
    unless lunar_include_unsafe is explicitly set to True.
    Supports both raw model dicts from /api/tags and string model names.
    """
    if lunar_include_unsafe:
        return True

    if isinstance(lunar_model_entry, str):
        return "unsafe" not in lunar_model_entry.lower()

    if not isinstance(lunar_model_entry, dict):
        return False

    # 1. Model name / tag check
    lunar_name = str(lunar_model_entry.get("name") or "").lower()
    if "unsafe" in lunar_name:
        return False

    # 2. Model details inspection (families, format, custom flags)
    lunar_details = lunar_model_entry.get("details", {})
    if isinstance(lunar_details, dict):
        for _, lunar_val in lunar_details.items():
            if isinstance(lunar_val, str) and "unsafe" in lunar_val.lower():
                return False
            elif isinstance(lunar_val, (list, tuple, set)) and any(
                isinstance(lunar_item, str) and "unsafe" in lunar_item.lower() for lunar_item in lunar_val
            ):
                return False

    # 3. Model flags, labels, or tags
    lunar_flags = lunar_model_entry.get("flags") or lunar_model_entry.get("tags") or []
    if isinstance(lunar_flags, (list, tuple, set)):
        if any(isinstance(lunar_f, str) and "unsafe" in lunar_f.lower() for lunar_f in lunar_flags):
            return False
    elif isinstance(lunar_flags, str) and "unsafe" in lunar_flags.lower():
        return False

    # 4. Explicit boolean flags (e.g. is_unsafe, unsafe)
    if lunar_model_entry.get("is_unsafe") is True or lunar_model_entry.get("unsafe") is True:
        return False

    return True


# (__)
# (˶ᵔ ᵕ ᵔ˶) < "Lunar Territory."
# / >[CRIMSON+]> "Hands off, unless you're Miharin."

def lunar_resolve_model_name(lunar_requested_model: str, lunar_known_models: Optional[List[str]] = None) -> str:
    """
    Normalizes and resolves common model aliases, shorthands, or version typos.
    For example:
    - 'gemma:e4b' -> 'gemma4:e4b' (when gemma4:e4b is known/default)
    - 'gemma-e4b' -> 'gemma4:e4b'
    - 'gemma' -> 'gemma4:e4b' (or first matching gemma model if available)
    - 'gemma:2b' -> 'gemma:2b'
    """
    if not lunar_requested_model:
        return DEFAULT_MODEL

    lunar_clean = lunar_requested_model.strip()
    lunar_known = lunar_known_models or []

    # 1. Exact match in known models
    if lunar_clean in lunar_known:
        return lunar_clean

    lunar_lower = lunar_clean.lower()

    # 2. Well-known alias mapping
    lunar_aliases = {
        "gemma:e4b": "gemma4:e4b",
        "gemma-e4b": "gemma4:e4b",
        "gemma_e4b": "gemma4:e4b",
        "gemma4": "gemma4:e4b",
    }
    if lunar_lower in lunar_aliases:
        lunar_candidate = lunar_aliases[lunar_lower]
        if not lunar_known or lunar_candidate in lunar_known:
            return lunar_candidate

    # 3. Known models prefix / family match
    if lunar_known:
        for km in lunar_known:
            if km.lower() == lunar_lower:
                return km
        for km in lunar_known:
            if km.lower().startswith(f"{lunar_lower}:"):
                return km
        # If bare model name requested (e.g. 'gemma'), match first model containing it
        if ":" not in lunar_clean:
            for km in lunar_known:
                if lunar_lower in km.lower():
                    return km

    return lunar_clean


AGENT_TOOLS_SCHEMA = [
    {
        "type": "function",
        "function": {
            "name": "list_tables",
            "description": "List tables and views in the active database. Returns schema distribution, total counts, and lightweight table summaries. ONLY use when user explicitly asks to explore what tables or schemas exist. NEVER use when the user asks for rows/data or when specific tables are already provided.",
            "parameters": {
                "type": "object",
                "properties": {
                    "schema": {
                        "type": "string",
                        "description": "Optional schema name to filter tables (e.g. 'public', 'master', 'rawat_inap_rme')"
                    },
                    "search": {
                        "type": "string",
                        "description": "Optional search keyword to match table names (case-insensitive)"
                    },
                    "include_views": {
                        "type": "boolean",
                        "description": "Whether to include views in the listing",
                        "default": True
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of tables to return in the list (default: 100). Use null or 0 for all matched tables.",
                        "default": 100
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
            "description": "Get Foreign Key relationships and entity associations across tables. Returns counts, schema distribution, and relation details. Supports filtering by table name, schema, or keyword.",
            "parameters": {
                "type": "object",
                "properties": {
                    "table_name": {
                        "type": "string",
                        "description": "Optional table name to filter relations (matches both outgoing source and incoming target connections, e.g. 'users' or 'master.cara_keluar')"
                    },
                    "schema": {
                        "type": "string",
                        "description": "Optional schema name to filter relationships (e.g. 'public', 'master', 'rawat_inap_rme')"
                    },
                    "search": {
                        "type": "string",
                        "description": "Optional search keyword to match source/target tables or columns"
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of relations to return (default: 50). Use null or 0 for all matched relations.",
                        "default": 50
                    }
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "execute_safe_query",
            "description": "Execute a read-only SQL SELECT or EXPLAIN query under AST security guardrails. MANDATORY tool to execute queries and fetch data rows whenever the user asks to see, get, or query table rows.",
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
    },
    {
        "type": "function",
        "function": {
            "name": "inspect_schema",
            "description": "Deeply inspect complete schema metadata for a table or database schema, including columns, data types, nullability, primary keys, foreign keys, inbound relationships, indexes, and row estimates.",
            "parameters": {
                "type": "object",
                "properties": {
                    "table_name": {
                        "type": "string",
                        "description": "Optional table name to inspect in deep detail"
                    },
                    "schema": {
                        "type": "string",
                        "description": "Optional schema name to inspect (e.g. 'public', 'master')"
                    }
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "explain_query_plan",
            "description": "Analyze execution plan, node tree, estimated costs, bottlenecks (e.g. sequential scans, temporary B-trees), and indexing recommendations for a SQL query.",
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
    },
    {
        "type": "function",
        "function": {
            "name": "data_profilling",
            "description": "Compute statistical profile and data quality metrics for columns in a table, including null rates, distinct values/cardinality, min/max, average, and sample frequency distribution.",
            "parameters": {
                "type": "object",
                "properties": {
                    "table_name": {
                        "type": "string",
                        "description": "The name of the table to profile"
                    },
                    "columns": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Optional subset of column names to profile. If omitted, profiles all key columns (up to 15)."
                    },
                    "sample_size": {
                        "type": "integer",
                        "description": "Sample row limit for profiling (default: 1000)",
                        "default": 1000
                    }
                },
                "required": ["table_name"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "natural_language_to_sql",
            "description": "Synthesize an optimal, guardrail-compliant SQL query from natural language intent with schema validation, table join reasoning, and AST guardrail verification.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query_intent": {
                        "type": "string",
                        "description": "Natural language query intent (e.g. 'find top 10 users with most orders last month')"
                    },
                    "target_tables": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Optional list of target tables to focus on"
                    }
                },
                "required": ["query_intent"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "evaluate_and_plan_query",
            "description": "Perform pre-execution validation, AST security inspection, query complexity scoring, and execution plan evaluation for a SQL query before running it.",
            "parameters": {
                "type": "object",
                "properties": {
                    "sql": {
                        "type": "string",
                        "description": "The SQL query to evaluate and plan"
                    }
                },
                "required": ["sql"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "run_async_streaming_query",
            "description": "Asynchronously execute a read-only SQL query with chunked streaming result batches, execution timing, and live row count progress.",
            "parameters": {
                "type": "object",
                "properties": {
                    "sql": {
                        "type": "string",
                        "description": "The SQL query to execute asynchronously"
                    },
                    "chunk_size": {
                        "type": "integer",
                        "description": "Number of rows per streaming batch (default: 50, max: 100)",
                        "default": 50
                    },
                    "max_rows": {
                        "type": "integer",
                        "description": "Maximum total rows to stream (default: 100, max: 200)",
                        "default": 100
                    }
                },
                "required": ["sql"]
            }
        }
    }
]


class ToolResult(tuple):
    """
    Subclass of 2-tuple (output, success) that also carries optional structured data
    without breaking legacy unpacking code: output, success = await execute_tool(...)
    """
    def __new__(cls, output: str, success: bool, data: Optional[Dict[str, Any]] = None):
        instance = super().__new__(cls, (output, success))
        instance._data = data
        return instance

    @property
    def output(self) -> str:
        return self[0]

    @property
    def success(self) -> bool:
        return self[1]

    @property
    def data(self) -> Optional[Dict[str, Any]]:
        return getattr(self, "_data", None)


class AgentService:
    """
    In-app database assistant service connecting local Ollama models with RevVault's
    AST guardrail and database engine.
    """

    @staticmethod
    async def check_status(ollama_url: str = DEFAULT_OLLAMA_URL, include_unsafe: bool = False) -> Dict[str, Any]:
        """
        Pings Ollama and returns available models and readiness status.
        Filters out models flagged or named 'unsafe' unless include_unsafe is True.
        """
        clean_url = lunar_normalize_ollama_url(ollama_url)
        try:
            async with httpx.AsyncClient(timeout=4.0) as client:
                res = await client.get(f"{clean_url}/api/tags")
                if res.status_code == 200:
                    data = res.json()
                    models = [
                        m.get("name")
                        for m in data.get("models", [])
                        if m.get("name") and lunar_is_safe_model_entry(m, lunar_include_unsafe=include_unsafe)
                    ]
                    
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

    @classmethod
    async def execute_tool(cls, tool_name: str, args: Dict[str, Any]) -> Tuple[str, bool]:
        """
        Executes a database tool directly in-process and reports audit events.
        Returns (result_text, is_success).
        """
        active_conn = settings_manager.get_active_connection()
        if not active_conn:
            return ToolResult("No active database connection configured in RevVault.", False, None)

        try:
            if tool_name == "list_tables":
                include_views = args.get("include_views", True)
                schema_filter = args.get("schema")
                search_filter = args.get("search")
                limit = args.get("limit")
                if limit == 0:
                    limit = None

                tables = await schema_inspector.get_tables(active_conn, include_views=include_views)
                summary = schema_inspector.format_tables_summary(
                    tables=tables,
                    schema=schema_filter,
                    search=search_filter,
                    limit=limit
                )

                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action="list_tables",
                        status="ALLOWED",
                        message=f"Agent retrieved {summary['returned_tables_count']}/{summary['total_database_tables']} tables from {active_conn.name}"
                    )
                )
                return ToolResult(json.dumps(summary, indent=2), True, summary)

            elif tool_name == "describe_table":
                tbl = args.get("table_name", "")
                meta = await schema_inspector.describe_table(active_conn, tbl)
                if not meta:
                    return ToolResult(f"Table '{tbl}' not found in active database '{active_conn.name}'.", False, None)
                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action="describe_table",
                        status="ALLOWED",
                        message=f"Agent described table {tbl} ({len(meta.columns)} cols)"
                    )
                )
                return ToolResult(json.dumps(meta.to_dict(), indent=2), True, meta.to_dict())

            elif tool_name == "get_table_relations":
                table_filter = args.get("table_name") or args.get("table")
                schema_filter = args.get("schema")
                search_filter = args.get("search")
                limit = args.get("limit")
                if limit == 0:
                    limit = None

                relations = await schema_inspector.get_relationships(active_conn)
                summary = schema_inspector.format_relations_summary(
                    relations=relations,
                    table_name=table_filter,
                    schema=schema_filter,
                    search=search_filter,
                    limit=limit
                )

                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action="get_table_relations",
                        status="ALLOWED",
                        message=f"Agent retrieved {summary['returned_relations_count']}/{summary['total_database_relations']} relationships from {active_conn.name}"
                    )
                )
                return ToolResult(json.dumps(summary, indent=2), True, summary)

            elif tool_name == "execute_safe_query":
                sql = args.get("sql", "")
                max_rows = min(max(1, args.get("max_rows", 100)), 500)
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
                    return ToolResult(f"SECURITY GUARDRAIL BLOCKED:\n{error_msg}", False, None)

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
                    return ToolResult(f"Execution error: {res.error}", False, None)

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

                structured_data = res.to_dict()
                structured_data["sql"] = sanitized_sql

                llm_summary = {
                    "status": "success",
                    "row_count": res.row_count,
                    "columns": res.columns,
                    "execution_time_ms": round(res.execution_time_ms, 2),
                    "sql": sanitized_sql,
                    "sample_rows": res.rows[:3],
                    "client_delivery": f"All {res.row_count} rows delivered directly to client UI Data Matrix.",
                    "instruction": "The complete dataset is already rendered in the client interactive table. Provide a concise summary or column insights for the user without generating a full markdown table."
                }
                return ToolResult(json.dumps(llm_summary, indent=2), True, structured_data)

            elif tool_name == "get_table_preview":
                tbl = args.get("table_name", "")
                limit = min(max(1, args.get("limit", 25)), 100)
                quoted = f'"{tbl}"' if active_conn.engine == "postgres" else f'`{tbl}`'
                query = f"SELECT * FROM {quoted} LIMIT {limit}"

                res = await db_manager.execute_query(active_conn, query, safe_mode=True, requested_limit=limit)
                if res.error:
                    return ToolResult(f"Error previewing table '{tbl}': {res.error}", False, None)

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
                structured_data = res.to_dict()
                structured_data["sql"] = query

                llm_summary = {
                    "status": "success",
                    "table": tbl,
                    "row_count": res.row_count,
                    "columns": res.columns,
                    "sample_rows": res.rows[:3],
                    "client_delivery": f"All {res.row_count} preview rows delivered directly to client UI Data Matrix.",
                    "instruction": "The complete preview dataset is already rendered in the client UI. Provide a brief summary of the table structure without generating the full table."
                }
                return ToolResult(json.dumps(llm_summary, indent=2), True, structured_data)

            elif tool_name in ("explain_query", "explain_query_plan"):
                sql = args.get("sql", "")
                analyze = args.get("analyze", False)
                from app.core.explain_inspector import explain_inspector
                res = await explain_inspector.explain_query(active_conn, sql, analyze=analyze)
                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action=tool_name,
                        sql=sql,
                        status="ERROR" if res.error else "ALLOWED",
                        execution_time_ms=res.execution_time_ms or res.planning_time_ms or 0.0,
                        message=res.error or f"Explained query plan ({res.engine})"
                    )
                )
                return json.dumps(res.to_dict(), indent=2), True

            elif tool_name == "inspect_schema":
                table_filter = args.get("table_name")
                schema_filter = args.get("schema")
                data = await schema_inspector.inspect_schema(
                    active_conn,
                    table_name=table_filter,
                    schema=schema_filter
                )
                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action="inspect_schema",
                        status="ALLOWED",
                        message=f"Agent inspected schema for '{table_filter or schema_filter or 'database'}' in {active_conn.name}"
                    )
                )
                return json.dumps(data, indent=2), True

            elif tool_name in ("data_profilling", "data_profiling"):
                tbl = args.get("table_name", "")
                cols = args.get("columns")
                sample_sz = args.get("sample_size", 1000)
                profile = await cls.profile_data(
                    active_conn,
                    table_name=tbl,
                    columns=cols,
                    sample_size=sample_sz
                )
                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action="data_profilling",
                        status="ERROR" if "error" in profile else "ALLOWED",
                        message=profile.get("error") or f"Profiled {profile.get('profiled_columns_count', 0)} columns for {tbl}"
                    )
                )
                return json.dumps(profile, indent=2), ("error" not in profile)

            elif tool_name == "natural_language_to_sql":
                intent = args.get("query_intent", "")
                tgt_tables = args.get("target_tables")
                res = await cls.natural_language_to_sql(
                    active_conn,
                    query_intent=intent,
                    target_tables=tgt_tables
                )
                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action="natural_language_to_sql",
                        status="ALLOWED" if res.get("is_safe") else "BLOCKED",
                        message=f"Synthesized SQL for intent: '{intent[:60]}...'"
                    )
                )
                return json.dumps(res, indent=2), True

            elif tool_name == "evaluate_and_plan_query":
                sql = args.get("sql", "")
                eval_res = await cls.evaluate_and_plan_query(active_conn, sql)
                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action="evaluate_and_plan_query",
                        sql=sql,
                        status="ALLOWED" if eval_res.get("is_safe") else "BLOCKED",
                        message=f"Evaluated query (Risk: {eval_res.get('risk_level')})"
                    )
                )
                return json.dumps(eval_res, indent=2), True

            elif tool_name == "run_async_streaming_query":
                sql = args.get("sql", "")
                chunk_sz = args.get("chunk_size", 50)
                max_r = args.get("max_rows", 100)
                stream_res = await cls.run_async_streaming_query(
                    active_conn,
                    sql=sql,
                    chunk_size=chunk_sz,
                    max_rows=max_r
                )
                audit_broadcaster.record_event(
                    AuditEvent(
                        source="REVVAULT_AI_AGENT",
                        action="run_async_streaming_query",
                        sql=sql,
                        status="ALLOWED" if stream_res.get("success") else "ERROR",
                        execution_time_ms=stream_res.get("execution_time_ms", 0.0),
                        row_count=stream_res.get("total_rows", 0),
                        message=f"Streamed {stream_res.get('total_rows', 0)} rows in {stream_res.get('chunks_count', 0)} chunks"
                    )
                )
                if stream_res.get("success"):
                    all_rows = [r for chunk in stream_res.get("chunks", []) for r in chunk.get("rows", [])]
                    structured_data = {
                        "columns": stream_res.get("columns", []),
                        "rows": all_rows,
                        "row_count": stream_res.get("total_rows", len(all_rows)),
                        "execution_time_ms": stream_res.get("execution_time_ms", 0.0),
                        "sql": stream_res.get("sql", sql)
                    }
                    return ToolResult(json.dumps(stream_res, indent=2), True, structured_data)
                return ToolResult(json.dumps(stream_res, indent=2), False, None)

            return f"Unknown tool: {tool_name}", False

        except Exception as e:
            return f"Error executing tool '{tool_name}': {str(e)}", False

    @classmethod
    async def profile_data(
        cls,
        conn: ConnectionConfig,
        table_name: str,
        columns: Optional[List[str]] = None,
        sample_size: int = 1000
    ) -> Dict[str, Any]:
        meta = await schema_inspector.describe_table(conn, table_name)
        if not meta:
            return {"error": f"Table '{table_name}' not found in active database '{conn.name}'."}

        target_columns = columns or [c.name for c in meta.columns[:15]]
        col_type_map = {c.name: c.data_type for c in meta.columns}

        quoted_table = f'"{meta.schema}"."{meta.raw_name}"' if conn.engine == "postgres" else f'`{meta.raw_name}`'

        count_res = await db_manager.execute_query(conn, f"SELECT count(*) FROM {quoted_table};", safe_mode=True)
        total_rows = int(count_res.rows[0][0]) if (count_res.rows and count_res.rows[0]) else 0

        column_profiles = []
        for col in target_columns:
            c_type = col_type_map.get(col, "TEXT").upper()
            c_quoted = f'"{col}"' if conn.engine == "postgres" else f'`{col}`'

            is_numeric = any(t in c_type for t in ("INT", "REAL", "FLOAT", "DOUBLE", "NUMERIC", "DECIMAL"))
            avg_clause = f", avg(CAST({c_quoted} AS REAL))" if is_numeric else ""

            agg_sql = f"""
                SELECT
                    count(*) - count({c_quoted}) AS null_cnt,
                    count(DISTINCT {c_quoted}) AS distinct_cnt,
                    min({c_quoted}) AS min_val,
                    max({c_quoted}) AS max_val
                    {avg_clause}
                FROM {quoted_table}
            """
            agg_res = await db_manager.execute_query(conn, agg_sql, safe_mode=True)
            null_cnt = 0
            distinct_cnt = 0
            min_val = None
            max_val = None
            avg_val = None

            if agg_res.rows and len(agg_res.rows[0]) >= 4:
                r = agg_res.rows[0]
                null_cnt = int(r[0]) if r[0] is not None else 0
                distinct_cnt = int(r[1]) if r[1] is not None else 0
                min_val = r[2]
                max_val = r[3]
                if is_numeric and len(r) >= 5 and r[4] is not None:
                    try:
                        avg_val = round(float(r[4]), 2)
                    except Exception:
                        pass

            null_pct = round((null_cnt / max(1, total_rows)) * 100.0, 1) if total_rows > 0 else 0.0

            freq_sql = f"""
                SELECT {c_quoted}, count(*) AS cnt
                FROM {quoted_table}
                WHERE {c_quoted} IS NOT NULL
                GROUP BY {c_quoted}
                ORDER BY cnt DESC
                LIMIT 3
            """
            freq_res = await db_manager.execute_query(conn, freq_sql, safe_mode=True)
            top_frequent = []
            if freq_res.rows:
                for fr in freq_res.rows:
                    top_frequent.append({"value": str(fr[0]), "count": int(fr[1])})

            column_profiles.append({
                "column": col,
                "data_type": c_type,
                "null_count": null_cnt,
                "null_percentage": null_pct,
                "distinct_count": distinct_cnt,
                "min": str(min_val) if min_val is not None else None,
                "max": str(max_val) if max_val is not None else None,
                "avg": avg_val,
                "top_frequent_values": top_frequent
            })

        return {
            "table_name": table_name,
            "total_rows": total_rows,
            "profiled_columns_count": len(column_profiles),
            "columns": column_profiles
        }

    @classmethod
    async def natural_language_to_sql(
        cls,
        conn: ConnectionConfig,
        query_intent: str,
        target_tables: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        tables = await schema_inspector.get_tables(conn, include_views=True)
        relations = await schema_inspector.get_relationships(conn)
        dialect = "sqlite" if conn.engine == "sqlite" else "postgres"

        matched_tables: List[TableMetadata] = []
        if target_tables:
            for tt in target_tables:
                m = schema_inspector.find_table(tables, tt)
                if m and m not in matched_tables:
                    matched_tables.append(m)

        if not matched_tables:
            # 1. Match schema-qualified names first (e.g. 'rawat_inap_rme.cara_keluar', 'public.users')
            matched_positions: List[Tuple[int, int, TableMetadata]] = []
            for m in re.finditer(r'\b([a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_]*)\b', query_intent):
                t_name = m.group(1)
                found = schema_inspector.find_table(tables, t_name)
                if found:
                    matched_positions.append((m.start(), m.end(), found))

            # 2. Match unqualified table names by word boundary
            reserved_words = {'in', 'is', 'of', 'to', 'at', 'as', 'or', 'by', 'for', 'on', 'no', 'do', 'if', 'and', 'not', 'the', 'first', 'row', 'rows', 'limit', 'show', 'select', 'get', 'give'}
            for t in tables:
                if t.raw_name.lower() in reserved_words or len(t.raw_name) < 2:
                    continue
                for m in re.finditer(r'\b' + re.escape(t.raw_name.lower()) + r'\b', query_intent.lower()):
                    if not any(start <= m.start() and m.end() <= end for start, end, _ in matched_positions):
                        matched_positions.append((m.start(), m.end(), t))

            # Sort by occurrence order in query_intent to preserve primary table order
            matched_positions.sort(key=lambda x: x[0])
            for _, _, t in matched_positions:
                if t not in matched_tables:
                    matched_tables.append(t)

        if not matched_tables and tables:
            matched_tables = tables[:2]

        if not matched_tables:
            return {"error": "No database tables found to formulate query."}

        # Ensure column definitions are loaded for all matched tables
        for i, t in enumerate(matched_tables):
            if not t.columns:
                described = await schema_inspector.describe_table(conn, t.name)
                if described and described.columns:
                    matched_tables[i] = described

        # Extract LIMIT from query_intent (e.g. '10 first row', 'limit 20', 'top 5')
        limit = 50
        limit_match = re.search(r'\b(?:limit|first|top)\s+(\d+)\b', query_intent, re.I) or re.search(r'\b(\d+)\s+(?:first|rows|row)\b', query_intent, re.I)
        if limit_match:
            try:
                limit = int(limit_match.group(1))
            except ValueError:
                pass

        primary_table = matched_tables[0]
        p_quoted = f'"{primary_table.schema}"."{primary_table.raw_name}"' if dialect == "postgres" else f'`{primary_table.raw_name}`'
        p_clean = primary_table.raw_name.lower() if primary_table.raw_name else "t"
        reserved_sql_keywords = {"or", "as", "on", "in", "is", "by", "to", "do", "if", "at", "no", "all", "and"}
        p_alias = p_clean[:1]
        if p_alias in reserved_sql_keywords:
            p_alias = p_clean[:2] if len(p_clean) >= 2 else f"{p_clean}1"

        joins = []
        joined_info: List[Tuple[TableMetadata, str]] = [(primary_table, p_alias)]
        used_aliases = {p_alias}

        for other_table in matched_tables[1:]:
            clean_raw = other_table.raw_name.lower()
            base_alias = clean_raw[:2] if len(clean_raw) >= 2 else clean_raw[:1]
            if base_alias in reserved_sql_keywords:
                base_alias = clean_raw[:3] if len(clean_raw) >= 3 else f"{clean_raw}1"

            o_alias = base_alias
            idx = 2
            while o_alias in used_aliases:
                o_alias = f"{base_alias}{idx}"
                idx += 1
            used_aliases.add(o_alias)

            o_quoted = f'"{other_table.schema}"."{other_table.raw_name}"' if dialect == "postgres" else f'`{other_table.raw_name}`'

            best_pred = None
            for j_table, j_alias in joined_info:
                pred = schema_inspector.predict_join_condition(
                    table_a=j_table,
                    table_b=other_table,
                    relations=relations,
                    alias_a=j_alias,
                    alias_b=o_alias
                )
                if pred:
                    if best_pred is None or pred.get("confidence", 0) > best_pred.get("confidence", 0):
                        best_pred = pred

            if best_pred:
                joins.append(f"JOIN {o_quoted} AS {o_alias} ON {best_pred['on_clause']}")
            else:
                joins.append(f"JOIN {o_quoted} AS {o_alias} ON {p_alias}.id = {o_alias}.id")

            joined_info.append((other_table, o_alias))

        # Dynamic column projections
        projections = [f"{p_alias}.*"]
        all_table_raws = {t.raw_name.lower() for t, _ in joined_info}
        prompt_lower = query_intent.lower()

        for j_table, j_alias in joined_info[1:]:
            j_cols = j_table.columns
            j_projected = []
            for col in j_cols:
                col_lower = col.name.lower()
                if col_lower in all_table_raws:
                    continue
                if re.search(r'\b' + re.escape(col_lower) + r'\b', prompt_lower):
                    j_projected.append(f"{j_alias}.{col.name}")
                elif re.search(r'\b(?:name|username)\b', prompt_lower) and any(k in col_lower for k in ('nama', 'name')) and 'kd_' not in col_lower:
                    if any(k in j_table.raw_name.lower() for k in ('user', 'pengguna', 'pegawai', 'member', 'person', 'petugas')):
                        j_projected.append(f"{j_alias}.{col.name} AS name")
            if j_projected:
                projections.extend(j_projected)

        select_clause = ",\n    ".join(projections)
        join_clause = ("\n" + "\n".join(joins)) if joins else ""
        sql = f"SELECT\n    {select_clause}\nFROM {p_quoted} AS {p_alias}{join_clause}\nLIMIT {limit};"

        is_safe, error_msg, sanitized_sql = guardrail.validate_and_sanitize(sql, dialect=dialect, enforce_limit=True, requested_limit=limit)

        return {
            "query_intent": query_intent,
            "sql": sanitized_sql or sql,
            "dialect": dialect,
            "tables_used": [t.name for t in matched_tables],
            "is_safe": is_safe,
            "guardrail_status": "ALLOWED" if is_safe else f"BLOCKED: {error_msg}",
            "joins_count": len(joins)
        }

    @classmethod
    async def evaluate_and_plan_query(
        cls,
        conn: ConnectionConfig,
        sql: str
    ) -> Dict[str, Any]:
        dialect = "sqlite" if conn.engine == "sqlite" else "postgres"
        from app.core.explain_inspector import explain_inspector

        is_safe, error_msg, sanitized_sql = guardrail.validate_and_sanitize(
            sql, dialect=dialect, enforce_limit=False
        )

        sql_upper = sql.upper()
        join_count = sql_upper.count(" JOIN ")
        has_subquery = ("SELECT" in sql_upper[sql_upper.find("SELECT")+6:]) or ("WITH " in sql_upper)
        has_groupby = "GROUP BY" in sql_upper
        has_orderby = "ORDER BY" in sql_upper
        has_limit = "LIMIT " in sql_upper

        explain_res = await explain_inspector.explain_query(conn, sql, analyze=False)

        risk_level = "LOW"
        risk_reasons = []

        if not is_safe:
            risk_level = "CRITICAL"
            risk_reasons.append(f"AST Guardrail: {error_msg}")
        elif explain_res.error:
            risk_level = "ERROR"
            risk_reasons.append(f"Query compilation error: {explain_res.error}")
        else:
            if explain_res.warnings:
                risk_level = "MEDIUM"
                risk_reasons.extend(explain_res.warnings)
            if not has_limit:
                risk_reasons.append("Missing LIMIT clause: query could fetch unbounded rows.")
                if risk_level == "LOW":
                    risk_level = "MEDIUM"
            if join_count >= 3:
                risk_reasons.append(f"High join count ({join_count} joins).")
                if risk_level == "LOW":
                    risk_level = "MEDIUM"

        return {
            "sql": sql,
            "is_safe": is_safe,
            "risk_level": risk_level,
            "risk_reasons": risk_reasons,
            "complexity": {
                "joins_count": join_count,
                "has_subquery": has_subquery,
                "has_group_by": has_groupby,
                "has_order_by": has_orderby,
                "has_limit": has_limit
            },
            "total_cost": explain_res.total_cost,
            "planning_time_ms": explain_res.planning_time_ms,
            "recommendations": explain_res.recommendations,
            "plan_tree": explain_res.plan_tree.to_dict() if explain_res.plan_tree else None
        }

    @classmethod
    async def run_async_streaming_query(
        cls,
        conn: ConnectionConfig,
        sql: str,
        chunk_size: int = 50,
        max_rows: int = 100
    ) -> Dict[str, Any]:
        dialect = "sqlite" if conn.engine == "sqlite" else "postgres"
        effective_max = min(max(1, max_rows), 200)
        effective_chunk = min(max(1, chunk_size), effective_max)

        is_safe, error_msg, sanitized_sql = guardrail.validate_and_sanitize(
            sql, dialect=dialect, enforce_limit=True, requested_limit=effective_max
        )
        if not is_safe:
            return {
                "success": False,
                "error": f"SECURITY GUARDRAIL BLOCKED: {error_msg}",
                "chunks_count": 0,
                "total_rows": 0
            }

        res = await db_manager.execute_query(conn, sanitized_sql, safe_mode=False)
        if res.error:
            return {
                "success": False,
                "error": res.error,
                "chunks_count": 0,
                "total_rows": 0
            }

        all_rows = res.rows or []
        chunks = []
        for i in range(0, len(all_rows), effective_chunk):
            chunks.append({
                "chunk_index": len(chunks) + 1,
                "rows_count": len(all_rows[i:i + effective_chunk]),
                "rows": all_rows[i:i + effective_chunk]
            })

        return {
            "success": True,
            "sql": sanitized_sql,
            "columns": res.columns,
            "total_rows": len(all_rows),
            "chunk_size": effective_chunk,
            "chunks_count": len(chunks),
            "execution_time_ms": res.execution_time_ms,
            "has_more": res.has_more,
            "chunks": chunks
        }

    @staticmethod
    def format_markdown_table(columns: List[str], rows: List[List[Any]], max_rows: int = 50) -> str:
        if not columns or not rows:
            return "*No data rows returned.*"

        header = "| " + " | ".join(str(c) for c in columns) + " |"
        separator = "| " + " | ".join(["---"] * len(columns)) + " |"

        table_rows = []
        for r in rows[:max_rows]:
            clean_cells = [
                str(c).replace("|", "\\|").replace("\n", " ") if c is not None else "*null*"
                for c in r
            ]
            table_rows.append("| " + " | ".join(clean_cells) + " |")

        res = "\n".join([header, separator] + table_rows)
        if len(rows) > max_rows:
            res += f"\n\n*(Showing first {max_rows} of {len(rows)} rows)*"
        return res

    @classmethod
    async def chat(
        cls,
        user_message: str,
        conversation_history: List[Dict[str, Any]],
        model: str = DEFAULT_MODEL,
        ollama_url: str = DEFAULT_OLLAMA_URL,
        persona: str = "standard",
        max_turns: int = 5
    ) -> Dict[str, Any]:
        """
        Executes an agent conversation turn with multi-turn tool calling against Ollama.
        """
        clean_url = lunar_normalize_ollama_url(ollama_url)
        resolved_model = lunar_resolve_model_name(model)
        system_prompt = AGENT_SYSTEM_PROMPT

        # Initialize messages with system prompt if absent
        messages: List[Dict[str, Any]] = []
        has_system = any(m.get("role") == "system" for m in conversation_history)
        if not has_system:
            messages.append({"role": "system", "content": system_prompt})

        messages.extend(conversation_history)
        messages.append({"role": "user", "content": user_message})

        executed_tools: List[Dict[str, Any]] = []
        turn_count = 0
        supports_tools = True

        async with httpx.AsyncClient(timeout=LUNAR_AGENT_TIMEOUT_SECONDS) as client:
            while turn_count < max_turns:
                turn_count += 1
                payload = {
                    "model": resolved_model,
                    "messages": messages,
                    "stream": False,
                    "options": {
                        "num_ctx": 8192
                    }
                }
                if supports_tools:
                    payload["tools"] = AGENT_TOOLS_SCHEMA

                try:
                    res = await client.post(f"{clean_url}/api/chat", json=payload)
                    if res.status_code != 200:
                        error_detail = res.text
                        err_lower = error_detail.lower()

                        # Case 1: Model does not support tools (HTTP 400). Auto-fallback without tools!
                        if supports_tools and ("does not support tools" in err_lower or "tools are not supported" in err_lower or ("tool" in err_lower and res.status_code == 400)):
                            supports_tools = False
                            retry_payload = {
                                "model": resolved_model,
                                "messages": messages,
                                "stream": False,
                                "options": {
                                    "num_ctx": 8192
                                }
                            }
                            retry_res = await client.post(f"{clean_url}/api/chat", json=retry_payload)
                            if retry_res.status_code == 200:
                                retry_data = retry_res.json()
                                retry_msg = retry_data.get("message", {})
                                messages.append(retry_msg)
                                notice_prefix = (
                                    f"> ℹ️ **Notice:** Model `{resolved_model}` does not support native function/tool calling in Ollama. "
                                    f"Operating in conversational & SQL assistance mode (database tools are disabled).\n\n"
                                )
                                return {
                                    "error": None,
                                    "content": notice_prefix + (retry_msg.get("content") or ""),
                                    "tool_executions": executed_tools,
                                    "history": messages
                                }
                            else:
                                error_detail = retry_res.text

                        if res.status_code == 404:
                            friendly_msg = (
                                f"Ollama returned HTTP 404 (Model '{resolved_model}' not found). "
                                f"Ensure Ollama is running with the proper model directory (e.g. OLLAMA_MODELS=/var/lib/ollama) "
                                f"and that '{resolved_model}' is pulled via 'ollama pull {resolved_model}'."
                            )
                        elif "does not support tools" in err_lower:
                            friendly_msg = (
                                f"Model '{resolved_model}' does not support tools/function calling in Ollama (HTTP 400). "
                                f"For automatic database queries and schema inspection tools, please switch to 'gemma4:e4b', 'qwen2.5:3b', or 'llama3.2:3b'."
                            )
                        else:
                            friendly_msg = f"Ollama connection error (HTTP {res.status_code}): {error_detail}"

                        return {
                            "error": f"Ollama returned HTTP {res.status_code}: {error_detail}",
                            "content": friendly_msg,
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
                    # Check if the user asked to fetch rows, but the agent stopped without executing a query!
                    u_lower = user_message.lower()
                    is_data_query = any(k in u_lower for k in ("first row", "first rows", "rows", "limit ", "give 10", "show 10", "top 10", "select ", "row of"))
                    has_executed_query = any(t.get("name") in ("execute_safe_query", "get_table_preview", "run_async_streaming_query") for t in executed_tools)

                    if is_data_query and not has_executed_query:
                        active_conn = settings_manager.get_active_connection()
                        if active_conn:
                            tables_from_tools = []
                            for et in executed_tools:
                                t_arg = et.get("arguments", {}).get("table_name")
                                if t_arg and t_arg not in tables_from_tools:
                                    tables_from_tools.append(t_arg)

                            synth = await cls.natural_language_to_sql(
                                active_conn,
                                query_intent=user_message,
                                target_tables=tables_from_tools or None
                            )

                            if synth.get("is_safe") and synth.get("sql"):
                                query_res = await db_manager.execute_query(active_conn, synth["sql"], safe_mode=True)
                                if query_res.error is None:
                                    query_dict = query_res.to_dict()
                                    query_dict["sql"] = synth["sql"]
                                    executed_tools.append({
                                        "name": "execute_safe_query",
                                        "arguments": {"sql": synth["sql"]},
                                        "output_preview": f"Retrieved {query_res.row_count} rows in {query_res.execution_time_ms:.1f}ms",
                                        "success": True,
                                        "data": query_dict
                                    })
                                    audit_broadcaster.record_event(
                                        AuditEvent(
                                            source="REVVAULT_AI_AGENT",
                                            action="execute_safe_query",
                                            sql=synth["sql"],
                                            status="ALLOWED",
                                            execution_time_ms=query_res.execution_time_ms,
                                            row_count=query_res.row_count,
                                            message=f"Agent executed predicted join query ({query_res.row_count} rows)"
                                        )
                                    )
                                    content = (
                                        f"I formulated and executed the query for you with auto-predicted join conditions:\n\n"
                                        f"```sql\n{synth['sql']}\n```\n\n"
                                        f"Retrieved **{query_res.row_count} rows** in **{query_res.execution_time_ms:.1f}ms**."
                                    )
                                    return {
                                        "error": None,
                                        "content": content,
                                        "tool_executions": executed_tools,
                                        "history": messages
                                    }

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

                    tool_result = await cls.execute_tool(fn_name, fn_args)
                    if isinstance(tool_result, ToolResult):
                        output_text = tool_result.output
                        success = tool_result.success
                        tool_data = tool_result.data
                    else:
                        output_text, success = tool_result
                        tool_data = None

                    executed_tools.append({
                        "name": fn_name,
                        "arguments": fn_args,
                        "output_preview": output_text[:200] + ("..." if len(output_text) > 200 else ""),
                        "success": success,
                        "data": tool_data
                    })

                    messages.append({
                        "role": "tool",
                        "content": output_text
                    })

            # If loop finished and user asked for data rows without query execution:
            u_lower = user_message.lower()
            is_data_query = any(k in u_lower for k in ("first row", "first rows", "rows", "limit ", "give 10", "show 10", "top 10", "select ", "row of"))
            has_executed_query = any(t.get("name") in ("execute_safe_query", "get_table_preview", "run_async_streaming_query") for t in executed_tools)
            if is_data_query and not has_executed_query:
                active_conn = settings_manager.get_active_connection()
                if active_conn:
                    tables_from_tools = []
                    for et in executed_tools:
                        t_arg = et.get("arguments", {}).get("table_name")
                        if t_arg and t_arg not in tables_from_tools:
                            tables_from_tools.append(t_arg)
                    synth = await cls.natural_language_to_sql(
                        active_conn,
                        query_intent=user_message,
                        target_tables=tables_from_tools or None
                    )
                    if synth.get("is_safe") and synth.get("sql"):
                        query_res = await db_manager.execute_query(active_conn, synth["sql"], safe_mode=True)
                        if query_res.error is None:
                            query_dict = query_res.to_dict()
                            query_dict["sql"] = synth["sql"]
                            executed_tools.append({
                                "name": "execute_safe_query",
                                "arguments": {"sql": synth["sql"]},
                                "output_preview": f"Retrieved {query_res.row_count} rows in {query_res.execution_time_ms:.1f}ms",
                                "success": True,
                                "data": query_dict
                            })
                            content = (
                                f"I formulated and executed the query for you with auto-predicted join conditions:\n\n"
                                f"```sql\n{synth['sql']}\n```\n\n"
                                f"Retrieved **{query_res.row_count} rows** in **{query_res.execution_time_ms:.1f}ms**."
                            )
                            return {
                                "error": None,
                                "content": content,
                                "tool_executions": executed_tools,
                                "history": messages
                            }

            # If loop finished without content
            final_content = messages[-1].get("content") or "Query executed and inspected."
            return {
                "error": None,
                "content": final_content,
                "tool_executions": executed_tools,
                "history": messages
            }

agent_service = AgentService()

# Backward compatibility aliases
AgentService.lunar_profile_data = AgentService.profile_data
AgentService.lunar_natural_language_to_sql = AgentService.natural_language_to_sql
AgentService.lunar_evaluate_and_plan_query = AgentService.evaluate_and_plan_query
AgentService.lunar_run_async_streaming_query = AgentService.run_async_streaming_query
AgentService.lunar_format_markdown_table = staticmethod(AgentService.format_markdown_table)
