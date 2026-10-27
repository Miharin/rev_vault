import pytest
from app.core.agent_service import agent_service, DEFAULT_MODEL, DEFAULT_OLLAMA_URL, lunar_is_safe_model_entry
from app.api.routes_agent import AgentChatRequest, AgentChatResponse


# (__)
# (˶ᵔ ᵕ ᵔ˶) < "Lunar Territory."
# / >[CRIMSON+]> "Hands off, unless you're Miharin."

def test_lunar_is_safe_model_entry():
    # String tests
    assert lunar_is_safe_model_entry("gemma4:e4b") is True
    assert lunar_is_safe_model_entry("qwen2.5-coder:7b") is True
    assert lunar_is_safe_model_entry("mistral-unsafe:latest") is False
    assert lunar_is_safe_model_entry("mistral-unsafe:latest", lunar_include_unsafe=True) is True

    # Dict tests: name
    assert lunar_is_safe_model_entry({"name": "llama3:latest"}) is True
    assert lunar_is_safe_model_entry({"name": "llama3-unsafe:latest"}) is False
    assert lunar_is_safe_model_entry({"name": "llama3-unsafe:latest"}, lunar_include_unsafe=True) is True

    # Dict tests: details
    assert lunar_is_safe_model_entry({
        "name": "custom-model:latest",
        "details": {"family": "unsafe_family"}
    }) is False
    assert lunar_is_safe_model_entry({
        "name": "custom-model:latest",
        "details": {"families": ["llama", "unsafe_experimental"]}
    }) is False

    # Dict tests: flags/tags
    assert lunar_is_safe_model_entry({
        "name": "custom-model:latest",
        "flags": ["experimental", "unsafe"]
    }) is False
    assert lunar_is_safe_model_entry({
        "name": "custom-model:latest",
        "flags": "unsafe"
    }) is False

    # Dict tests: boolean flags
    assert lunar_is_safe_model_entry({
        "name": "custom-model:latest",
        "is_unsafe": True
    }) is False
    assert lunar_is_safe_model_entry({
        "name": "custom-model:latest",
        "unsafe": True
    }) is False
    assert lunar_is_safe_model_entry({
        "name": "custom-model:latest",
        "is_unsafe": True
    }, lunar_include_unsafe=True) is True


@pytest.mark.asyncio
async def test_agent_status_filters_unsafe_models(monkeypatch):
    class MockResponse:
        status_code = 200
        def json(self):
            return {
                "models": [
                    {"name": "gemma4:e4b", "details": {"family": "gemma"}},
                    {"name": "qwen2.5-coder:7b", "details": {"family": "qwen"}},
                    {"name": "rogue-unsafe:latest", "details": {"family": "llama"}},
                    {"name": "jailbreak:latest", "details": {"family": "unsafe"}},
                    {"name": "flagged-model:latest", "flags": ["unsafe"]},
                    {"name": "bool-unsafe:latest", "is_unsafe": True},
                ]
            }

    class MockAsyncClient:
        async def __aenter__(self):
            return self
        async def __aexit__(self, exc_type, exc_val, exc_tb):
            pass
        async def get(self, url):
            return MockResponse()

    import httpx2
    monkeypatch.setattr(httpx2, "AsyncClient", lambda **kwargs: MockAsyncClient())

    # Default: unsafe models filtered out
    status_safe = await agent_service.check_status(ollama_url="http://localhost:11434", include_unsafe=False)
    assert status_safe["online"] is True
    assert status_safe["models"] == ["gemma4:e4b", "qwen2.5-coder:7b"]

    # When include_unsafe=True: all models retained
    status_all = await agent_service.check_status(ollama_url="http://localhost:11434", include_unsafe=True)
    assert status_all["online"] is True
    assert len(status_all["models"]) == 6


@pytest.mark.asyncio
async def test_agent_status_structure():
    status = await agent_service.check_status(ollama_url=DEFAULT_OLLAMA_URL)
    assert "online" in status
    assert "models" in status
    assert status["default_model"] == DEFAULT_MODEL
    assert isinstance(status["models"], list)


from app.config import settings_manager
from tests.test_db_and_schema import temp_sqlite_db


@pytest.mark.asyncio
async def test_agent_tool_execution_safety(temp_sqlite_db, monkeypatch):
    monkeypatch.setattr(settings_manager, "get_active_connection", lambda: temp_sqlite_db)
    # Attempt dangerous destructive statement via execute_safe_query tool
    output, success = await agent_service.execute_tool(
        "execute_safe_query",
        {"sql": "DROP TABLE users;"}
    )
    assert success is False
    assert "SECURITY GUARDRAIL BLOCKED" in output


