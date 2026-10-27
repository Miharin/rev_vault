from fastapi import APIRouter, HTTPException
from typing import List, Dict, Any, Optional
from pydantic import BaseModel
from app.config import settings_manager
from app.core.schema_inspector import schema_inspector

router = APIRouter(prefix="/api/schema", tags=["Schema"])

@router.get("", response_model=List[Dict[str, Any]])
async def get_schema(include_views: bool = True, refresh: bool = False):
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=400, detail="No active database connection configured")
    tables = await schema_inspector.get_tables(conn, include_views=include_views, refresh=refresh)
    return [t.to_dict() for t in tables]

@router.get("/table/{table_name}")
async def describe_table(table_name: str):
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=400, detail="No active database connection configured")
    t = await schema_inspector.describe_table(conn, table_name)
    if not t:
        raise HTTPException(status_code=404, detail=f"Table '{table_name}' not found")
    return t.to_dict()

@router.get("/relationships", response_model=List[Dict[str, Any]])
async def get_relationships(
    refresh: bool = False,
    table: Optional[str] = None,
    schema: Optional[str] = None
):
    """
    Returns detected Foreign Key entity relationships across active database tables.
    Supports optional filtering by table name or schema.
    """
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=400, detail="No active database connection configured")
    relations = await schema_inspector.get_relationships(conn, refresh=refresh)
    if table or schema:
        summary = schema_inspector.format_relations_summary(
            relations=relations,
            table_name=table,
            schema=schema,
            limit=None
        )
        return summary["relations"]
    return relations


class ColumnDef(BaseModel):
    name: str
    data_type: str = "TEXT"
    length_precision: Optional[str] = None
    is_nullable: bool = True
    is_primary_key: bool = False
    is_auto_increment: bool = False
    is_unique: bool = False
    default_value: Optional[str] = None
    foreign_key_table: Optional[str] = None
    foreign_key_column: Optional[str] = None
    on_delete: Optional[str] = "CASCADE"


class CreateTableRequest(BaseModel):
    table_name: str
    schema_name: Optional[str] = None
    columns: List[ColumnDef]
    if_not_exists: bool = True


def build_create_table_ddl(
    engine: str,
    table_name: str,
    schema_name: Optional[str],
    columns: List[ColumnDef],
    if_not_exists: bool = True
) -> str:
    import re
    clean_table = table_name.strip('"`')
    if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', clean_table):
        raise ValueError(f"Invalid table identifier name: '{table_name}'")

    if engine == "postgres":
        clean_schema = (schema_name or "public").strip('"`')
        target_name = f'"{clean_schema}"."{clean_table}"'
    else:
        target_name = f'`{clean_table}`'

    col_defs = []
    has_pk = False

    for c in columns:
        clean_col = c.name.strip('"`')
        if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', clean_col):
            raise ValueError(f"Invalid column identifier name: '{c.name}'")

        q_col = f'"{clean_col}"' if engine == "postgres" else f'`{clean_col}`'
        type_str = c.data_type.strip().upper()
        if c.length_precision and c.length_precision.strip():
            type_str = f"{type_str}({c.length_precision.strip()})"

        parts = [q_col]

        if c.is_auto_increment:
            has_pk = True
            if engine == "sqlite":
                parts.append("INTEGER PRIMARY KEY AUTOINCREMENT")
            else:
                if "BIG" in type_str or "8" in type_str:
                    parts.append("BIGSERIAL PRIMARY KEY")
                else:
                    parts.append("SERIAL PRIMARY KEY")
        else:
            parts.append(type_str)
            if c.is_primary_key:
                has_pk = True
                parts.append("PRIMARY KEY")
            if not c.is_nullable:
                parts.append("NOT NULL")
            if c.is_unique and not c.is_primary_key:
                parts.append("UNIQUE")
            if c.default_value is not None and c.default_value.strip():
                parts.append(f"DEFAULT {c.default_value.strip()}")

        if c.foreign_key_table and c.foreign_key_column:
            fk_tbl = c.foreign_key_table.strip('"`')
            fk_col = c.foreign_key_column.strip('"`')
            on_del = f" ON DELETE {c.on_delete.strip().upper()}" if c.on_delete else ""
            if engine == "postgres":
                parts.append(f'REFERENCES "{fk_tbl}" ("{fk_col}"){on_del}')
            else:
                parts.append(f'REFERENCES `{fk_tbl}` (`{fk_col}`){on_del}')

        col_defs.append("  " + " ".join(parts))

    if not col_defs:
        raise ValueError("Cannot create table without any columns")

    body = ",\n".join(col_defs)
    ine = "IF NOT EXISTS " if if_not_exists else ""
    return f"CREATE TABLE {ine}{target_name} (\n{body}\n);"


