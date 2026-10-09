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



