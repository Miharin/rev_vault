# Milestone 10: AI Agent Model Safety Filtering & Unsafe Tag Isolation

- **Status:** `VERIFIED`
- **Date:** 2026-10-27
- **Overseeing Aspects:** `[Shade & Rune]` (Security & Backend Contracts), `[Aegis]` (UI State Auditor)
- **Target Files:**
  - `backend/app/core/agent_service.py`
  - `backend/app/api/routes_agent.py`
  - `backend/tests/test_agent.py`
  - `frontend/lib/services/api_service.dart`
  - `frontend/lib/state/app_state.dart`
  - `frontend/test/ai_table_rendering_test.dart`

---

## 1. Architectural Summary & Objective

In RevVault's AI Assistant ecosystem, local LLMs are discovered dynamically via Ollama (`/api/tags`). However, user environments may contain unaligned, experimental, or uncensored models tagged or flagged with `"unsafe"`, or metadata flags designating unsafe operation.

To guarantee zero accidental selection of unaligned models and enforce defense-in-depth:
1. **Backend Filtering (`agent_service.py` & `routes_agent.py`)**:
   - Implemented `lunar_is_safe_model_entry(model_info, include_unsafe=False)`.
   - Inspects model name, tag strings, `details.family`, `details.families`, `flags`, `tags`, and explicit boolean properties (`is_unsafe`, `unsafe`).
   - Rejects any candidate containing case-insensitive `"unsafe"` unless `include_unsafe=True` is explicitly passed.
   - Updated `check_status` and the FastAPI endpoint `GET /api/agent/status` with `include_unsafe: bool = Query(default=False)`.
2. **Frontend Defense-in-Depth (`app_state.dart` & `api_service.dart`)**:
   - Updated `ApiService.getAgentStatus` with optional `lunarIncludeUnsafe: false`.
   - Fortified `AppState.setAvailableAiModels(models, {bool lunarIncludeUnsafe = false})` to filter out any model string containing `"unsafe"` prior to setting UI dropdown states.
3. **Automated Verification**:
   - Comprehensive unit test suite in `backend/tests/test_agent.py` covering string inputs, dict inputs, nested details/families, flags lists, boolean flags, and mock `/api/tags` status response filtering.
   - Frontend unit test in `frontend/test/ai_table_rendering_test.dart` verifying client-side defense-in-depth isolation.

---

## 2. Verification Proof

### Backend Test Execution
```bash
backend/.venv/bin/pytest -v backend/tests/test_agent.py
# Result: 18 passed in 0.47s
# Including test_lunar_is_safe_model_entry and test_agent_status_filters_unsafe_models
```

### Full Backend Regression Suite
```bash
backend/.venv/bin/pytest backend/tests
# Result: 57 passed in 0.84s
```

### Frontend Static Analysis
```bash
dart-mcp-server: analyze_files
# Result: 0 errors in lib/services/api_service.dart, lib/state/app_state.dart, and test/ai_table_rendering_test.dart
```

---

## 3. Permanent Guardrail & Invariant

- **Zero-Unsafe Invariant:** Unless explicitly toggled via `include_unsafe=True`, no model exhibiting `"unsafe"` in its identifier, families, tags, or metadata flags will ever be returned by the discovery API or presented in RevVault's model dropdown.