@router.post("/table/create", response_model=Dict[str, Any])
async def create_table(req: CreateTableRequest):
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=400, detail="No active database connection configured")

    try:
        ddl = build_create_table_ddl(
            engine=conn.engine,
            table_name=req.table_name,
            schema_name=req.schema_name,
            columns=req.columns,
            if_not_exists=req.if_not_exists
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    from app.core.db_manager import db_manager
    from app.core.audit import audit_broadcaster, AuditEvent

    result = await db_manager.create_table(conn, ddl)
    status = "ERROR" if result.error else "ALLOWED"

    audit_broadcaster.record_event(
        AuditEvent(
            source="FLUTTER_UI",
            action="create_table",
            sql=ddl,
            status=status,
            execution_time_ms=result.execution_time_ms,
            message=result.error or f"Created table '{req.table_name}'"
        )
    )

    if result.error:
        raise HTTPException(status_code=400, detail=result.error)

    # Invalidate schema cache so new table appears immediately
    schema_inspector.invalidate_cache(conn.id)

    return {
        "success": True,
        "table_name": req.table_name,
        "ddl": ddl,
        "execution_time_ms": result.execution_time_ms
    }


class DropTableRequest(BaseModel):
    table_name: str
    schema_name: Optional[str] = None
    cascade: bool = False


@router.post("/table/drop", response_model=Dict[str, Any])
async def drop_table(req: DropTableRequest):
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=400, detail="No active database connection configured")

    from app.core.db_manager import db_manager
    from app.core.audit import audit_broadcaster, AuditEvent

    schema = req.schema_name or ("public" if conn.engine == "postgres" else "main")
    result = await db_manager.drop_table(conn, schema=schema, table=req.table_name, cascade=req.cascade)
    status = "ERROR" if result.error else "ALLOWED"

    audit_broadcaster.record_event(
        AuditEvent(
            source="FLUTTER_UI",
            action="drop_table",
            sql=f"DROP TABLE {req.table_name};",
            status=status,
            execution_time_ms=result.execution_time_ms,
            message=result.error or f"Dropped table '{req.table_name}'"
        )
    )

    if result.error:
        raise HTTPException(status_code=400, detail=result.error)

    schema_inspector.invalidate_cache(conn.id)

    return {
        "success": True,
        "dropped_table": req.table_name,
        "execution_time_ms": result.execution_time_ms
    }


class TruncateTableRequest(BaseModel):
    table_name: str
    schema_name: Optional[str] = None
    cascade: bool = False


@router.post("/table/truncate", response_model=Dict[str, Any])
async def truncate_table(req: TruncateTableRequest):
    conn = settings_manager.get_active_connection()
    if not conn:
        raise HTTPException(status_code=400, detail="No active database connection configured")

    from app.core.db_manager import db_manager
    from app.core.audit import audit_broadcaster, AuditEvent

    schema = req.schema_name or ("public" if conn.engine == "postgres" else "main")
    result = await db_manager.truncate_table(conn, schema=schema, table=req.table_name, cascade=req.cascade)
    status = "ERROR" if result.error else "ALLOWED"

    audit_broadcaster.record_event(
        AuditEvent(
            source="FLUTTER_UI",
            action="truncate_table",
            sql=f"TRUNCATE TABLE {req.table_name};",
            status=status,
            execution_time_ms=result.execution_time_ms,
            message=result.error or f"Truncated table '{req.table_name}'"
        )
    )

    if result.error:
        raise HTTPException(status_code=400, detail=result.error)

    schema_inspector.invalidate_cache(conn.id)

    return {
        "success": True,
        "truncated_table": req.table_name,
        "execution_time_ms": result.execution_time_ms
    }


