import pytest
from app.core.guardrail import SQLGuardrail
from app.config import GuardrailSettings

@pytest.fixture
def guard():
    settings = GuardrailSettings(default_row_limit=50, max_row_limit=100)
    return SQLGuardrail(settings)

def test_safe_select_passes(guard):
    sql = "SELECT id, name FROM users WHERE active = 1"
    is_safe, error, sanitized = guard.validate_and_sanitize(sql, dialect="sqlite")
    assert is_safe is True
    assert error is None
    assert "LIMIT 50" in sanitized.upper()

def test_explain_passes(guard):
    sql = "EXPLAIN SELECT * FROM orders"
    is_safe, error, sanitized = guard.validate_and_sanitize(sql, dialect="sqlite")
    assert is_safe is True
    assert error is None

def test_drop_table_blocked(guard):
    sql = "DROP TABLE users"
    is_safe, error, _ = guard.validate_and_sanitize(sql, dialect="sqlite")
    assert is_safe is False
    assert "GUARDRAIL BLOCKED" in error
    assert "Drop" in error

def test_delete_blocked(guard):
    sql = "DELETE FROM users WHERE id = 1"
    is_safe, error, _ = guard.validate_and_sanitize(sql, dialect="sqlite")
    assert is_safe is False
    assert "GUARDRAIL BLOCKED" in error
    assert "Delete" in error

def test_truncate_blocked(guard):
    sql = "TRUNCATE TABLE logs"
    is_safe, error, _ = guard.validate_and_sanitize(sql, dialect="postgres")
    assert is_safe is False
    assert "GUARDRAIL BLOCKED" in error

def test_alter_table_blocked(guard):
    sql = "ALTER TABLE users ADD COLUMN secret_key TEXT"
    is_safe, error, _ = guard.validate_and_sanitize(sql, dialect="sqlite")
    assert is_safe is False
    assert "GUARDRAIL BLOCKED" in error

def test_multi_statement_injection_blocked(guard):
    sql = "SELECT 1; DROP TABLE users;"
    is_safe, error, _ = guard.validate_and_sanitize(sql, dialect="sqlite")
    assert is_safe is False
    assert "Multi-statement" in error or "GUARDRAIL BLOCKED" in error

def test_limit_clamping(guard):
    sql = "SELECT * FROM large_table LIMIT 5000"
    is_safe, error, sanitized = guard.validate_and_sanitize(sql, dialect="sqlite")
    assert is_safe is True
    # Clamped to max_row_limit = 100
    assert "100" in sanitized
    assert "5000" not in sanitized

def test_probe_has_more_increments_limit(guard):
    sql = "SELECT * FROM users LIMIT 25 OFFSET 50"
    is_safe, error, sanitized = guard.validate_and_sanitize(sql, dialect="sqlite", probe_has_more=True)
    assert is_safe is True
    assert "LIMIT 26" in sanitized
    assert "OFFSET 50" in sanitized
    assert guard.last_effective_limit == 25
    assert guard.last_offset == 50

def test_parse_limit_and_offset(guard):
    limit, offset = guard.parse_limit_and_offset("SELECT * FROM products LIMIT 100 OFFSET 200;")
    assert limit == 100
    assert offset == 200