@pytest.mark.asyncio
async def test_agent_list_tables_execution(temp_sqlite_db, monkeypatch):
    import json
    monkeypatch.setattr(settings_manager, "get_active_connection", lambda: temp_sqlite_db)
    output, success = await agent_service.execute_tool(
        "list_tables",
        {"include_views": True, "limit": 50}
    )
    assert success is True
    data = json.loads(output)
    assert "total_database_tables" in data
    assert "schemas_summary" in data
    assert "tables" in data
    assert "returned_tables_count" in data
    if data["returned_tables_count"] > 0:
        tbl = data["tables"][0]
        assert "name" in tbl
        assert "schema" in tbl
        assert "columns_count" in tbl
        assert "columns" not in tbl  # Must be lightweight summary!


@pytest.mark.asyncio
async def test_agent_get_table_relations_execution(temp_sqlite_db, monkeypatch):
    import json
    monkeypatch.setattr(settings_manager, "get_active_connection", lambda: temp_sqlite_db)
    output, success = await agent_service.execute_tool(
        "get_table_relations",
        {}
    )
    assert success is True
    data = json.loads(output)
    assert "total_database_relations" in data
    assert "schema_distribution" in data
    assert "matched_relations_count" in data
    assert "returned_relations_count" in data
    assert "relations" in data
    assert data["total_database_relations"] == 1
    assert data["returned_relations_count"] == 1
    rel = data["relations"][0]
    assert rel["source_table"] == "orders"
    assert rel["source_column"] == "user_id"
    assert rel["target_table"] == "users"
    assert rel["target_column"] == "id"


@pytest.mark.asyncio
async def test_agent_get_table_relations_with_filters(temp_sqlite_db, monkeypatch):
    import json
    monkeypatch.setattr(settings_manager, "get_active_connection", lambda: temp_sqlite_db)
    
    # Test filtering by source table
    output, success = await agent_service.execute_tool(
        "get_table_relations",
        {"table_name": "orders"}
    )
    assert success is True
    data = json.loads(output)
    assert data["matched_relations_count"] == 1
    assert data["relations"][0]["source_table"] == "orders"

    # Test filtering by target table (incoming FKs)
    output_users, success = await agent_service.execute_tool(
        "get_table_relations",
        {"table_name": "users"}
    )
    assert success is True
    data_users = json.loads(output_users)
    assert data_users["matched_relations_count"] == 1
    assert data_users["relations"][0]["target_table"] == "users"

    # Test filtering by nonexistent table
    output_none, success = await agent_service.execute_tool(
        "get_table_relations",
        {"table_name": "nonexistent"}
    )
    assert success is True
    data_none = json.loads(output_none)
    assert data_none["matched_relations_count"] == 0
    assert len(data_none["relations"]) == 0


def test_agent_system_prompt_join_and_table_rules():
    from app.core.agent_service import AGENT_SYSTEM_PROMPT, LUNAR_AGENT_SYSTEM_PROMPT
    assert AGENT_SYSTEM_PROMPT == LUNAR_AGENT_SYSTEM_PROMPT
    assert "RevVault AI Database Assistant" in AGENT_SYSTEM_PROMPT
    assert "AESTHETIC PRESENTATION & REAL DATA TABLES" in AGENT_SYSTEM_PROMPT
    assert "SQL GENERATION & RELATIONAL JOIN RULES" in AGENT_SYSTEM_PROMPT
    assert "<main_table>.*" in AGENT_SYSTEM_PROMPT
    assert "JOINED TABLE SPECIFIC KEYS" in AGENT_SYSTEM_PROMPT


@pytest.mark.asyncio
async def test_agent_inspect_schema_tool(temp_sqlite_db, monkeypatch):
    import json
    monkeypatch.setattr(settings_manager, "get_active_connection", lambda: temp_sqlite_db)
    output, success = await agent_service.execute_tool(
        "inspect_schema",
        {"table_name": "users"}
    )
    assert success is True
    data = json.loads(output)
    assert data["found"] is True
    assert data["table_name"] == "users"
    assert data["columns_count"] >= 3
    assert "id" in data["primary_keys"]
    assert "indexes" in data
    assert "inbound_foreign_keys" in data
    assert len(data["inbound_foreign_keys"]) == 1
    assert data["inbound_foreign_keys"][0]["source_table"] == "orders"


