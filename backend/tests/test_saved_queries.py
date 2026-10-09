import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.config import settings_manager, SavedQueryConfig

client = TestClient(app)

def test_saved_queries_crud(tmp_path, monkeypatch):
    # Override data dir for isolated testing
    test_manager = type(settings_manager)(data_dir=tmp_path)
    monkeypatch.setattr("app.api.routes_query.settings_manager", test_manager)

    # Initially empty
    response = client.get("/api/query/saved")
    assert response.status_code == 200
    assert response.json() == []

    # Create saved query
    payload = {
        "id": "q1",
        "title": "Active Users Query",
        "sql": "SELECT * FROM users WHERE status = 'active';",
        "description": "Fetches all active users",
        "builder_mode": "rawSql",
        "created_at": "2026-10-01T12:00:00Z"
    }
    response = client.post("/api/query/saved", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == "q1"
    assert data["title"] == "Active Users Query"

    # List saved queries
    response = client.get("/api/query/saved")
    assert response.status_code == 200
    queries = response.json()
    assert len(queries) == 1
    assert queries[0]["id"] == "q1"

    # Delete saved query
    response = client.delete("/api/query/saved/q1")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "deleted_id": "q1"}

    # Confirm deletion
    response = client.get("/api/query/saved")
    assert response.status_code == 200
    assert response.json() == []

def test_auto_cast_mismatched_sql():
    from app.core.db_manager import DatabaseManager
    sql = 'SELECT "ck".*, "u"."nama_user" FROM "rawat_inap_rme"."cara_keluar" ck LEFT JOIN "public"."users" u ON ck.kd_user = u.kd_user LIMIT 25;'
    casted = DatabaseManager._auto_cast_mismatched_sql(sql)
    assert 'ON ck.kd_user::text = u.kd_user::text' in casted

@pytest.mark.asyncio
async def test_explain_postgres_auto_cast_mismatched_sql(monkeypatch):
    from unittest.mock import AsyncMock, MagicMock
    from app.core.explain_inspector import explain_inspector
    from app.config import ConnectionConfig

    mock_conn = MagicMock()
    # First call raises operator does not exist error, second call succeeds with JSON plan
    call_count = 0
    async def fake_fetchval(query):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            raise Exception("operator does not exist: smallint = character varying\nHINT: No operator matches the given name and argument types.")
        return '[{"Plan": {"Node Type": "Seq Scan", "Relation Name": "cara_keluar", "Total Cost": 10.5}}]'

    mock_conn.fetchval = AsyncMock(side_effect=fake_fetchval)

    mock_pool = MagicMock()
    mock_pool.acquire.return_value.__aenter__ = AsyncMock(return_value=mock_conn)
    mock_pool.acquire.return_value.__aexit__ = AsyncMock(return_value=None)

    monkeypatch.setattr("app.core.db_manager.db_manager.get_pg_pool", AsyncMock(return_value=mock_pool))

    cfg = ConnectionConfig(
        id="pg_test",
        name="Postgres Test",
        engine="postgres",
        host="localhost",
        database="testdb"
    )
    sql = 'SELECT "ck".*, "u"."nama_user" FROM "rawat_inap_rme"."cara_keluar" ck LEFT JOIN "public"."users" u ON ck.kd_user = u.kd_user LIMIT 25;'
    res = await explain_inspector.explain_query(cfg, sql, analyze=False)

    assert res.error is None
    assert call_count == 2
    assert res.plan_tree.node_type == "Seq Scan"
    assert any("Datatype mismatch detected" in w for w in res.warnings)
    assert any("Add explicit type casts" in r for r in res.recommendations)


