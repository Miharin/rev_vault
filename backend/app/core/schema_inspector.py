from typing import Dict, Any, List, Optional, Tuple
import time
import logging
import aiosqlite
import sqlglot
from sqlglot import exp
from app.config import ConnectionConfig
from app.core.db_manager import db_manager

logger = logging.getLogger("revvault.schema_inspector")

class ForeignKeyMetadata:
    def __init__(
        self,
        column_name: str,
        target_table: str,
        target_column: str,
        constraint_name: Optional[str] = None
    ):
        self.column_name = column_name
        self.target_table = target_table
        self.target_column = target_column
        self.constraint_name = constraint_name

    def to_dict(self) -> Dict[str, Any]:
        return {
            "column_name": self.column_name,
            "target_table": self.target_table,
            "target_column": self.target_column,
            "constraint_name": self.constraint_name,
        }

class ColumnMetadata:
    def __init__(
        self,
        name: str,
        data_type: str,
        is_nullable: bool = True,
        is_primary_key: bool = False,
        default_value: Optional[str] = None,
        foreign_key: Optional[ForeignKeyMetadata] = None,
        is_unique: bool = False
    ):
        self.name = name
        self.data_type = data_type
        self.is_nullable = is_nullable
        self.is_primary_key = is_primary_key
        self.default_value = default_value
        self.foreign_key = foreign_key
        self.is_unique = is_unique

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "data_type": self.data_type,
            "is_nullable": self.is_nullable,
            "is_primary_key": self.is_primary_key,
            "default_value": self.default_value,
            "foreign_key": self.foreign_key.to_dict() if self.foreign_key else None,
            "is_unique": self.is_unique,
        }

class TableMetadata:
    def __init__(
        self,
        name: str,
        schema: str = "main",
        table_type: str = "TABLE",
        raw_name: Optional[str] = None,
        columns: Optional[List[ColumnMetadata]] = None,
        foreign_keys: Optional[List[ForeignKeyMetadata]] = None
    ):
        self.name = name
        self.schema = schema
        self.raw_name = raw_name or (name.split(".", 1)[-1] if "." in name else name)
        self.table_type = table_type
        self.columns: List[ColumnMetadata] = columns or []
        self.foreign_keys: List[ForeignKeyMetadata] = foreign_keys or []

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "schema": self.schema,
            "raw_name": self.raw_name,
            "table_type": self.table_type,
            "columns": [c.to_dict() for c in self.columns],
            "foreign_keys": [fk.to_dict() for fk in self.foreign_keys],
        }

    def to_summary_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "schema": self.schema,
            "raw_name": self.raw_name,
            "table_type": self.table_type,
            "columns_count": len(self.columns),
        }

    def lunar_to_summary_dict(self) -> Dict[str, Any]:
        return self.to_summary_dict()

