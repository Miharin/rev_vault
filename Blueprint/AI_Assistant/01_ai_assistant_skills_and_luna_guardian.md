# Blueprint: AI Assistant Skills Suite (RevVault Core)

- **Development State:** `VERIFIED`
- **Current Progress:** 100% (Complete Implementation, Decoupling & Test Verification)
- **Target Systems:**
  - `backend/app/core/agent_service.py`
  - `backend/app/core/schema_inspector.py`
  - `backend/app/core/explain_inspector.py`
  - `backend/app/mcp/server.py`
  - `backend/app/api/routes_agent.py`
  - `frontend/lib/services/api_service.dart`
  - `frontend/lib/state/app_state.dart`
  - `frontend/lib/views/ai_assistant_view.dart`

---

## 1. Executive Summary & Objective

Equip RevVault's in-app AI Assistant with dedicated tactical database skills and a clean, developer-focused operational model:
1. **`inspect_schema`**: Deep introspection of complete table and schema metadata (columns, data types, nullability, primary keys, foreign keys, indexes, and row estimates).
2. **`explain_query_plan`**: Query execution plan inspection, total cost computation, sequential scan detection, and indexing recommendations.
3. **`data_profilling`**: Comprehensive column statistical profiling (null percentage, distinct values, min, max, avg, and sample frequency distribution).
4. **`natural_language_to_sql`**: Synthesis of optimal, read-only SQL queries from conversational prompts with schema and join reasoning.
5. **`evaluate_and_plan_query`**: Pre-execution AST guardrail safety audit, query complexity rating, execution plan cost calculation, and risk assessment.
6. **`run_async_streaming_query`**: Asynchronous query execution with chunked batch progress, streaming latency timing, and row previews.
7. **Zero-Token Direct Structured Data Matrix Pipeline**: Decouple dataset delivery from LLM text generation tokens. Query results are streamed directly as structured payloads (`tool_executions[].data`) to an interactive Flutter client Data Matrix, while Ollama receives only a compact summary to eliminate token bottlenecks and latency.

> [!NOTE]
> **Decoupling Notice:** The Luna Nocturnal Guardian persona, companion dialogue, and crimson aesthetic overrides have been cleanly decoupled from RevVault. RevVault remains a pure, high-performance database management suite. The Luna Guardian persona is exclusively reserved and implemented inside **RevLunarSanctuary**.

---

## 2. Architectural Blueprint & Verification Checklist

- [x] Architectural design & Blueprint specification
- [x] Backend core implementation of the database skills:
  - [x] `inspect_schema` in `schema_inspector.py` and `agent_service.py`
  - [x] `explain_query_plan` in `explain_inspector.py` and `agent_service.py`
  - [x] `data_profilling` (and alias `data_profiling`) in `agent_service.py`
  - [x] `natural_language_to_sql` in `agent_service.py`
  - [x] `evaluate_and_plan_query` in `agent_service.py`
  - [x] `run_async_streaming_query` in `agent_service.py`
  - [x] Expose all tools in `backend/app/mcp/server.py`
- [x] Zero-Token Direct Structured Data Matrix Pipeline:
  - [x] Backend `ToolResult` tuple subclass supporting `.data` payload delivery
  - [x] `execute_safe_query` and `get_table_preview` return compact summaries to LLM, delivering full datasets (`QueryResult.to_dict()`) in `ToolExecutionDto.data`
  - [x] Ollama prompt instructed not to re-serialize datasets into markdown tables
  - [x] Maximum row limit expanded from 10 to 100/500
  - [x] Frontend `AiMessage.primaryQueryResult` & `primaryQuerySql` accessors
  - [x] High-capacity Flutter `_StructuredDataMatrixWidget` with real-time filtering, pagination (10, 25, 50, 100, All), TSV/Markdown copy, and 1-click "Run in Editor"
- [x] Clean API and Request models (`routes_agent.py`):
  - [x] Default persona: `"standard"`
  - [x] `ToolExecutionDto` includes optional `data: Optional[Dict[str, Any]]`
- [x] Frontend API and state integration:
  - [x] `frontend/lib/services/api_service.dart`: pass `persona: 'standard'`
  - [x] `frontend/lib/state/app_state.dart`: pure database assistant state handling
- [x] Frontend UI enhancement in `ai_assistant_view.dart`:
  - [x] Standard tactical header toolbar with Ollama status pill & model selector
  - [x] Horizontal Quick Skills Dock with interactive chips
  - [x] Empty state recommendation cards for the 6 core skills
  - [x] Interactive data matrix table rendering for query results
- [x] Complete Luna Decoupling:
  - [x] Removal of `LUNAR_GUARDIAN_SYSTEM_PROMPT` and narrative strings from RevVault
  - [x] Removal of `isLunaMode` switch and crimson styling from RevVault UI
  - [x] Replaced standalone terminal agent with `scripts/revvault_standalone_agent.py`
- [x] Model Safety & Unsafe Tag Filtration:
  - [x] `lunar_is_safe_model_entry` checks model names, tags, details, families, and boolean flags for 'unsafe'
  - [x] Backend `check_status` and `GET /api/agent/status` default to `include_unsafe=False`
  - [x] Client-side defense-in-depth filtering in `AppState.setAvailableAiModels`
- [x] Comprehensive testing:
  - [x] Backend pytest suite verifying all tools and model filtering (57/57 passed)
  - [x] Frontend Flutter widget and state tests verified (`ai_table_rendering_test.dart`)

