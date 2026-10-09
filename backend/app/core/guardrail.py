from typing import Tuple, Optional, List
import sqlglot
from sqlglot import exp
from app.config import GuardrailSettings, settings_manager

# AST Expression types that alter or manipulate data/schema destructively
DISALLOWED_AST_NODES = (
    exp.Delete,
    exp.Drop,
    exp.TruncateTable,
    exp.Insert,
    exp.Update,
    exp.Alter,
    exp.Create,
    exp.Command,
    exp.Grant,
    exp.Revoke,
    exp.Merge,
)

# AST Expression types permitted in read-only safe mode
ALLOWED_ROOT_NODES = (
    exp.Select,
    exp.Union,
)

class SQLGuardrail:
    def __init__(self, settings: Optional[GuardrailSettings] = None):
        self.settings = settings or settings_manager.load_guardrail_settings()
        self.last_effective_limit: Optional[int] = None
        self.last_offset: Optional[int] = None

    def parse_limit_and_offset(self, sql: str, dialect: str = "sqlite") -> Tuple[Optional[int], Optional[int]]:
        """Extracts existing LIMIT and OFFSET from SQL using AST parsing."""
        try:
            trimmed = sql.strip().rstrip(";")
            statements = sqlglot.parse(trimmed, read=dialect)
            if not statements:
                return None, None
            stmt = statements[0]
            limit_val: Optional[int] = None
            offset_val: Optional[int] = None

            current_limit = stmt.find(exp.Limit)
            if current_limit:
                expr = current_limit.expression
                limit_val = int(expr.this) if hasattr(expr, "this") else int(str(expr))

            current_offset = stmt.find(exp.Offset)
            if current_offset:
                expr = current_offset.expression
                offset_val = int(expr.this) if hasattr(expr, "this") else int(str(expr))

            return limit_val, offset_val
        except Exception:
            return None, None

    def validate_and_sanitize(
        self,
        sql: str,
        dialect: str = "sqlite",
        enforce_limit: bool = True,
        requested_limit: Optional[int] = None,
        probe_has_more: bool = False
    ) -> Tuple[bool, Optional[str], str]:
        """
        Parses SQL using AST and verifies safety.
        Returns:
            (is_safe, error_message, sanitized_or_limited_sql)
        """
        self.last_effective_limit = None
        self.last_offset = 0

        trimmed = sql.strip().rstrip(";")
        if not trimmed:
            return False, "Empty query", sql

        try:
            # sqlglot can parse multiple statements separated by ';'
            statements: List[exp.Expression] = sqlglot.parse(trimmed, read=dialect)
        except Exception as e:
            return False, f"SQL syntax parsing failed: {str(e)}", sql

        if not statements:
            return False, "No valid SQL expressions detected", sql

        sanitized_statements = []

        for stmt in statements:
            # Handle EXPLAIN command
            is_explain = False
            if isinstance(stmt, exp.Command) and str(stmt.this).upper() == "EXPLAIN":
                is_explain = True
                # Disallow any dangerous nodes in command
                for disallowed in (exp.Delete, exp.Drop, exp.TruncateTable, exp.Insert, exp.Update, exp.Alter, exp.Create, exp.Grant, exp.Revoke, exp.Merge):
                    if list(stmt.find_all(disallowed)):
                        return False, "GUARDRAIL BLOCKED: Destructive operations are not allowed even under EXPLAIN.", sql
                sanitized_statements.append(stmt.sql(dialect=dialect))
                continue

            # 1. Check for any disallowed AST nodes anywhere in the syntax tree
            for disallowed in DISALLOWED_AST_NODES:
                found = list(stmt.find_all(disallowed))
                if found:
                    node_name = disallowed.__name__
                    return (
                        False,
                        f"GUARDRAIL BLOCKED: Query contains prohibited operation '{node_name}'. "
                        "Destructive operations (DROP, DELETE, TRUNCATE, ALTER, UPDATE, INSERT) are disallowed.",
                        sql
                    )

            # 2. Check that root statement is an allowed read-only query
            if not isinstance(stmt, ALLOWED_ROOT_NODES):
                return (
                    False,
                    f"GUARDRAIL BLOCKED: Statement type '{type(stmt).__name__}' is not allowed in safe mode. "
                    "Only SELECT and EXPLAIN queries are permitted.",
                    sql
                )

            # Extract offset if present
            current_offset = stmt.find(exp.Offset)
            if current_offset:
                try:
                    expr = current_offset.expression
                    self.last_offset = int(expr.this) if hasattr(expr, "this") else int(str(expr))
                except Exception:
                    self.last_offset = 0

            # 3. Enforce / clamp row limit if it's a SELECT statement
            if enforce_limit and isinstance(stmt, (exp.Select, exp.Union)):
                # If requested_limit is -1, explicitly allow unbounded (no limit appended)
                if requested_limit == -1:
                    self.last_effective_limit = None
                else:
                    limit_to_apply = requested_limit or self.settings.default_row_limit
                    limit_to_apply = min(limit_to_apply, self.settings.max_row_limit)

                    # Check if statement already has a LIMIT clause
                    current_limit = stmt.find(exp.Limit)
                    if current_limit:
                        try:
                            expr = current_limit.expression
                            val = int(expr.this) if hasattr(expr, "this") else int(str(expr))
                            if val > self.settings.max_row_limit:
                                # Clamp to maximum allowable limit
                                val = self.settings.max_row_limit
                            self.last_effective_limit = val
                            exec_limit = (val + 1) if probe_has_more else val
                            current_limit.set("expression", exp.Literal.number(exec_limit))
                        except Exception:
                            self.last_effective_limit = limit_to_apply
                            exec_limit = (limit_to_apply + 1) if probe_has_more else limit_to_apply
                            current_limit.set("expression", exp.Literal.number(exec_limit))
                    else:
                        # Append LIMIT
                        self.last_effective_limit = limit_to_apply
                        exec_limit = (limit_to_apply + 1) if probe_has_more else limit_to_apply
                        stmt = stmt.limit(exec_limit)

            sanitized_statements.append(stmt.sql(dialect=dialect))

        final_sql = ";\n".join(sanitized_statements)
        return True, None, final_sql

guardrail = SQLGuardrail()
