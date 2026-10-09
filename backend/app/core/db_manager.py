import asyncio
import time
from typing import Dict, Any, List, Optional, Tuple
import aiosqlite
import asyncpg
from app.config import ConnectionConfig, settings_manager
from app.core.guardrail import guardrail

class QueryResult:
    def __init__(
        self,
        columns: List[str],
        rows: List[List[Any]],
        row_count: int,
        execution_time_ms: float,
        error: Optional[str] = None,
        total_rows: Optional[int] = None,
        page: Optional[int] = None,
        page_size: Optional[int] = None,
        has_more: Optional[bool] = None
    ):
        self.columns = columns
        self.rows = rows
        self.row_count = row_count
        self.execution_time_ms = execution_time_ms
        self.error = error
        self.total_rows = total_rows
        self.page = page
        self.page_size = page_size
        self.has_more = has_more

    def to_dict(self) -> Dict[str, Any]:
        return {
            "columns": self.columns,
            "rows": self.rows,
            "row_count": self.row_count,
            "execution_time_ms": round(self.execution_time_ms, 2),
            "error": self.error,
            "total_rows": self.total_rows,
            "page": self.page,
            "page_size": self.page_size,
            "has_more": self.has_more
        }

class DatabaseManager:
    def __init__(self):
        self._pg_pools: Dict[str, asyncpg.Pool] = {}

    async def test_connection(self, config: ConnectionConfig) -> Tuple[bool, str]:
        if config.engine == "sqlite":
            if not config.filepath:
                return False, "Filepath is required for SQLite connection."
            try:
                async with aiosqlite.connect(config.filepath) as db:
                    await db.execute("SELECT 1")
                return True, "Successfully connected to SQLite database."
            except Exception as e:
                return False, f"SQLite connection failed: {str(e)}"

        elif config.engine == "postgres":
            try:
                conn = await asyncpg.connect(
                    host=config.host or "localhost",
                    port=config.port or 5432,
                    user=config.username,
                    password=config.password,
                    database=config.database or "postgres",
                    ssl=config.ssl if config.ssl != "disable" else False,
                    timeout=5.0
                )
                await conn.fetchval("SELECT 1")
                dbs = await conn.fetch("SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname")
                db_list = [d["datname"] for d in dbs]
                await conn.close()
                return True, f"Connected successfully! Available databases: {', '.join(db_list)}"
            except Exception as e:
                return False, f"PostgreSQL connection failed: {str(e)}"
        else:
            return False, f"Unsupported database engine: {config.engine}"

    async def get_pg_pool(self, config: ConnectionConfig) -> asyncpg.Pool:
        if config.id not in self._pg_pools:
            self._pg_pools[config.id] = await asyncpg.create_pool(
                host=config.host or "localhost",
                port=config.port or 5432,
                user=config.username,
                password=config.password,
                database=config.database,
                ssl=config.ssl if config.ssl != "disable" else False,
                min_size=1,
                max_size=10
            )
        return self._pg_pools[config.id]

    async def execute_query(
        self,
        config: ConnectionConfig,
        sql: str,
        safe_mode: bool = True,
        requested_limit: Optional[int] = None,
        probe_has_more: bool = True
    ) -> QueryResult:
        dialect = "sqlite" if config.engine == "sqlite" else "postgres"
        effective_limit: Optional[int] = None
        offset: int = 0

        # Apply Guardrail if safe_mode is active
        if safe_mode:
            is_safe, error_msg, sanitized_sql = guardrail.validate_and_sanitize(
                sql, dialect=dialect, enforce_limit=True, requested_limit=requested_limit,
                probe_has_more=probe_has_more
            )
            if not is_safe:
                return QueryResult(
                    columns=[],
                    rows=[],
                    row_count=0,
                    execution_time_ms=0.0,
                    error=error_msg
                )
            query_to_run = sanitized_sql
            effective_limit = guardrail.last_effective_limit
            offset = guardrail.last_offset or 0
        else:
            query_to_run = sql
            effective_limit, parsed_offset = guardrail.parse_limit_and_offset(sql, dialect)
            offset = parsed_offset or 0

        start_time = time.perf_counter()

        try:
            if config.engine == "sqlite":
                result = await self._execute_sqlite(config, query_to_run, start_time)
            elif config.engine == "postgres":
                result = await self._execute_postgres(config, query_to_run, start_time)
            else:
                return QueryResult([], [], 0, 0.0, f"Unsupported engine: {config.engine}")
        except Exception as e:
            elapsed = (time.perf_counter() - start_time) * 1000.0
            return QueryResult([], [], 0, elapsed, f"Execution error: {str(e)}")

        # Post-process for limit / probe_has_more
        if effective_limit is not None and effective_limit > 0:
            if probe_has_more and len(result.rows) > effective_limit:
                result.rows = result.rows[:effective_limit]
                result.row_count = len(result.rows)
                result.has_more = True
            elif probe_has_more:
                result.has_more = False
            else:
                result.has_more = (len(result.rows) >= effective_limit)

            result.page_size = effective_limit
            result.page = (offset // effective_limit) + 1
        else:
            result.has_more = False

        return result

    async def _execute_sqlite(
        self,
        config: ConnectionConfig,
        sql: str,
        start_time: float
    ) -> QueryResult:
        if not config.filepath:
            return QueryResult([], [], 0, 0.0, "SQLite file path not configured")

        async with aiosqlite.connect(config.filepath) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(sql) as cursor:
                columns = [d[0] for d in cursor.description] if cursor.description else []
                rows_raw = await cursor.fetchall()
                elapsed = (time.perf_counter() - start_time) * 1000.0

                rows = [list(r) for r in rows_raw]
                return QueryResult(
                    columns=columns,
                    rows=rows,
                    row_count=len(rows),
                    execution_time_ms=elapsed
                )

    @staticmethod
    def _auto_cast_mismatched_sql(sql: str) -> str:
        """
        Safely rewrites comparison expressions (e.g., `ON colA = colB`) to `colA::text = colB::text`
        when PostgreSQL encounters a datatype mismatch operator error (e.g., `varchar = smallint`).
        """
        import re

        def _replacer(match):
            prefix = match.group(1)
            left = match.group(2).strip()
            right = match.group(3).strip()
            left_cast = left if ("::" in left or "CAST(" in left.upper()) else f"{left}::text"
            right_cast = right if ("::" in right or "CAST(" in right.upper()) else f"{right}::text"
            return f"{prefix}{left_cast} = {right_cast}"

        pattern = re.compile(
            r'(\bON\s+|\bAND\s+|\bWHERE\s+)([\w\."`]+)\s*=\s*([\w\."`]+)',
            re.IGNORECASE
        )
        return pattern.sub(_replacer, sql)

    async def _execute_postgres(
        self,
        config: ConnectionConfig,
        sql: str,
        start_time: float
    ) -> QueryResult:
        pool = await self.get_pg_pool(config)
        async with pool.acquire() as conn:
            target_sql = sql
            try:
                stmt = await conn.prepare(target_sql)
            except Exception as e:
                err_msg = str(e).lower()
                if "operator does not exist" in err_msg or "cannot be matched" in err_msg:
                    target_sql = self._auto_cast_mismatched_sql(sql)
                    if target_sql != sql:
                        stmt = await conn.prepare(target_sql)
                    else:
                        raise e
                else:
                    raise e

            try:
                columns = [attr.name for attr in stmt.get_attributes()]
                records = await stmt.fetch()
                elapsed = (time.perf_counter() - start_time) * 1000.0

                rows = []
                for record in records:
                    row_vals = []
                    for val in record.values():
                        # Ensure JSON serializable string representation for complex types
                        if isinstance(val, (bytes, bytearray)):
                            row_vals.append(val.hex())
                        else:
                            row_vals.append(str(val) if val is not None and not isinstance(val, (int, float, bool)) else val)
                    rows.append(row_vals)

                return QueryResult(
                    columns=columns,
                    rows=rows,
                    row_count=len(rows),
                    execution_time_ms=elapsed
                )
            except Exception as e:
                err_msg = str(e).lower()
                if "operator does not exist" in err_msg and target_sql == sql:
                    casted_sql = self._auto_cast_mismatched_sql(sql)
                    if casted_sql != sql:
                        stmt = await conn.prepare(casted_sql)
                        columns = [attr.name for attr in stmt.get_attributes()]
                        records = await stmt.fetch()
                        elapsed = (time.perf_counter() - start_time) * 1000.0
                        rows = []
                        for record in records:
                            row_vals = []
                            for val in record.values():
                                if isinstance(val, (bytes, bytearray)):
                                    row_vals.append(val.hex())
                                else:
                                    row_vals.append(str(val) if val is not None and not isinstance(val, (int, float, bool)) else val)
                            rows.append(row_vals)

                        return QueryResult(
                            columns=columns,
                            rows=rows,
                            row_count=len(rows),
                            execution_time_ms=elapsed
                        )
                raise e

    async def get_table_row_count(self, config: ConnectionConfig, schema: str, table: str) -> Optional[int]:
        try:
            if config.engine == "postgres":
                pool = await self.get_pg_pool(config)
                async with pool.acquire() as conn:
                    # Check reltuples from pg_class for quick estimate
                    est_query = """
                        SELECT c.reltuples::bigint AS est
                        FROM pg_class c
                        JOIN pg_namespace n ON n.oid = c.relnamespace
                        WHERE n.nspname = $1 AND c.relname = $2
                    """
                    row = await conn.fetchrow(est_query, schema, table)
                    if row and row["est"] is not None and row["est"] >= 0:
                        est = row["est"]
                        if est > 5000:
                            return est

                    count_row = await conn.fetchval(f'SELECT count(*) FROM "{schema}"."{table}"')
                    return int(count_row) if count_row is not None else 0
            elif config.engine == "sqlite":
                if not config.filepath:
                    return None
                async with aiosqlite.connect(config.filepath) as db:
                    async with db.execute(f"SELECT count(*) FROM `{table}`") as cursor:
                        row = await cursor.fetchone()
                        return int(row[0]) if row else 0
        except Exception:
            return None
        return None

db_manager = DatabaseManager()
