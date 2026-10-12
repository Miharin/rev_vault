import json
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Dict, Any, List, Optional
from pydantic import BaseModel, Field

from app.config import DEFAULT_DATA_DIR, ConnectionConfig
from app.core.db_manager import db_manager
from app.core.audit import audit_broadcaster, AuditEvent

class MutationRecord(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    timestamp: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    table_name: str
    operation: str  # "update" | "delete"
    primary_keys: Dict[str, Any]
    old_values: Dict[str, Any]
    new_values: Optional[Dict[str, Any]] = None
    inverse_sql: str
    is_recovered: bool = False

def format_sql_literal(val: Any) -> str:
    if val is None:
        return "NULL"
    if isinstance(val, bool):
        return "TRUE" if val else "FALSE"
    if isinstance(val, (int, float)):
        return str(val)
    sanitized = str(val).replace("'", "''")
    return f"'{sanitized}'"

def quote_col_ident(col: str, engine: str) -> str:
    clean = col.strip('"`')
    return f'"{clean}"' if engine == "postgres" else f'`{clean}`'

def quote_table_name(table_name: str, engine: str) -> str:
    parts = [p.strip('"`') for p in table_name.split(".")]
    if engine == "postgres":
        return ".".join(f'"{p}"' for p in parts)
    return ".".join(f'`{p}`' for p in parts)

class HistoryManager:
    MAX_EDITS = 50
    MAX_DELETES = 50
    RETENTION_DAYS = 365

    def __init__(self, data_dir: Path = DEFAULT_DATA_DIR):
        self.data_dir = data_dir
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.history_file = self.data_dir / "mutation_history.json"
        self._ensure_file()

    def _ensure_file(self):
        if not self.history_file.exists():
            self.history_file.write_text("[]", encoding="utf-8")

    def load_history(self) -> List[MutationRecord]:
        try:
            content = self.history_file.read_text(encoding="utf-8")
            data = json.loads(content)
            return [MutationRecord(**item) for item in data]
        except Exception:
            return []

    def _save_history(self, records: List[MutationRecord]):
        data = [r.model_dump() for r in records]
        self.history_file.write_text(json.dumps(data, indent=2), encoding="utf-8")

    def prune_records(self, records: List[MutationRecord]) -> List[MutationRecord]:
        """
        Prunes records:
        - Drops records older than RETENTION_DAYS (1 year)
        - Retains at most MAX_EDITS (50) updates
        - Retains at most MAX_DELETES (50) deletes
        """
        now = datetime.now(timezone.utc)
        cutoff = now - timedelta(days=self.RETENTION_DAYS)

        valid_records: List[MutationRecord] = []
        for r in records:
            try:
                # Handle possible missing 'Z' or offset formats
                ts = datetime.fromisoformat(r.timestamp.replace("Z", "+00:00"))
                if ts >= cutoff:
                    valid_records.append(r)
            except Exception:
                # If parsing fails, retain conservatively
                valid_records.append(r)

        updates = [r for r in valid_records if r.operation.lower() == "update"]
        deletes = [r for r in valid_records if r.operation.lower() == "delete"]
        inserts = [r for r in valid_records if r.operation.lower() == "insert"]

        # Keep the latest entries (newest are at the end)
        if len(updates) > self.MAX_EDITS:
            updates = updates[-self.MAX_EDITS:]
        if len(deletes) > self.MAX_DELETES:
            deletes = deletes[-self.MAX_DELETES:]
        if len(inserts) > self.MAX_EDITS:
            inserts = inserts[-self.MAX_EDITS:]

        combined = updates + deletes + inserts
        # Sort chronologically by timestamp
        combined.sort(key=lambda r: r.timestamp)
        return combined

    def build_inverse_sql(
        self,
        table_name: str,
        operation: str,
        primary_keys: Dict[str, Any],
        old_values: Dict[str, Any],
        engine: str
    ) -> str:
        table_quoted = quote_table_name(table_name, engine)

        if operation.lower() == "delete":
            # Inverse of DELETE is INSERT with all old values
            cols = list(old_values.keys())
            quoted_cols = [quote_col_ident(c, engine) for c in cols]
            vals = [format_sql_literal(old_values[c]) for c in cols]
            cols_str = ", ".join(quoted_cols)
            vals_str = ", ".join(vals)
            return f"INSERT INTO {table_quoted} ({cols_str}) VALUES ({vals_str});"

        elif operation.lower() == "update":
            # Inverse of UPDATE is UPDATE setting old values for modified columns
            set_clauses = [
                f"{quote_col_ident(k, engine)} = {format_sql_literal(v)}"
                for k, v in old_values.items()
            ]
            set_str = ", ".join(set_clauses)

            where_clauses = []
            for k, v in primary_keys.items():
                col_q = quote_col_ident(k, engine)
                if v is None:
                    where_clauses.append(f"{col_q} IS NULL")
                else:
                    where_clauses.append(f"{col_q} = {format_sql_literal(v)}")
            where_str = " AND ".join(where_clauses)
            return f"UPDATE {table_quoted} SET {set_str} WHERE {where_str};"

        elif operation.lower() == "insert":
            # Inverse of INSERT is DELETE by primary keys or inserted keys if provided
            pks = primary_keys or old_values
            if pks:
                where_clauses = []
                for k, v in pks.items():
                    col_q = quote_col_ident(k, engine)
                    if v is None:
                        where_clauses.append(f"{col_q} IS NULL")
                    else:
                        where_clauses.append(f"{col_q} = {format_sql_literal(v)}")
                where_str = " AND ".join(where_clauses)
                return f"DELETE FROM {table_quoted} WHERE {where_str};"

        return ""

    def record_mutation(
        self,
        table_name: str,
        operation: str,
        primary_keys: Dict[str, Any],
        old_values: Dict[str, Any],
        new_values: Optional[Dict[str, Any]],
        engine: str
    ) -> MutationRecord:
        inverse_sql = self.build_inverse_sql(
            table_name=table_name,
            operation=operation,
            primary_keys=primary_keys,
            old_values=old_values,
            engine=engine
        )

        record = MutationRecord(
            table_name=table_name,
            operation=operation.lower(),
            primary_keys=primary_keys,
            old_values=old_values,
            new_values=new_values,
            inverse_sql=inverse_sql,
            is_recovered=False
        )

        current = self.load_history()
        current.append(record)
        pruned = self.prune_records(current)
        self._save_history(pruned)
        return record

    async def recover(self, history_id: str, conn: ConnectionConfig) -> Dict[str, Any]:
        records = self.load_history()
        target = next((r for r in records if r.id == history_id), None)
        if not target:
            return {"success": False, "error": f"Mutation record '{history_id}' not found"}

        if not target.inverse_sql.strip():
            return {"success": False, "error": "No inverse SQL statement available for this mutation"}

        result = await db_manager.execute_query(conn, target.inverse_sql, safe_mode=False)

        status = "ERROR" if result.error else "ALLOWED"
        audit_broadcaster.record_event(
            AuditEvent(
                source="FLUTTER_UI",
                action=f"row_recover_{target.operation}",
                sql=target.inverse_sql,
                status=status,
                execution_time_ms=result.execution_time_ms,
                row_count=result.row_count,
                message=result.error or f"Recovered {target.operation} for {target.table_name}"
            )
        )

        if result.error:
            return {
                "success": False,
                "error": result.error,
                "inverse_sql": target.inverse_sql
            }

        target.is_recovered = True
        self._save_history(records)

        return {
            "success": True,
            "recovered_id": history_id,
            "operation": target.operation,
            "table_name": target.table_name,
            "affected_rows": result.row_count,
            "inverse_sql": target.inverse_sql
        }

history_manager = HistoryManager()