@pytest.mark.asyncio
async def test_agent_explain_query_plan_tool(temp_sqlite_db, monkeypatch):
    import json
    monkeypatch.setattr(settings_manager, "get_active_connection", lambda: temp_sqlite_db)
    output, success = await agent_service.execute_tool(
        "explain_query_plan",
        {"sql": "SELECT * FROM users WHERE id = 1;"}
    )
    assert success is True
    data = json.loads(output)
    assert data["engine"] == "sqlite"
    assert "plan_tree" in data
    assert "planning_time_ms" in data


@pytest.mark.asyncio
async def test_agent_data_profiling_tool(temp_sqlite_db, monkeypatch):
    import json
    monkeypatch.setattr(settings_manager, "get_active_connection", lambda: temp_sqlite_db)
    output, success = await agent_service.execute_tool(
        "data_profilling",
        {"table_name": "users"}
    )
    assert success is True
    data = json.loads(output)
    assert data["table_name"] == "users"
    assert data["total_rows"] == 2
    assert len(data["columns"]) >= 3
    # Check column null and distinct stats
    id_col = next(c for c in data["columns"] if c["column"] == "id")
    assert id_col["null_count"] == 0
    assert id_col["distinct_count"] == 2


@pytest.mark.asyncio
async def test_agent_natural_language_to_sql_tool(temp_sqlite_db, monkeypatch):
    import json
    monkeypatch.setattr(settings_manager, "get_active_connection", lambda: temp_sqlite_db)
    output, success = await agent_service.execute_tool(
        "natural_language_to_sql",
        {"query_intent": "find users with their orders", "target_tables": ["users", "orders"]}
    )
    assert success is True
    data = json.loads(output)
    assert data["is_safe"] is True
    assert "SELECT" in data["sql"]
    assert "users" in data["sql"].lower()
    assert "orders" in data["sql"].lower()
    assert "JOIN" in data["sql"]


@pytest.mark.asyncio
async def test_agent_evaluate_and_plan_query_tool(temp_sqlite_db, monkeypatch):
    import json
    monkeypatch.setattr(settings_manager, "get_active_connection", lambda: temp_sqlite_db)
    output, success = await agent_service.execute_tool(
        "evaluate_and_plan_query",
        {"sql": "SELECT u.id, o.amount FROM users u JOIN orders o ON u.id = o.user_id LIMIT 10;"}
    )
    assert success is True
    data = json.loads(output)
    assert data["is_safe"] is True
    assert data["risk_level"] in ("LOW", "MEDIUM")
    assert data["complexity"]["joins_count"] == 1
    assert data["complexity"]["has_limit"] is True


@pytest.mark.asyncio
async def test_agent_run_async_streaming_query_tool(temp_sqlite_db, monkeypatch):
    import json
    monkeypatch.setattr(settings_manager, "get_active_connection", lambda: temp_sqlite_db)
    output, success = await agent_service.execute_tool(
        "run_async_streaming_query",
        {"sql": "SELECT * FROM users;", "chunk_size": 1, "max_rows": 10}
    )
    assert success is True
    data = json.loads(output)
    assert data["success"] is True
    assert data["total_rows"] == 2
    assert data["chunk_size"] == 1
    assert data["chunks_count"] == 2
    assert len(data["chunks"]) == 2
    assert data["chunks"][0]["rows_count"] == 1


@pytest.mark.asyncio
async def test_lunar_natural_language_to_sql_multi_join_and_projections(monkeypatch):
    from app.core.schema_inspector import TableMetadata, ColumnMetadata, ForeignKeyMetadata, schema_inspector
    from app.config import ConnectionConfig

    t_cara_keluar = TableMetadata(
        name="rawat_inap_rme.cara_keluar",
        schema="rawat_inap_rme",
        raw_name="cara_keluar",
        columns=[
            ColumnMetadata(name="counter", data_type="integer"),
            ColumnMetadata(name="kd_user", data_type="varchar"),
            ColumnMetadata(name="cara_keluar", data_type="varchar"),
        ]
    )
    t_users = TableMetadata(
        name="public.users",
        schema="public",
        raw_name="users",
        columns=[
            ColumnMetadata(name="kd_user", data_type="smallint", is_primary_key=True),
            ColumnMetadata(name="nama_user", data_type="varchar"),
            ColumnMetadata(name="unit", data_type="integer"),
        ],
        foreign_keys=[
            ForeignKeyMetadata(column_name="unit", target_table="unit", target_column="kd_unit")
        ]
    )
    t_unit = TableMetadata(
        name="public.unit",
        schema="public",
        raw_name="unit",
        columns=[
            ColumnMetadata(name="kd_unit", data_type="integer", is_primary_key=True),
            ColumnMetadata(name="nama_unit", data_type="varchar"),
        ]
    )

    mock_conn = ConnectionConfig(id="test_pg", name="Test PG", engine="postgres")
    async def mock_get_tables(conn, include_views=True, refresh=False):
        return [t_cara_keluar, t_users, t_unit]
    monkeypatch.setattr(schema_inspector, "get_tables", mock_get_tables)

    prompt = "give 10 first row of rawat_inap_rme.cara_keluar join public.users and public.unit and in users show only name, and in the unit show nama_unit"
    res = await agent_service.lunar_natural_language_to_sql(mock_conn, prompt)

    assert res["is_safe"] is True
    assert res["tables_used"] == ["rawat_inap_rme.cara_keluar", "public.users", "public.unit"]
    sql_lower = res["sql"].lower()
    assert "kd_user" in sql_lower
    assert "nama_unit" in sql_lower
    assert "limit 10" in sql_lower