class SchemaInspector:
    def __init__(self):
        self._schema_cache: Dict[str, Tuple[float, List[TableMetadata]]] = {}
        self.CACHE_TTL: float = 60.0

    def format_tables_summary(
        self,
        tables: List[TableMetadata],
        schema: Optional[str] = None,
        search: Optional[str] = None,
        limit: Optional[int] = None
    ) -> Dict[str, Any]:
        """
        Formats table metadata into an ultra-efficient, lightweight summary payload.
        Includes database-wide schema distribution, filtered results, and total counts
        without polluting LLM context with thousands of column definitions.
        """
        schema_summary: Dict[str, int] = {}
        for t in tables:
            schema_summary[t.schema] = schema_summary.get(t.schema, 0) + 1

        filtered = tables
        if schema:
            target_schema = schema.strip().lower()
            filtered = [t for t in filtered if t.schema.lower() == target_schema]
        if search:
            target_search = search.strip().lower()
            filtered = [t for t in filtered if target_search in t.name.lower() or target_search in t.raw_name.lower()]

        total_matched = len(filtered)

        # When exploring a large database without specific filters, cap sample tables to 20
        # to ensure CPU LLM token generation completes in seconds rather than minutes.
        if limit is None and not schema and not search and total_matched > 30:
            effective_limit = 20
        else:
            effective_limit = limit

        if effective_limit is not None and effective_limit > 0:
            sliced = filtered[:effective_limit]
            has_more = total_matched > effective_limit
        else:
            sliced = filtered
            has_more = False

        return {
            "total_database_tables": len(tables),
            "schemas_summary": schema_summary,
            "matched_tables_count": total_matched,
            "returned_tables_count": len(sliced),
            "has_more": has_more,
            "schema_filter": schema,
            "search_filter": search,
            "tables": [t.to_summary_dict() for t in sliced]
        }

    def lunar_format_tables_summary(
        self,
        lunar_tables: List[TableMetadata],
        lunar_schema: Optional[str] = None,
        lunar_search: Optional[str] = None,
        lunar_limit: Optional[int] = 100
    ) -> Dict[str, Any]:
        return self.format_tables_summary(
            tables=lunar_tables,
            schema=lunar_schema,
            search=lunar_search,
            limit=lunar_limit
        )

    def format_relations_summary(
        self,
        relations: List[Dict[str, Any]],
        table_name: Optional[str] = None,
        schema: Optional[str] = None,
        search: Optional[str] = None,
        limit: Optional[int] = None
    ) -> Dict[str, Any]:
        """
        Formats Foreign Key relationships into an ultra-efficient, lightweight summary payload.
        Provides database-wide relationship counts, schema distribution, and filtered relation mappings
        without polluting LLM context with thousands of raw records.
        """
        schema_distribution: Dict[str, int] = {}
        for r in relations:
            src = r.get("source_table", "")
            s_schema = src.split(".")[0] if "." in src else "public"
            schema_distribution[s_schema] = schema_distribution.get(s_schema, 0) + 1

        filtered = relations

        if table_name:
            target_tbl = table_name.strip().lower()
            filtered = [
                r for r in filtered
                if r.get("source_table", "").lower() == target_tbl
                or r.get("source_table", "").split(".")[-1].lower() == target_tbl
                or r.get("target_table", "").lower() == target_tbl
                or r.get("target_table", "").split(".")[-1].lower() == target_tbl
            ]

        if schema:
            target_sch = schema.strip().lower()
            filtered = [
                r for r in filtered
                if (r.get("source_table", "").split(".")[0].lower() if "." in r.get("source_table", "") else "public") == target_sch
                or (r.get("target_table", "").split(".")[0].lower() if "." in r.get("target_table", "") else "public") == target_sch
            ]

        if search:
            target_search = search.strip().lower()
            filtered = [
                r for r in filtered
                if target_search in r.get("source_table", "").lower()
                or target_search in r.get("target_table", "").lower()
                or target_search in r.get("source_column", "").lower()
                or target_search in r.get("target_column", "").lower()
                or target_search in (r.get("constraint_name") or "").lower()
            ]

        total_matched = len(filtered)

        # When exploring database-wide relationships without specific filters,
        # cap sample relations to 25 to prevent context window overflow (e.g. 8192 tokens)
        if limit is None and not table_name and not schema and not search and total_matched > 30:
            effective_limit = 25
        else:
            effective_limit = limit

        if effective_limit is not None and effective_limit > 0:
            sliced = filtered[:effective_limit]
            has_more = total_matched > effective_limit
        else:
            sliced = filtered
            has_more = False

        note = None
        if has_more:
            note = (
                f"Showing {len(sliced)} of {total_matched} relations "
                f"(total in database: {len(relations)}). Specify 'table_name' "
                f"(e.g. 'users' or 'master.cara_keluar') or 'schema' to inspect specific connections."
            )

        return {
            "total_database_relations": len(relations),
            "schema_distribution": schema_distribution,
            "matched_relations_count": total_matched,
            "returned_relations_count": len(sliced),
            "has_more": has_more,
            "table_filter": table_name,
            "schema_filter": schema,
            "search_filter": search,
            "note": note,
            "relations": sliced
        }

    def lunar_format_relations_summary(
        self,
        lunar_relations: List[Dict[str, Any]],
        lunar_table_name: Optional[str] = None,
        lunar_schema: Optional[str] = None,
        lunar_search: Optional[str] = None,
        lunar_limit: Optional[int] = 50
    ) -> Dict[str, Any]:
        return self.format_relations_summary(
            relations=lunar_relations,
            table_name=lunar_table_name,
            schema=lunar_schema,
            search=lunar_search,
            limit=lunar_limit
        )

    def invalidate_cache(self, connection_id: Optional[str] = None) -> None:
        if connection_id:
            keys_to_remove = [k for k in self._schema_cache if k.startswith(f"{connection_id}_")]
            for k in keys_to_remove:
                self._schema_cache.pop(k, None)
        else:
            self._schema_cache.clear()

    async def get_tables(self, config: ConnectionConfig, include_views: bool = True, refresh: bool = False) -> List[TableMetadata]:
        cache_key = f"{config.id}_{include_views}"
        if not refresh and cache_key in self._schema_cache:
            ts, cached_tables = self._schema_cache[cache_key]
            if time.time() - ts < self.CACHE_TTL:
                return cached_tables

        tables: List[TableMetadata] = []
        if config.engine == "sqlite":
            tables = await self._get_sqlite_tables(config, include_views)
        elif config.engine == "postgres":
            tables = await self._get_postgres_tables(config, include_views)

        self._schema_cache[cache_key] = (time.time(), tables)
        return tables

    @staticmethod
    def find_table(tables: List[TableMetadata], table_name: str) -> Optional[TableMetadata]:
        """
        Locates a table across schema-qualified ('public.users', 'rawat_inap_rme.cara_keluar'),
        raw, display, or quoted formats.
        """
        if not table_name:
            return None
        norm = table_name.strip().strip('"').strip("'").strip('`').lower()
        parts = [p.strip().strip('"').strip("'").strip('`') for p in norm.split('.') if p.strip()]

        # 1. Exact match against display name, raw name, or full schema.raw_name
        for t in tables:
            t_full = f"{t.schema}.{t.raw_name}".lower()
            if norm in (t.name.lower(), t.raw_name.lower(), t_full):
                return t

        # 2. Schema-qualified matching: "public.users" -> schema="public", raw_name="users"
        if len(parts) >= 2:
            target_schema, target_raw = parts[-2], parts[-1]
            for t in tables:
                if t.schema.lower() == target_schema and t.raw_name.lower() == target_raw:
                    return t
        elif len(parts) == 1:
            target_raw = parts[0]
            for t in tables:
                if t.raw_name.lower() == target_raw:
                    return t
        return None

    @staticmethod
    def predict_join_condition(
        table_a: TableMetadata,
        table_b: TableMetadata,
        relations: Optional[List[Dict[str, Any]]] = None,
        alias_a: Optional[str] = None,
        alias_b: Optional[str] = None
    ) -> Optional[Dict[str, Any]]:
        """
        Determines the optimal JOIN ON condition between two tables by comparing their schemas.
        Priority:
        1. Catalog Foreign Keys (from either table's metadata or relationships graph)
        2. Domain identifier intersection (e.g., kd_user == kd_user, no_transaksi == no_transaksi)
        3. Entity-code heuristics (e.g., users.unit == unit.kd_unit or order.user_id == users.id)
        """
        a_alias = alias_a or table_a.raw_name[:1].lower()
        b_alias = alias_b or table_b.raw_name[:1].lower() + "2"
        if a_alias == b_alias:
            b_alias = a_alias + "2"

        a_names = {table_a.name.lower(), table_a.raw_name.lower(), f"{table_a.schema}.{table_a.raw_name}".lower()}
        b_names = {table_b.name.lower(), table_b.raw_name.lower(), f"{table_b.schema}.{table_b.raw_name}".lower()}

        # 1. Explicit Catalog Foreign Keys on Table A -> Table B
        for fk in table_a.foreign_keys:
            fk_target = fk.target_table.lower()
            if fk_target in b_names or fk_target.split('.')[-1] in b_names:
                return {
                    "method": "FOREIGN_KEY_CATALOG",
                    "confidence": 1.0,
                    "source_table": table_a.name,
                    "source_column": fk.column_name,
                    "target_table": table_b.name,
                    "target_column": fk.target_column,
                    "on_clause": f"{a_alias}.{fk.column_name} = {b_alias}.{fk.target_column}"
                }

        # Explicit Catalog Foreign Keys on Table B -> Table A
        for fk in table_b.foreign_keys:
            fk_target = fk.target_table.lower()
            if fk_target in a_names or fk_target.split('.')[-1] in a_names:
                return {
                    "method": "FOREIGN_KEY_CATALOG",
                    "confidence": 1.0,
                    "source_table": table_b.name,
                    "source_column": fk.column_name,
                    "target_table": table_a.name,
                    "target_column": fk.target_column,
                    "on_clause": f"{a_alias}.{fk.target_column} = {b_alias}.{fk.column_name}"
                }

        # Check in external relations list if provided
        if relations:
            for r in relations:
                src = r.get("source_table", "").lower()
                tgt = r.get("target_table", "").lower()
                if (src in a_names or src.split('.')[-1] in a_names) and (tgt in b_names or tgt.split('.')[-1] in b_names):
                    return {
                        "method": "FOREIGN_KEY_RELATION",
                        "confidence": 1.0,
                        "source_table": table_a.name,
                        "source_column": r["source_column"],
                        "target_table": table_b.name,
                        "target_column": r["target_column"],
                        "on_clause": f"{a_alias}.{r['source_column']} = {b_alias}.{r['target_column']}"
                    }
                if (src in b_names or src.split('.')[-1] in b_names) and (tgt in a_names or tgt.split('.')[-1] in a_names):
                    return {
                        "method": "FOREIGN_KEY_RELATION",
                        "confidence": 1.0,
                        "source_table": table_b.name,
                        "source_column": r["source_column"],
                        "target_table": table_a.name,
                        "target_column": r["target_column"],
                        "on_clause": f"{a_alias}.{r['target_column']} = {b_alias}.{r['source_column']}"
                    }

        # 2. Exact Domain Identifier Match (Intersection)
        ignored_cols = {
            "created_at", "updated_at", "date_created", "date_updated",
            "status_aktif", "status_hapus", "status_final", "status",
            "is_active", "is_deleted", "deleted_at", "flag", "keterangan",
            "note", "notes", "description"
        }

        a_cols = {c.name.lower(): c.name for c in table_a.columns}
        b_cols = {c.name.lower(): c.name for c in table_b.columns}
        common_cols = set(a_cols.keys()) & set(b_cols.keys()) - ignored_cols

        id_candidates = []
        for col in common_cols:
            score = 0
            if col.startswith("kd_"):
                score = 100
            elif col.startswith("no_"):
                score = 90
            elif col.endswith("_id") or col.endswith("_code"):
                score = 80
            elif col in ("id", "uuid", "single_id"):
                score = 70
            else:
                score = 10
            id_candidates.append((score, col))

        if id_candidates:
            id_candidates.sort(key=lambda x: x[0], reverse=True)
            best_col = id_candidates[0][1]
            orig_a = a_cols[best_col]
            orig_b = b_cols[best_col]
            return {
                "method": "EXACT_IDENTIFIER_MATCH",
                "confidence": 0.95,
                "source_table": table_a.name,
                "source_column": orig_a,
                "target_table": table_b.name,
                "target_column": orig_b,
                "on_clause": f"{a_alias}.{orig_a} = {b_alias}.{orig_b}"
            }

        # 3. Entity-Code Heuristics (e.g. Table A has 'unit', Table B has 'kd_unit' or 'id')
        raw_b = table_b.raw_name.lower()
        raw_a = table_a.raw_name.lower()

        b_ref_patterns = [raw_b, f"kd_{raw_b}", f"{raw_b}_id", f"id_{raw_b}"]
        for pattern in b_ref_patterns:
            if pattern in a_cols:
                pk_col = next((c.name for c in table_b.columns if c.is_primary_key), None)
                if pk_col and pk_col.lower() in b_cols:
                    return {
                        "method": "ENTITY_PREFIX_HEURISTIC",
                        "confidence": 0.90,
                        "source_table": table_a.name,
                        "source_column": a_cols[pattern],
                        "target_table": table_b.name,
                        "target_column": pk_col,
                        "on_clause": f"{a_alias}.{a_cols[pattern]} = {b_alias}.{pk_col}"
                    }
                b_pk_candidates = [f"kd_{raw_b}", "id", f"{raw_b}_id"]
                for b_cand in b_pk_candidates:
                    if b_cand in b_cols:
                        return {
                            "method": "ENTITY_PREFIX_HEURISTIC",
                            "confidence": 0.85,
                            "source_table": table_a.name,
                            "source_column": a_cols[pattern],
                            "target_table": table_b.name,
                            "target_column": b_cols[b_cand],
                            "on_clause": f"{a_alias}.{a_cols[pattern]} = {b_alias}.{b_cols[b_cand]}"
                        }

        a_ref_patterns = [raw_a, f"kd_{raw_a}", f"{raw_a}_id", f"id_{raw_a}"]
        for pattern in a_ref_patterns:
            if pattern in b_cols:
                pk_col = next((c.name for c in table_a.columns if c.is_primary_key), None)
                if pk_col and pk_col.lower() in a_cols:
                    return {
                        "method": "ENTITY_PREFIX_HEURISTIC",
                        "confidence": 0.90,
                        "source_table": table_a.name,
                        "source_column": pk_col,
                        "target_table": table_b.name,
                        "target_column": b_cols[pattern],
                        "on_clause": f"{a_alias}.{pk_col} = {b_alias}.{b_cols[pattern]}"
                    }
                a_pk_candidates = [f"kd_{raw_a}", "id", f"{raw_a}_id"]
                for a_cand in a_pk_candidates:
                    if a_cand in a_cols:
                        return {
                            "method": "ENTITY_PREFIX_HEURISTIC",
                            "confidence": 0.85,
                            "source_table": table_a.name,
                            "source_column": a_cols[a_cand],
                            "target_table": table_b.name,
                            "target_column": b_cols[pattern],
                            "on_clause": f"{a_alias}.{a_cols[a_cand]} = {b_alias}.{b_cols[pattern]}"
                        }

        return None

    async def auto_resolve_joins(self, conn: ConnectionConfig, sql: str) -> str:
        """
        Inspects SQL queries for any JOIN clauses lacking an ON/USING condition.
        Uses predict_join_condition to automatically predict and inject the ON condition
        based on active database schema relations and identifier matching.
        """
        if not sql or not (" JOIN " in sql.upper() or "\nJOIN " in sql.upper()):
            return sql

        dialect = "sqlite" if conn.engine == "sqlite" else "postgres"
        try:
            trimmed = sql.strip().rstrip(";")
            stmts = sqlglot.parse(trimmed, read=dialect)
            if not stmts:
                return sql

            stmt = stmts[0]
            joins = list(stmt.find_all(exp.Join))
            missing_joins = [j for j in joins if j.args.get("on") is None and j.args.get("using") is None]

            if not missing_joins:
                return sql

            tables = await self.get_tables(conn, include_views=True)
            relations = await self.get_relationships(conn)

            from_clause = stmt.find(exp.From)
            if not from_clause or not from_clause.this:
                return sql

            p_expr = from_clause.this
            p_name = f"{p_expr.db}.{p_expr.name}" if hasattr(p_expr, "db") and p_expr.db else (p_expr.name if hasattr(p_expr, "name") else str(p_expr))
            p_alias = p_expr.alias_or_name
            p_meta = self.find_table(tables, p_name)

            active_tables: List[Tuple[Optional[TableMetadata], str]] = [(p_meta, p_alias)]

            for j in joins:
                j_expr = j.this
                j_name = f"{j_expr.db}.{j_expr.name}" if hasattr(j_expr, "db") and j_expr.db else (j_expr.name if hasattr(j_expr, "name") else str(j_expr))
                j_alias = j_expr.alias_or_name
                j_meta = self.find_table(tables, j_name)

                if j.args.get("on") is None and j.args.get("using") is None:
                    if j_meta:
                        best_pred = None
                        for prev_meta, prev_alias in active_tables:
                            if not prev_meta:
                                continue
                            pred = self.predict_join_condition(
                                table_a=prev_meta,
                                table_b=j_meta,
                                relations=relations,
                                alias_a=prev_alias,
                                alias_b=j_alias
                            )
                            if pred:
                                if best_pred is None or pred.get("confidence", 0) > best_pred.get("confidence", 0):
                                    best_pred = pred

                        if best_pred:
                            j.set("on", sqlglot.parse_one(best_pred["on_clause"], read=dialect))
                        elif p_alias and j_alias:
                            j.set("on", sqlglot.parse_one(f"{p_alias}.id = {j_alias}.id", read=dialect))

                active_tables.append((j_meta, j_alias))

            return stmt.sql(dialect=dialect)
        except Exception as e:
            logger.warning(f"auto_resolve_joins failed to rewrite SQL: {e}")
            return sql

    async def describe_table(self, config: ConnectionConfig, table_name: str) -> Optional[TableMetadata]:
        tables = await self.get_tables(config, include_views=True)
        return self.find_table(tables, table_name)

    async def get_relationships(self, config: ConnectionConfig, refresh: bool = False) -> List[Dict[str, Any]]:
        tables: Optional[List[TableMetadata]] = None
        if not refresh:
            for iv in [False, True]:
                key = f"{config.id}_{iv}"
                if key in self._schema_cache:
                    ts, cached_tables = self._schema_cache[key]
                    if time.time() - ts < self.CACHE_TTL:
                        tables = cached_tables
                        break

        if tables is None:
            tables = await self.get_tables(config, include_views=False, refresh=refresh)

        relations: List[Dict[str, Any]] = []
        for t in tables:
            for fk in t.foreign_keys:
                relations.append({
                    "source_table": t.name,
                    "source_column": fk.column_name,
                    "target_table": fk.target_table,
                    "target_column": fk.target_column,
                    "constraint_name": fk.constraint_name,
                })
        return relations

    async def _get_sqlite_tables(self, config: ConnectionConfig, include_views: bool) -> List[TableMetadata]:
        if not config.filepath:
            return []

        tables: List[TableMetadata] = []
        types = "('table', 'view')" if include_views else "('table')"
        query = f"SELECT name, type FROM sqlite_master WHERE type IN {types} AND name NOT LIKE 'sqlite_%' ORDER BY name"

        async with aiosqlite.connect(config.filepath) as db:
            async with db.execute(query) as cursor:
                rows = await cursor.fetchall()
                for name, t_type in rows:
                    t_meta = TableMetadata(name=name, schema="main", table_type=t_type.upper())

                    # PRAGMA table_info(tableName) returns:
                    # (cid, name, type, notnull, dflt_value, pk)
                    async with db.execute(f"PRAGMA table_info('{name}')") as col_cursor:
                        col_rows = await col_cursor.fetchall()
                        for _, c_name, c_type, notnull, dflt, pk in col_rows:
                            col_meta = ColumnMetadata(
                                name=c_name,
                                data_type=c_type or "TEXT",
                                is_nullable=not bool(notnull),
                                is_primary_key=bool(pk),
                                default_value=str(dflt) if dflt is not None else None
                            )
                            t_meta.columns.append(col_meta)

                    # PRAGMA foreign_key_list(tableName) returns:
                    # (id, seq, table, from, to, on_update, on_delete, match)
                    try:
                        async with db.execute(f"PRAGMA foreign_key_list('{name}')") as fk_cursor:
                            fk_rows = await fk_cursor.fetchall()
                            for _, _, target_tbl, col_from, col_to, _, _, _ in fk_rows:
                                if col_from and target_tbl:
                                    fk_meta = ForeignKeyMetadata(
                                        column_name=col_from,
                                        target_table=target_tbl,
                                        target_column=col_to or "id"
                                    )
                                    t_meta.foreign_keys.append(fk_meta)
                                    # Link to column
                                    for col in t_meta.columns:
                                        if col.name.lower() == col_from.lower():
                                            col.foreign_key = fk_meta
                    except Exception:
                        pass

                    tables.append(t_meta)
        return tables

    async def _get_postgres_tables(self, config: ConnectionConfig, include_views: bool) -> List[TableMetadata]:
        pool = await db_manager.get_pg_pool(config)
        try:
            return await self._get_postgres_tables_pg_catalog(pool, include_views)
        except Exception:
            return await self._get_postgres_tables_information_schema(pool, include_views)

    async def _get_postgres_tables_pg_catalog(self, pool, include_views: bool) -> List[TableMetadata]:
        tables_map: Dict[str, TableMetadata] = {}

        # 1. Fetch tables and views directly from pg_class & pg_namespace
        relkinds = "('r', 'p', 'v', 'm')" if include_views else "('r', 'p')"
        tbl_query = f"""
            SELECT
                n.nspname AS table_schema,
                c.relname AS table_name,
                c.relkind AS relkind
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
              AND c.relkind IN {relkinds}
            ORDER BY n.nspname, c.relname
        """
        async with pool.acquire() as conn:
            rows = await conn.fetch(tbl_query)
            for r in rows:
                schema = r["table_schema"]
                raw_name = r["table_name"]
                t_type = "TABLE" if r["relkind"] in ('r', 'p') else "VIEW"
                name = f"{schema}.{raw_name}" if schema != "public" else raw_name
                tables_map[f"{schema}.{raw_name}"] = TableMetadata(
                    name=name,
                    schema=schema,
                    table_type=t_type,
                    raw_name=raw_name
                )

            if not tables_map:
                return []

            # 2. Fetch Primary Keys and Unique constraints in < 0.02s
            pk_map: Dict[str, set] = {}
            uniq_map: Dict[str, set] = {}
            constraint_query = """
                SELECT
                    n.nspname AS table_schema,
                    c.relname AS table_name,
                    a.attname AS column_name,
                    con.contype::text AS constraint_type
                FROM pg_constraint con
                JOIN pg_class c ON c.oid = con.conrelid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                JOIN LATERAL unnest(con.conkey) AS k(attnum) ON true
                JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = k.attnum
                WHERE con.contype IN ('p', 'u')
                  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
            """
            try:
                c_rows = await conn.fetch(constraint_query)
                for cr in c_rows:
                    key = f"{cr['table_schema']}.{cr['table_name']}"
                    c_type = str(cr["constraint_type"]).lower()
                    col = cr["column_name"]
                    if c_type in ('p', '112'):
                        pk_map.setdefault(key, set()).add(col)
                    elif c_type in ('u', '117'):
                        uniq_map.setdefault(key, set()).add(col)
            except Exception as e:
                logger.warning(f"Error querying pg_constraint: {e}")

            # 3. Fetch Columns in batch in < 0.08s
            col_query = f"""
                SELECT
                    n.nspname AS table_schema,
                    c.relname AS table_name,
                    a.attname AS column_name,
                    pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
                    NOT a.attnotnull AS is_nullable,
                    pg_get_expr(d.adbin, d.adrelid) AS column_default
                FROM pg_attribute a
                JOIN pg_class c ON c.oid = a.attrelid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
                WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
                  AND c.relkind IN {relkinds}
                  AND a.attnum > 0
                  AND NOT a.attisdropped
                ORDER BY n.nspname, c.relname, a.attnum
            """
            col_rows = await conn.fetch(col_query)
            for cr in col_rows:
                key = f"{cr['table_schema']}.{cr['table_name']}"
                if key in tables_map:
                    col_name = cr["column_name"]
                    is_pk = col_name in pk_map.get(key, set())
                    is_uniq = col_name in uniq_map.get(key, set())
                    col_meta = ColumnMetadata(
                        name=col_name,
                        data_type=cr["data_type"],
                        is_nullable=bool(cr["is_nullable"]),
                        is_primary_key=is_pk,
                        default_value=cr["column_default"],
                        is_unique=is_uniq
                    )
                    tables_map[key].columns.append(col_meta)

            # 4. Fetch Foreign Keys in < 0.03s
            fk_query = """
                SELECT
                    con.conname AS constraint_name,
                    src_ns.nspname AS table_schema,
                    src_cls.relname AS table_name,
                    src_att.attname AS column_name,
                    tgt_ns.nspname AS target_schema,
                    tgt_cls.relname AS target_table,
                    tgt_att.attname AS target_column
                FROM pg_constraint con
                JOIN pg_class src_cls ON src_cls.oid = con.conrelid
                JOIN pg_namespace src_ns ON src_ns.oid = src_cls.relnamespace
                JOIN pg_class tgt_cls ON tgt_cls.oid = con.confrelid
                JOIN pg_namespace tgt_ns ON tgt_ns.oid = tgt_cls.relnamespace
                JOIN LATERAL unnest(con.conkey, con.confkey) WITH ORDINALITY AS cols(src_attnum, tgt_attnum, ord) ON true
                JOIN pg_attribute src_att ON src_att.attrelid = con.conrelid AND src_att.attnum = cols.src_attnum
                JOIN pg_attribute tgt_att ON tgt_att.attrelid = con.confrelid AND tgt_att.attnum = cols.tgt_attnum
                WHERE con.contype = 'f'
                  AND src_ns.nspname NOT IN ('pg_catalog', 'information_schema')
                ORDER BY src_ns.nspname, src_cls.relname, cols.ord
            """
            try:
                fk_rows = await conn.fetch(fk_query)
                for fkr in fk_rows:
                    source_key = f"{fkr['table_schema']}.{fkr['table_name']}"
                    if source_key in tables_map:
                        target_sch = fkr["target_schema"]
                        target_tbl = fkr["target_table"]
                        target_display = f"{target_sch}.{target_tbl}" if target_sch != "public" else target_tbl
                        fk_meta = ForeignKeyMetadata(
                            column_name=fkr["column_name"],
                            target_table=target_display,
                            target_column=fkr["target_column"],
                            constraint_name=fkr["constraint_name"]
                        )
                        tables_map[source_key].foreign_keys.append(fk_meta)
                        for col in tables_map[source_key].columns:
                            if col.name == fkr["column_name"]:
                                col.foreign_key = fk_meta
            except Exception:
                pass

        return list(tables_map.values())

    async def _get_postgres_tables_information_schema(self, pool, include_views: bool) -> List[TableMetadata]:
        tables_map: Dict[str, TableMetadata] = {}

        table_types = "('BASE TABLE', 'VIEW')" if include_views else "('BASE TABLE')"
        query = f"""
            SELECT table_schema, table_name, table_type
            FROM information_schema.tables
            WHERE table_schema NOT IN ('information_schema', 'pg_catalog')
              AND table_type IN {table_types}
            ORDER BY table_schema, table_name
        """

        async with pool.acquire() as conn:
            rows = await conn.fetch(query)
            for r in rows:
                schema = r["table_schema"]
                raw_name = r["table_name"]
                t_type = "TABLE" if r["table_type"] == "BASE TABLE" else "VIEW"
                name = f"{schema}.{raw_name}" if schema != "public" else raw_name
                tables_map[f"{schema}.{raw_name}"] = TableMetadata(name=name, schema=schema, table_type=t_type, raw_name=raw_name)

            if tables_map:
                # 1. Fetch Primary Keys and Unique constraints
                pk_map: Dict[str, set] = {}
                uniq_map: Dict[str, set] = {}
                constraint_query = """
                    SELECT 
                        tc.table_schema,
                        tc.table_name,
                        kcu.column_name,
                        tc.constraint_type
                    FROM information_schema.table_constraints tc
                    JOIN information_schema.key_column_usage kcu 
                      ON tc.constraint_name = kcu.constraint_name 
                     AND tc.table_schema = kcu.table_schema
                    WHERE tc.constraint_type IN ('PRIMARY KEY', 'UNIQUE')
                      AND tc.table_schema NOT IN ('information_schema', 'pg_catalog')
                """
                try:
                    c_rows = await conn.fetch(constraint_query)
                    for cr in c_rows:
                        key = f"{cr['table_schema']}.{cr['table_name']}"
                        c_type = cr["constraint_type"]
                        col = cr["column_name"]
                        if c_type == "PRIMARY KEY":
                            pk_map.setdefault(key, set()).add(col)
                        elif c_type == "UNIQUE":
                            uniq_map.setdefault(key, set()).add(col)
                except Exception:
                    pass

                # 2. Fetch Columns
                col_query = """
                    SELECT 
                        table_schema,
                        table_name,
                        column_name,
                        data_type,
                        is_nullable,
                        column_default
                    FROM information_schema.columns
                    WHERE table_schema NOT IN ('information_schema', 'pg_catalog')
                    ORDER BY table_schema, table_name, ordinal_position
                """
                col_rows = await conn.fetch(col_query)
                for cr in col_rows:
                    key = f"{cr['table_schema']}.{cr['table_name']}"
                    if key in tables_map:
                        col_name = cr["column_name"]
                        is_pk = col_name in pk_map.get(key, set())
                        is_uniq = col_name in uniq_map.get(key, set())
                        col_meta = ColumnMetadata(
                            name=col_name,
                            data_type=cr["data_type"],
                            is_nullable=cr["is_nullable"] == "YES",
                            is_primary_key=is_pk,
                            default_value=cr["column_default"],
                            is_unique=is_uniq
                        )
                        tables_map[key].columns.append(col_meta)

                # 3. Fetch Foreign Keys
                fk_query = """
                    SELECT
                        tc.table_schema,
                        tc.table_name,
                        kcu.column_name,
                        ccu.table_schema AS target_schema,
                        ccu.table_name AS target_table,
                        ccu.column_name AS target_column,
                        tc.constraint_name
                    FROM information_schema.table_constraints AS tc
                    JOIN information_schema.key_column_usage AS kcu
                      ON tc.constraint_name = kcu.constraint_name
                     AND tc.table_schema = kcu.table_schema
                    JOIN information_schema.constraint_column_usage AS ccu
                      ON ccu.constraint_name = tc.constraint_name
                     AND ccu.table_schema = tc.table_schema
                    WHERE tc.constraint_type = 'FOREIGN KEY'
                      AND tc.table_schema NOT IN ('information_schema', 'pg_catalog')
                """
                try:
                    fk_rows = await conn.fetch(fk_query)
                    for fkr in fk_rows:
                        source_key = f"{fkr['table_schema']}.{fkr['table_name']}"
                        if source_key in tables_map:
                            target_sch = fkr["target_schema"]
                            target_tbl = fkr["target_table"]
                            target_display = f"{target_sch}.{target_tbl}" if target_sch != "public" else target_tbl
                            fk_meta = ForeignKeyMetadata(
                                column_name=fkr["column_name"],
                                target_table=target_display,
                                target_column=fkr["target_column"],
                                constraint_name=fkr["constraint_name"]
                            )
                            tables_map[source_key].foreign_keys.append(fk_meta)
                            for col in tables_map[source_key].columns:
                                if col.name == fkr["column_name"]:
                                    col.foreign_key = fk_meta
                except Exception:
                    pass

        return list(tables_map.values())

    async def inspect_schema(
        self,
        config: ConnectionConfig,
        table_name: Optional[str] = None,
        schema: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Deeply inspects complete schema metadata, columns, nullability,
        primary keys, foreign keys, inbound relationships, and indexes.
        """
        tables = await self.get_tables(config, include_views=True)
        all_relations = await self.get_relationships(config)

        if table_name:
            table = self.find_table(tables, table_name)
            if not table:
                return {
                    "found": False,
                    "error": f"Table '{table_name}' was not found in active database '{config.name}'."
                }

            schema_name = table.schema
            raw_table = table.raw_name

            # 1. Fetch indexes
            indexes: List[Dict[str, Any]] = []
            try:
                if config.engine == "sqlite" and config.filepath:
                    async with aiosqlite.connect(config.filepath) as db:
                        async with db.execute(f"PRAGMA index_list('{raw_table}')") as cur:
                            idx_rows = await cur.fetchall()
                            for idx_row in idx_rows:
                                idx_name = idx_row[1]
                                is_uniq = bool(idx_row[2])
                                cols: List[str] = []
                                try:
                                    async with db.execute(f"PRAGMA index_info('{idx_name}')") as c_cur:
                                        c_rows = await c_cur.fetchall()
                                        cols = [r[2] for r in c_rows]
                                except Exception:
                                    pass
                                indexes.append({
                                    "index_name": idx_name,
                                    "is_unique": is_uniq,
                                    "columns": cols
                                })
                elif config.engine == "postgres":
                    pool = await db_manager.get_pg_pool(config)
                    async with pool.acquire() as conn:
                        idx_q = """
                            SELECT indexname, indexdef
                            FROM pg_indexes
                            WHERE tablename = $1 AND schemaname = $2
                        """
                        idx_rows = await conn.fetch(idx_q, raw_table, schema_name)
                        for ir in idx_rows:
                            indexes.append({
                                "index_name": ir["indexname"],
                                "definition": ir["indexdef"]
                            })
            except Exception as e:
                logger.warning(f"Error fetching indexes for {table_name}: {e}")

            # 2. Fetch row count estimate
            row_count = await db_manager.get_table_row_count(config, schema_name, raw_table)

            # 3. Fetch inbound relations
            inbound_relations: List[Dict[str, Any]] = [
                r for r in all_relations
                if r.get("target_table", "").lower() == table.name.lower()
                or r.get("target_table", "").split(".")[-1].lower() == raw_table.lower()
            ]

            pks = [c.name for c in table.columns if c.is_primary_key]

            return {
                "found": True,
                "table_name": table.name,
                "schema": table.schema,
                "raw_name": table.raw_name,
                "table_type": table.table_type,
                "estimated_row_count": row_count,
                "columns_count": len(table.columns),
                "columns": [c.to_dict() for c in table.columns],
                "primary_keys": pks,
                "foreign_keys": [fk.to_dict() for fk in table.foreign_keys],
                "inbound_foreign_keys": inbound_relations,
                "indexes": indexes,
                "indexes_count": len(indexes)
            }

        # Schema-level or Database-level introspection
        filtered_tables = tables
        if schema:
            target_sch = schema.strip().lower()
            filtered_tables = [t for t in tables if t.schema.lower() == target_sch]

        schema_counts: Dict[str, int] = {}
        for t in tables:
            schema_counts[t.schema] = schema_counts.get(t.schema, 0) + 1

        return {
            "found": True,
            "database_name": config.name,
            "engine": config.engine,
            "target_schema": schema,
            "total_tables_in_database": len(tables),
            "schema_distribution": schema_counts,
            "matched_tables_count": len(filtered_tables),
            "tables": [
                {
                    "name": t.name,
                    "schema": t.schema,
                    "table_type": t.table_type,
                    "columns_count": len(t.columns),
                    "primary_keys": [c.name for c in t.columns if c.is_primary_key],
                    "foreign_keys_count": len(t.foreign_keys)
                }
                for t in filtered_tables
            ]
        }

schema_inspector = SchemaInspector()

# Backward compatibility aliases
SchemaInspector.lunar_find_table = staticmethod(SchemaInspector.find_table)
SchemaInspector.lunar_predict_join_condition = staticmethod(SchemaInspector.predict_join_condition)
SchemaInspector.lunar_auto_resolve_joins = SchemaInspector.auto_resolve_joins
SchemaInspector.lunar_inspect_schema = SchemaInspector.inspect_schema
