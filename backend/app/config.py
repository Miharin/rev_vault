from pathlib import Path
import json
import os
from typing import Dict, Any, List, Optional
from pydantic import BaseModel, Field

import sys

def get_default_data_dir() -> Path:
    """Returns platform-standard user application data directory."""
    if "REVVAULT_DIR" in os.environ:
        return Path(os.environ["REVVAULT_DIR"])
    if sys.platform == "win32":
        app_data = os.environ.get("APPDATA")
        if app_data:
            return Path(app_data) / "Relva" / "RevVault"
        return Path.home() / "AppData" / "Roaming" / "Relva" / "RevVault"
    return Path.home() / ".revvault"

DEFAULT_DATA_DIR = get_default_data_dir()

class GuardrailSettings(BaseModel):
    strict_read_only: bool = True
    default_row_limit: int = 50
    max_row_limit: int = 250
    blocked_statements: List[str] = Field(
        default_factory=lambda: [
            "DROP", "DELETE", "TRUNCATE", "ALTER", "UPDATE", "INSERT",
            "CREATE", "GRANT", "REVOKE", "MERGE"
        ]
    )

class ConnectionConfig(BaseModel):
    id: str
    name: str
    engine: str  # "sqlite" | "postgres"
    filepath: Optional[str] = None  # for sqlite
    host: Optional[str] = None      # for postgres
    port: Optional[int] = 5432
    database: Optional[str] = None
    username: Optional[str] = None
    password: Optional[str] = None
    ssl: Optional[str] = "prefer"   # "disable", "prefer", "require"
    is_active: bool = False

class SavedQueryConfig(BaseModel):
    id: str
    title: str
    sql: str
    description: Optional[str] = ""
    builder_mode: Optional[str] = "rawSql"
    created_at: Optional[str] = None

class SettingsManager:
    def __init__(self, data_dir: Path = DEFAULT_DATA_DIR):
        self.data_dir = data_dir
        if not self.data_dir.exists():
            try:
                self.data_dir.mkdir(parents=True, exist_ok=True)
            except OSError:
                pass
        self.connections_file = self.data_dir / "connections.json"
        self.guardrail_file = self.data_dir / "guardrail.json"
        self.saved_queries_file = self.data_dir / "saved_queries.json"
        self._ensure_files()

    def _ensure_files(self):
        try:
            if not self.connections_file.exists():
                self.connections_file.write_text("[]", encoding="utf-8")
            if not self.guardrail_file.exists():
                default_guard = GuardrailSettings().model_dump_json(indent=2)
                self.guardrail_file.write_text(default_guard, encoding="utf-8")
            if not self.saved_queries_file.exists():
                self.saved_queries_file.write_text("[]", encoding="utf-8")
        except OSError:
            pass

    def load_connections(self) -> List[ConnectionConfig]:
        try:
            content = self.connections_file.read_text(encoding="utf-8")
            data = json.loads(content)
            return [ConnectionConfig(**c) for c in data]
        except Exception:
            return []

    def save_connections(self, conns: List[ConnectionConfig]):
        data = [c.model_dump() for c in conns]
        self.connections_file.write_text(json.dumps(data, indent=2), encoding="utf-8")

    def get_active_connection(self) -> Optional[ConnectionConfig]:
        conns = self.load_connections()
        for c in conns:
            if c.is_active:
                return c
        return conns[0] if conns else None

    def set_active_connection(self, conn_id: str) -> Optional[ConnectionConfig]:
        conns = self.load_connections()
        active_conn = None
        for c in conns:
            if c.id == conn_id:
                c.is_active = True
                active_conn = c
            else:
                c.is_active = False
        self.save_connections(conns)
        return active_conn

    def load_guardrail_settings(self) -> GuardrailSettings:
        try:
            content = self.guardrail_file.read_text(encoding="utf-8")
            return GuardrailSettings(**json.loads(content))
        except Exception:
            return GuardrailSettings()

    def save_guardrail_settings(self, settings: GuardrailSettings):
        self.guardrail_file.write_text(settings.model_dump_json(indent=2), encoding="utf-8")

    def load_saved_queries(self) -> List[SavedQueryConfig]:
        try:
            content = self.saved_queries_file.read_text(encoding="utf-8")
            data = json.loads(content)
            return [SavedQueryConfig(**q) for q in data]
        except Exception:
            return []

    def save_query(self, query: SavedQueryConfig) -> SavedQueryConfig:
        queries = self.load_saved_queries()
        existing_idx = next((i for i, q in enumerate(queries) if q.id == query.id), None)
        if existing_idx is not None:
            queries[existing_idx] = query
        else:
            queries.insert(0, query)
        data = [q.model_dump() for q in queries]
        self.saved_queries_file.write_text(json.dumps(data, indent=2), encoding="utf-8")
        return query

    def delete_query(self, query_id: str) -> bool:
        queries = self.load_saved_queries()
        filtered = [q for q in queries if q.id != query_id]
        if len(filtered) != len(queries):
            data = [q.model_dump() for q in filtered]
            self.saved_queries_file.write_text(json.dumps(data, indent=2), encoding="utf-8")
            return True
        return False

settings_manager = SettingsManager()