@pytest.mark.asyncio
async def test_lunar_auto_resolve_joins_syntax(monkeypatch):
    from app.core.schema_inspector import TableMetadata, ColumnMetadata, ForeignKeyMetadata, schema_inspector
    from app.config import ConnectionConfig

    t_cara_keluar = TableMetadata(
        name="rawat_inap_rme.cara_keluar",
        schema="rawat_inap_rme",
        raw_name="cara_keluar",
        columns=[
            ColumnMetadata(name="counter", data_type="integer"),
            ColumnMetadata(name="kd_user", data_type="varchar"),
            ColumnMetadata(name="cara_keluar", data_type="varchar"),
        ]
    )
    t_users = TableMetadata(
        name="public.users",
        schema="public",
        raw_name="users",
        columns=[
            ColumnMetadata(name="kd_user", data_type="smallint", is_primary_key=True),
            ColumnMetadata(name="nama_user", data_type="varchar"),
            ColumnMetadata(name="unit", data_type="integer"),
        ],
        foreign_keys=[
            ForeignKeyMetadata(column_name="unit", target_table="unit", target_column="kd_unit")
        ]
    )
    t_unit = TableMetadata(
        name="public.unit",
        schema="public",
        raw_name="unit",
        columns=[
            ColumnMetadata(name="kd_unit", data_type="integer", is_primary_key=True),
            ColumnMetadata(name="nama_unit", data_type="varchar"),
        ]
    )

    mock_conn = ConnectionConfig(id="test_pg", name="Test PG", engine="postgres")
    async def mock_get_tables_2(conn, include_views=True, refresh=False):
        return [t_cara_keluar, t_users, t_unit]
    monkeypatch.setattr(schema_inspector, "get_tables", mock_get_tables_2)

    raw_sql = "SELECT c.*, u.nama_user, un.nama_unit FROM rawat_inap_rme.cara_keluar c JOIN public.users u JOIN public.unit un LIMIT 10"
    resolved_sql = await schema_inspector.lunar_auto_resolve_joins(mock_conn, raw_sql)

    assert "c.kd_user = u.kd_user" in resolved_sql
    assert "u.unit = un.kd_unit" in resolved_sql


def test_lunar_format_markdown_table():
    cols = ["id", "name", "notes"]
    rows = [
        [1, "Alice", "Line1\nLine2"],
        [2, "Bob", "Pipe | Test"]
    ]
    md = agent_service.lunar_format_markdown_table(cols, rows)
    assert "| id | name | notes |" in md
    assert "| 1 | Alice | Line1 Line2 |" in md
    assert "| 2 | Bob | Pipe \\| Test |" in md


@pytest.mark.asyncio
async def test_agent_execute_safe_query_zero_token_structured_data(temp_sqlite_db, monkeypatch):
    import json
    monkeypatch.setattr(settings_manager, "get_active_connection", lambda: temp_sqlite_db)
    
    # execute_safe_query against users table
    tool_res = await agent_service.execute_tool(
        "execute_safe_query",
        {"sql": "SELECT * FROM users;"}
    )
    
    # Backward-compatible 2-tuple unpacking
    output, success = tool_res
    assert success is True
    
    # Verify lightweight LLM summary output to save tokens
    llm_payload = json.loads(output)
    assert llm_payload["status"] == "success"
    assert llm_payload["row_count"] == 2
    assert "columns" in llm_payload
    assert "client_delivery" in llm_payload
    
    # Verify structured data carries complete rows and columns for UI Data Matrix
    structured_data = getattr(tool_res, "data", None)
    assert structured_data is not None
    assert structured_data["row_count"] == 2
    assert "id" in structured_data["columns"]
    assert len(structured_data["rows"]) == 2



