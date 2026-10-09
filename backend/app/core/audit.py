import asyncio
import datetime
from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field

class AuditEvent(BaseModel):
    id: str = Field(default_factory=lambda: f"evt_{datetime.datetime.utcnow().strftime('%H%M%S%f')[:10]}")
    timestamp: str = Field(default_factory=lambda: datetime.datetime.utcnow().isoformat() + "Z")
    source: str  # "ANTIGRAVITY_MCP" | "FLUTTER_UI"
    action: str  # "execute_safe_query", "list_tables", "describe_table", etc.
    sql: Optional[str] = None
    status: str  # "ALLOWED" | "BLOCKED" | "ERROR"
    execution_time_ms: float = 0.0
    row_count: int = 0
    message: Optional[str] = None

class AuditBroadcaster:
    def __init__(self, max_history: int = 100):
        self.max_history = max_history
        self._history: List[AuditEvent] = []
        self._listeners: List[asyncio.Queue] = []

    def record_event(self, event: AuditEvent):
        self._history.append(event)
        if len(self._history) > self.max_history:
            self._history.pop(0)

        # Notify active WebSocket listeners
        for q in list(self._listeners):
            try:
                q.put_nowait(event)
            except Exception:
                pass

    def get_history(self) -> List[Dict[str, Any]]:
        return [e.model_dump() for e in reversed(self._history)]

    def subscribe(self) -> asyncio.Queue:
        q = asyncio.Queue()
        self._listeners.append(q)
        return q

    def unsubscribe(self, q: asyncio.Queue):
        if q in self._listeners:
            self._listeners.remove(q)

audit_broadcaster = AuditBroadcaster()
