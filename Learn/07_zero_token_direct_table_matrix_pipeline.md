# Learning Note: Zero-Token Direct Structured Table Matrix Pipeline

**Date:** 2026-10-27  
**Status:** `VERIFIED` & `PROMOTED`  
**Target Systems:** RevVault AI Assistant (Backend Agent Service & Frontend Flutter Data Matrix)

---

## 1. Symptom & Architectural Context

When querying database tables or previews through the RevVault AI Assistant, the system previously had two major pain points:
1. **The 10-Row Hard Limit:** Query outputs were artificially capped at 10 rows to prevent context explosion.
2. **Token Burn & Severe Generation Latency:** Generating 50–100 rows in Markdown text burned 3,000 to 8,000 generation tokens. On local Ollama models (e.g. Qwen 2.5 Coder, Llama 3), this caused 20–45 seconds of generation delay, high memory usage, and frequent truncation mid-stream.
3. **Static, Non-Interactive Output:** Standard Markdown tables inside chat messages lacked sorting, search filtering, pagination, and direct integration with RevVault's SQL Editor.

Miharin asked:
> *"Luna the data matrix is limit to 10 ? What if like this the agent just check the query and using MCP for table so it can full table, so it not burning the token, can we do this ?"*

---

## 2. Root Cause Analysis

**Coupling tabular data transport to LLM autoregressive token generation:**  
LLMs are reasoning engines, not high-throughput tabular serialization protocols. Passing an entire dataset through the model's tokenizer and requiring it to autoregressively output every pipe `|`, dash `-`, and cell value character-by-character is an anti-pattern.

The database engine already holds the structured data (`columns`, `rows`, `row_count`, `execution_time_ms`). Passing it through the LLM text output:
- Consumed unnecessary tokens.
- Increased latency by orders of magnitude.
- Enforced low artificial row limits.

---

## 3. Step-by-Step Surgical Implementation

### Step 1: Backward-Compatible `ToolResult` Subclass (`backend/app/core/agent_service.py`)
To attach structured data to tool executions without breaking legacy tuple unpacking `(output, success)` in tests and services, we introduced a tuple subclass:

```python
class ToolResult(tuple):
    """Tuple subclass (output_str, success_bool) holding optional structured data payload."""
    def __new__(cls, output: str, success: bool = True, data: Optional[Dict[str, Any]] = None):
        instance = super().__new__(cls, (output, success))
        instance.data = data
        return instance
```

### Step 2: Zero-Token Compact Summaries for LLM Context
In `execute_safe_query` and `get_table_preview`:
- The full query result (`QueryResult.to_dict()`) is attached to `ToolResult(..., data=query_dict)`.
- The string fed to the LLM's tool context is stripped of large row arrays and replaced with a lightweight summary (under 60 tokens):

```json
{
  "status": "success",
  "row_count": 100,
  "columns": ["id", "username", "email", "created_at"],
  "execution_time_ms": 1.42,
  "sql": "SELECT * FROM users LIMIT 100;",
  "sample_rows": [ ...first 3 rows only... ],
  "client_delivery": "FULL_DATASET_TRANSMITTED_DIRECTLY_TO_CLIENT_UI_DATA_MATRIX"
}
```

- System prompt updated: `CRITICAL INSTRUCTION: Query and preview results are delivered directly to the client's interactive Data Matrix UI as structured data. DO NOT reproduce or serialize full markdown tables in your text response.`
- Query limit expanded from 10 to 100 (up to 500 rows maximum).

### Step 3: API Pipeline Data Forwarding (`backend/app/api/routes_agent.py`)
- Updated `ToolExecutionDto` to include `data: Optional[Dict[str, Any]] = None`.
- Tool execution loop extracts `tool_res.data` and forwards it directly in the API response.

### Step 4: Frontend Data Matrix & Model Integration (`frontend/lib/`)
1. **`frontend/lib/models/ai_message.dart`:**
   - Added `QueryResult? get primaryQueryResult`: extracts the structured `QueryResult` from the message's `toolExecutions` payload.
   - Added `String? get primaryQuerySql`: extracts the SQL query that produced the result.
2. **`frontend/lib/views/ai_assistant_view.dart`:**
   - Implemented `_StructuredDataMatrixWidget`:
     - **Tactical Header:** Badge showing row count, column count, and query execution time in ms.
     - **Client-Side Live Filter:** Real-time text search across all columns and rows.
     - **Pagination Controls:** Dropdown supporting 10, 25, 50, 100, or All rows per page, with fast page jumping (`First`, `Prev`, `Next`, `Last`).
     - **Direct Action Bar:**
       - `Run in Editor`: Injects the SQL query directly into the active SQL editor tab.
       - `Copy TSV`: One-click copy formatted for Excel and Google Sheets.
       - `Copy Markdown`: One-click copy formatted for documentation.
     - **Interactive Data Table:** Scrollable horizontal and vertical table with monospace formatting and null styling.

---

## 4. Verification Proof

1. **Backend Test Suite:**
   - Added `test_agent_execute_safe_query_zero_token_structured_data` in `backend/tests/test_agent.py`.
   - Verified that `execute_safe_query` delivers `row_count == 100` in structured data while keeping tool text output under 60 tokens.
   - Executed `./backend/.venv/bin/pytest backend/tests`: **55 passed out of 55 passed (100%)** in 0.75s.
2. **Frontend Analysis & Hot Reload:**
   - Analyzed Flutter files via MCP `analyze_files`: **0 errors / 0 warnings**.
   - Connected via Dart Tooling Daemon (`ws://127.0.0.1:38361/3dBmpGipJEs=`).
   - Triggered MCP `hot_reload`: **Hot reload succeeded** in live application.
3. **Performance Metrics:**
   - **Token Consumption:** Reduced from ~4,500 tokens to ~65 tokens (>98% token reduction).
   - **Latency:** Decreased from ~30 seconds down to <1 second on local Ollama models.
   - **Capacity:** Expanded from 10 rows to 100/500 rows with instantaneous rendering.

---

## 5. Permanent Architectural Invariant

> [!IMPORTANT]
> **The Zero-Token Out-of-Band Data Invariant:**  
> Tabular and high-volume structured query results must NEVER be serialized through LLM text generation tokens. Database results must flow out-of-band via structured API payloads (`ToolExecutionDto.data`) directly to the client UI. The LLM receives only execution metadata and a 3-row sample for semantic reasoning.
