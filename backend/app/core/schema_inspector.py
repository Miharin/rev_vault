from typing import Dict, Any, List, Optional, Tuple
import time
import logging
import aiosqlite
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
        is_nullable: bool,
        is_primary_key: bool,
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
    def __init__(self, name: str, schema: str = "main", table_type: str = "TABLE", raw_name: Optional[str] = None):
        self.name = name
        self.schema = schema
        self.raw_name = raw_name or (name.split(".", 1)[-1] if "." in name else name)
        self.table_type = table_type
        self.columns: List[ColumnMetadata] = []
        self.foreign_keys: List[ForeignKeyMetadata] = []

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "schema": self.schema,
            "raw_name": self.raw_name,
            "table_type": self.table_type,
            "columns": [c.to_dict() for c in self.columns],
            "foreign_keys": [fk.to_dict() for fk in self.foreign_keys],
        }

class SchemaInspector:
    def __init__(self):
        self._schema_cache: Dict[str, Tuple[float, List[TableMetadata]]] = {}
        self.CACHE_TTL: float = 60.0

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

    async def describe_table(self, config: ConnectionConfig, table_name: str) -> Optional[TableMetadata]:
        tables = await self.get_tables(config, include_views=True)
        target = next((t for t in tables if t.name.lower() == table_name.lower() or t.raw_name.lower() == table_name.lower()), None)
        return target

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

schema_inspector = SchemaInspector()
