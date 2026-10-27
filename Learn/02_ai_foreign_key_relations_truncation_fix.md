<!--
          (\__/)
          (˶ᵔ ᵕ ᵔ˶)  < "Lunar Territory."
         / >[CRIMSON+]>   "Hands off, unless you're Miharin."
-->

# Milestone: AI Foreign Key Relations Context Overflow & Filtering Resolution

- **Date:** 2026-10-27
- **Authors:** Miharin & Luna
- **Channeled Aspects:** Scythe (SQL & Query Planning), Cipher (Natural Language & Tooling), Verdict (Verification & Contracts)
- **Status:** VERIFIED & PASSING (42/42 Tests)

---

## 1. Symptom & Unintended Behavior
When asking RevVault's AI Assistant to inspect foreign keys (e.g. clicking the prompt chip *"Inspect Foreign Key Relationships"* or asking *"What are the foreign keys of table X?"*), the assistant failed to respond as intended. It either stalled indefinitely, timed out after 300 seconds, dropped prompt context, or generated empty / hallucinated responses.

---

## 2. Root Cause Analysis
1. **Unbounded Context Payload (25,000+ Tokens):**
   - In production databases (e.g., hospital databases with 892 foreign key constraints across schemas like `master`, `antrian`, and `rawat_inap`), `get_table_relations` dumped all 892 raw foreign key relations as a 6,245-line indented JSON array into the LLM conversation history.
   - Ollama was configured with `num_ctx: 8192`. The ~25k token tool result drastically exceeded the context window, causing Ollama to drop the system instructions or fail during token evaluation.
2. **Missing Parameterization in Tool Schema:**
   - The `get_table_relations` definition in `AGENT_TOOLS_SCHEMA` and `mcp/server.py` had empty parameter schemas (`properties: {}`).
   - Even when the user or LLM attempted to pass `table_name` or `schema` to target a specific entity, the tool executor ignored the arguments and still retrieved all 892 relationships.
3. **Absence of Exploration Guidance in System Prompt:**
   - `AGENT_SYSTEM_PROMPT` had specific rules for database table exploration (`list_tables`), but lacked guidance instructing the LLM on how to handle foreign key exploration, schema-level relationship summaries, or targeted table drills.

---

## 3. Step-by-Step Surgical Fix Procedure
1. **Lightweight Relations Summary Engine (`SchemaInspector.format_relations_summary`):**
   - In `backend/app/core/schema_inspector.py`, created `format_relations_summary` (and `lunar_format_relations_summary`).
   - Computes database-wide schema distribution (e.g. `{"master": 120, "public": 15}`).
   - Filters by `table_name` (matching both source outgoing and target incoming foreign keys, handling both raw names and schema-qualified names).
   - Filters by `schema` and keyword `search`.
   - Capped database-wide exploration to 25 relations with an informative `note` and `has_more: true` flag.
2. **Schema & Argument Expansion in `agent_service.py`:**
   - Added `table_name`, `schema`, `search`, and `limit` to `get_table_relations` tool definition in `AGENT_TOOLS_SCHEMA`.
   - Wired `execute_tool` to parse `table_name` (or `table`), `schema`, `search`, and `limit`, returning formatted JSON summaries.
3. **System Prompt Advisory Guardrails:**
   - Updated `AGENT_SYSTEM_PROMPT` in `agent_service.py` and `scripts/lunar_standalone_agent.py` instructing the AI to:
     - Always pass `table_name` to `get_table_relations` when inquiring about a specific table or entity.
     - Review total relation counts and schema distribution first when exploring database-wide relations.
     - Guide users to filter by table or schema rather than overflowing context.
4. **MCP Server Alignment (`server.py`):**
   - Updated `get_table_relations` in `backend/app/mcp/server.py` to accept `table_name`, `schema`, `search`, and `limit`, delegating to `format_relations_summary`.
5. **REST API Enhancement (`routes_schema.py`):**
   - Added optional `table` and `schema` query parameters to `/api/schema/relationships`.

---

## 4. Verification Proof
1. **Pytest Test Suite:**
   - Added `test_agent_get_table_relations_execution` and `test_agent_get_table_relations_with_filters` in `backend/tests/test_agent.py`.
   - Added `format_relations_summary` unit assertions in `backend/tests/test_db_and_schema.py`.
   - Executed `pytest`: **42 passed in 0.95s** with zero regressions.
2. **Standalone Verification:**
   - Executed standalone Python inspection verifying both filtered queries and unfiltered summary outputs against hospital-style schema datasets.

---

## 5. Prevention Invariant
- **Invariant:** *No database introspection tool exposed to LLM context may return unbounded raw collections.*
- Every schema or relationship tool must enforce lightweight summarization, schema-level aggregation counts, and default upper-bound limits (20-50 items) unless explicitly overridden with targeted filters.
