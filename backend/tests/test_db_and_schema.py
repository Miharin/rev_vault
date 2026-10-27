import pytest
import tempfile
import os
import aiosqlite
from app.config import ConnectionConfig
from app.core.db_manager import db_manager
from app.core.schema_inspector import schema_inspector

@pytest.fixture
async def temp_sqlite_db():
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)

    # Initialize sample database tables
    async with aiosqlite.connect(path) as db:
        await db.execute("""
            CREATE TABLE users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT NOT NULL,
                name TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        await db.execute("""
            CREATE TABLE orders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                amount REAL,
                FOREIGN KEY (user_id) REFERENCES users (id)
            )
        """)
        await db.execute("INSERT INTO users (email, name) VALUES ('alice@relva.io', 'Alice')")
        await db.execute("INSERT INTO users (email, name) VALUES ('bob@relva.io', 'Bob')")
        await db.execute("INSERT INTO orders (user_id, amount) VALUES (1, 99.50)")
        await db.commit()

    conn_config = ConnectionConfig(
        id="test_sqlite",
        name="Test SQLite DB",
        engine="sqlite",
        filepath=path,
        is_active=True
    )

    yield conn_config

    if os.path.exists(path):
        os.remove(path)

@pytest.mark.asyncio
async def test_schema_inspector(temp_sqlite_db):
    tables = await schema_inspector.get_tables(temp_sqlite_db, include_views=True)
    table_names = [t.name for t in tables]
    assert "users" in table_names
    assert "orders" in table_names

    users_table = next(t for t in tables if t.name == "users")
    col_names = [c.name for c in users_table.columns]
    assert "id" in col_names
    assert "email" in col_names

@pytest.mark.asyncio
async def test_safe_query_execution(temp_sqlite_db):
    res = await db_manager.execute_query(temp_sqlite_db, "SELECT email, name FROM users ORDER BY id", safe_mode=True)
    assert res.error is None
    assert res.row_count == 2
    assert res.columns == ["email", "name"]
    assert res.rows[0] == ["alice@relva.io", "Alice"]

@pytest.mark.asyncio
async def test_destructive_query_intercepted(temp_sqlite_db):
    res = await db_manager.execute_query(temp_sqlite_db, "DROP TABLE orders", safe_mode=True)
    assert res.error is not None
    assert "GUARDRAIL BLOCKED" in res.error

@pytest.mark.asyncio
async def test_table_row_count(temp_sqlite_db):
    count = await db_manager.get_table_row_count(temp_sqlite_db, "main", "users")
    assert count == 2

def test_quote_table_name():
    from app.api.routes_query import quote_table_name
    assert quote_table_name("master.cppt_keperawatan", "postgres") == '"master"."cppt_keperawatan"'
    assert quote_table_name("users", "postgres") == '"users"'
    assert quote_table_name("main.users", "sqlite") == '`main`.`users`'

@pytest.mark.asyncio
async def test_foreign_key_and_relationships(temp_sqlite_db):
    tables = await schema_inspector.get_tables(temp_sqlite_db, include_views=False)
    orders_table = next(t for t in tables if t.name == "orders")
    assert len(orders_table.foreign_keys) == 1
    fk = orders_table.foreign_keys[0]
    assert fk.column_name == "user_id"
    assert fk.target_table == "users"
    assert fk.target_column == "id"

    # Column level link
    user_id_col = next(c for c in orders_table.columns if c.name == "user_id")
    assert user_id_col.foreign_key is not None
    assert user_id_col.foreign_key.target_table == "users"

    # Relationship graph
    relations = await schema_inspector.get_relationships(temp_sqlite_db)
    assert len(relations) == 1
    assert relations[0]["source_table"] == "orders"
    assert relations[0]["source_column"] == "user_id"
    assert relations[0]["target_table"] == "users"
    assert relations[0]["target_column"] == "id"

    # Format relations summary
    summary = schema_inspector.format_relations_summary(relations)
    assert summary["total_database_relations"] == 1
    assert summary["returned_relations_count"] == 1

    # Filter by source table
    orders_summary = schema_inspector.format_relations_summary(relations, table_name="orders")
    assert orders_summary["matched_relations_count"] == 1
    assert orders_summary["relations"][0]["source_table"] == "orders"

    # Filter by target table (incoming FK)
    users_summary = schema_inspector.format_relations_summary(relations, table_name="users")
    assert users_summary["matched_relations_count"] == 1
    assert users_summary["relations"][0]["target_table"] == "users"

    # Filter by nonexistent table
    empty_summary = schema_inspector.format_relations_summary(relations, table_name="missing_table")
    assert empty_summary["matched_relations_count"] == 0

@pytest.mark.asyncio
async def test_explain_query_inspector(temp_sqlite_db):
    from app.core.explain_inspector import explain_inspector
    res = await explain_inspector.explain_query(temp_sqlite_db, "SELECT * FROM orders WHERE user_id = 1")
    assert res.error is None
    assert res.engine == "sqlite"
    assert res.plan_tree is not None
    assert len(res.warnings) >= 1
    assert any("scan" in w.lower() for w in res.warnings)

@pytest.mark.asyncio
async def test_schema_cache_and_invalidation(temp_sqlite_db):
    schema_inspector.invalidate_cache()
    # First call populates cache
    tables1 = await schema_inspector.get_tables(temp_sqlite_db, include_views=True)
    cache_key = f"{temp_sqlite_db.id}_True"
    assert cache_key in schema_inspector._schema_cache
    # Second call returns cached list
    tables2 = await schema_inspector.get_tables(temp_sqlite_db, include_views=True)
    assert tables1 is tables2

    # Invalidation clears cache
    schema_inspector.invalidate_cache(temp_sqlite_db.id)
    assert cache_key not in schema_inspector._schema_cache

    # Refresh bypasses cache
    tables3 = await schema_inspector.get_tables(temp_sqlite_db, include_views=True, refresh=True)
    assert len(tables3) == len(tables1)


@pytest.mark.asyncio
async def test_row_mutation_update_and_delete(temp_sqlite_db):
    # Test update row
    update_res = await db_manager.execute_query(
        temp_sqlite_db,
        "UPDATE users SET name = 'Alice Updated' WHERE id = 1",
        safe_mode=False
    )
    assert update_res.error is None
    assert update_res.row_count == 1

    # Verify updated row persisted
    verify_res = await db_manager.execute_query(
        temp_sqlite_db,
        "SELECT name FROM users WHERE id = 1",
        safe_mode=True
    )
    assert verify_res.rows[0][0] == "Alice Updated"

    # Test delete row
    del_res = await db_manager.execute_query(
        temp_sqlite_db,
        "DELETE FROM users WHERE id = 2",
        safe_mode=False
    )
    assert del_res.error is None
    assert del_res.row_count == 1

    # Verify deleted row no longer exists
    count_res = await db_manager.execute_query(
        temp_sqlite_db,
        "SELECT COUNT(*) FROM users",
        safe_mode=True
    )
    assert count_res.rows[0][0] == 1


@pytest.mark.asyncio
async def test_schema_inspector_format_tables_summary(temp_sqlite_db):
    tables = await schema_inspector.get_tables(temp_sqlite_db, include_views=True)
    summary = schema_inspector.format_tables_summary(tables, limit=10)

    assert summary["total_database_tables"] == len(tables)
    assert "main" in summary["schemas_summary"]
    assert summary["matched_tables_count"] == len(tables)
    assert summary["returned_tables_count"] == len(tables)
    assert summary["has_more"] is False
    assert len(summary["tables"]) == len(tables)

    # Verify lightweight summary dictionary structure (no column bloat)
    first_tbl = summary["tables"][0]
    assert "name" in first_tbl
    assert "schema" in first_tbl
    assert "columns_count" in first_tbl
    assert "columns" not in first_tbl  # Must NOT leak heavy column details!

    # Test search filter
    filtered_summary = schema_inspector.format_tables_summary(tables, search="user")
    assert filtered_summary["matched_tables_count"] == 1
    assert filtered_summary["tables"][0]["name"] == "users"


def test_lunar_find_table_resolution():
    from app.core.schema_inspector import TableMetadata, ColumnMetadata
    tables = [
        TableMetadata(name="users", schema="public", raw_name="users"),
        TableMetadata(name="unit", schema="public", raw_name="unit"),
        TableMetadata(name="rawat_inap_rme.cara_keluar", schema="rawat_inap_rme", raw_name="cara_keluar")
    ]
    # Exact display name
    assert schema_inspector.lunar_find_table(tables, "users") is not None
    assert schema_inspector.lunar_find_table(tables, "users").raw_name == "users"

    # Schema-qualified display name
    assert schema_inspector.lunar_find_table(tables, "public.users") is not None
    assert schema_inspector.lunar_find_table(tables, "public.users").raw_name == "users"

    # Quoted schema-qualified name
    assert schema_inspector.lunar_find_table(tables, '"public"."unit"') is not None
    assert schema_inspector.lunar_find_table(tables, '"public"."unit"').raw_name == "unit"

    # Multi-schema table
    assert schema_inspector.lunar_find_table(tables, "rawat_inap_rme.cara_keluar") is not None
    assert schema_inspector.lunar_find_table(tables, "cara_keluar") is not None
    assert schema_inspector.lunar_find_table(tables, "non_existent") is None


def test_lunar_predict_join_condition():
    from app.core.schema_inspector import TableMetadata, ColumnMetadata, ForeignKeyMetadata
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
        name="users",
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
        name="unit",
        schema="public",
        raw_name="unit",
        columns=[
            ColumnMetadata(name="kd_unit", data_type="integer", is_primary_key=True),
            ColumnMetadata(name="nama_unit", data_type="varchar"),
        ]
    )

    # 1. Exact domain identifier intersection: cara_keluar and users (kd_user)
    pred_user = schema_inspector.lunar_predict_join_condition(t_cara_keluar, t_users, alias_a="c", alias_b="u")
    assert pred_user is not None
    assert pred_user["method"] == "EXACT_IDENTIFIER_MATCH"
    assert pred_user["on_clause"] == "c.kd_user = u.kd_user"

    # 2. Foreign Key catalog: users and unit (users.unit = unit.kd_unit)
    pred_unit = schema_inspector.lunar_predict_join_condition(t_users, t_unit, alias_a="u", alias_b="un")
    assert pred_unit is not None
    assert pred_unit["method"] == "FOREIGN_KEY_CATALOG"
    assert pred_unit["on_clause"] == "u.unit = un.kd_unit"

    # 3. Entity-code heuristic without explicit FK
    t_users_nofk = TableMetadata(
        name="users",
        schema="public",
        raw_name="users",
        columns=[
            ColumnMetadata(name="kd_user", data_type="smallint", is_primary_key=True),
            ColumnMetadata(name="unit", data_type="integer"),
        ]
    )
    pred_heuristic = schema_inspector.lunar_predict_join_condition(t_users_nofk, t_unit, alias_a="u", alias_b="un")
    assert pred_heuristic is not None
    assert "u.unit = un.kd_unit" in pred_heuristic["on_clause"]





