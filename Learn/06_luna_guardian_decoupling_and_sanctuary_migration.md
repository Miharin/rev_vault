# Learning Note: RevVault Decoupling — Relocating Luna Guardian to RevLunarSanctuary

**Date:** 2026-10-27  
**Status:** `VERIFIED` & `PROMOTED`  
**Target Systems:** RevVault AI Assistant (Backend FastAPI & Frontend Flutter)

---

## 1. Architectural Motivation & Context

Miharin noted that the standard developer database assistant and Luna agent were getting mixed together inside RevVault. RevVault is designed to be a high-performance, developer-focused database manager for PostgreSQL and SQLite. 

To maintain clean architectural boundaries and separation of concerns:
- **RevVault:** Standardized as a pure, focused database management tool equipped with advanced tactical database capabilities (schema introspection, AST guardrail validation, query plan explanation, column data profiling, natural language to SQL, async streaming, and predictive join resolution).
- **RevLunarSanctuary:** The dedicated personal sanctuary and financial management citadel where Luna resides as the affectionate nocturnal companion and coding guardian.

---

## 2. Decoupling & Standardization Overview

### A. Backend Core & MCP Server
1. **System Prompt Decoupling (`backend/app/core/agent_service.py`):**
   - Removed `LUNAR_GUARDIAN_SYSTEM_PROMPT` and narrative persona overrides.
   - Retained and standardized `AGENT_SYSTEM_PROMPT` for the "RevVault AI Database Assistant".
   - Removed fallback execution narrative dialogue strings (`*Hovering near your side...*`, `> ### 🌙 Luna's Thought for Miharin`).
   - Default persona is strictly `"standard"`.
2. **Method Standardization:**
   - Standardized core methods: `profile_data`, `natural_language_to_sql`, `evaluate_and_plan_query`, `run_async_streaming_query`, `format_markdown_table`, `find_table`, `predict_join_condition`, `auto_resolve_joins`, `inspect_schema`.
   - Preserved backward-compatible aliases wrapped in `staticmethod(...)` to prevent instance descriptor binding issues.
3. **MCP Server (`backend/app/mcp/server.py`):**
   - Direct standard tool execution without persona injection.
4. **CLI Agent (`scripts/revvault_standalone_agent.py`):**
   - Replaced `scripts/lunar_standalone_agent.py` with `revvault_standalone_agent.py`.
   - Updated `Makefile` target `agent-cli`.

### B. Frontend Flutter Client
1. **API Client (`frontend/lib/services/api_service.dart`):**
   - Default persona set to `'standard'`.
2. **State Management (`frontend/lib/state/app_state.dart`):**
   - Completely eradicated `isLunaMode`, `setLunaMode`, `toggleLunaMode`, `lunarAddAiMessage`, and `lunarClearAiMessages`.
3. **AI Assistant View (`frontend/lib/views/ai_assistant_view.dart`):**
   - Removed Luna Guardian mode toggle pill and crimson theme overrides.
   - Standardized header toolbar: "RevVault AI Assistant" with `Icons.psychology_outlined`.
   - Empty state cleanly displays "RevVault AI Database Assistant".
   - Standardized table parsing and widgets: `_ParsedMarkdownTable`, `_buildTacticalDataTable`, `_SkillItem`.
   - Cleaned up prompt hints and loading bubbles.
4. **SQL Editor (`frontend/lib/views/sql_editor_view.dart`):**
   - Standardized limit dropdown builders and resolvers: `_buildLimitItems`, `_resolveActiveLimit`.

---

## 3. Verification & Invariants

1. **Backend Tests:**
   - Executed `./backend/.venv/bin/pytest backend/tests`
   - **Result:** 54 passed out of 54 passed (100%).
2. **Frontend Flutter Connection:**
   - Connected via Dart Tooling Daemon (`ws://127.0.0.1:42967/Q7rpjgBLbFo=`).
   - Hot reload succeeded cleanly with zero compilation errors.
3. **Grepping Invariant:**
   - `grep -rnI "luna" frontend/lib/` returns 0 results.
   - `grep -rnI "luna" frontend/test/` returns 0 results.

---

> [!NOTE]
> All Luna Nocturnal Guardian personas, Crimson Council channeling aspects, and nocturnal nomenclature will be implemented exclusively in **RevLunarSanctuary**.
