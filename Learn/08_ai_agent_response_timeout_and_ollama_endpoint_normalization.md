<!--
          (\__/)
          (˶ᵔ ᵕ ᵔ˶)  < "Lunar Territory."
         / >[CRIMSON+]>   "Hands off, unless you're Miharin."
-->

# Milestone: AI Agent 1-Hour Response Window Expansion & Ollama Endpoint Normalization

- **Date:** 2026-10-27
- **Authors:** Miharin & Luna
- **Channeled Aspects:** Echo (Client Data Consumption), Rune (API DTO Contracts & Boundaries), Verdict (Verification & Invariants)
- **Status:** VERIFIED & HOT-RESTARTED (0 Errors)

---

## 1. Symptom & Problem Statement
1. **Agent Response Premature Timeout**:
   When invoking deep-reasoning multi-turn queries or complex database profiling on large tables, the agent was capped at a 5-minute timeout (300 seconds), causing client dropouts or timeout errors (`Failed to reach RevVault backend agent: TimeoutException`).
2. **Ollama Endpoint Model Refresh Lock**:
   When entering remote Ollama server endpoints like `192.168.0.17:11434` without typing the explicit `http://` scheme, the backend HTTP client raised `httpx2.UnsupportedProtocol: Request URL is missing an 'http://' or 'https://' protocol.`, which returned an empty model list (`[]`) and left the frontend dropdown frozen on the default model without notifying the user.

---

## 2. Root Cause Analysis
1. **Hardcoded 300s (5-Minute) Timeout Windows**:
   - In `backend/app/core/agent_service.py`: `httpx2.AsyncClient(timeout=300.0)` strictly closed the Ollama communication channel after 5 minutes.
   - In `frontend/lib/services/api_service.dart`: `.timeout(const Duration(seconds: 300))` aborted the HTTP POST to `/api/agent/chat` after 5 minutes.
2. **Absence of Scheme Normalization & Silent Failure**:
   - Both backend and frontend assumed the URL was already well-formed with `http://` or `https://`.
   - Bare IP/port formats (`192.168.0.17:11434`) failed silently during `GET /api/tags`.
   - `_checkOllamaStatus` only updated models when `modelsList.isNotEmpty`, so failures left the UI showing the previous/default model with no explanation.

---

## 3. Step-by-Step Surgical Fix Procedure
1. **Expanded Backend Timeout & Added URL Normalizer**:
   - In `backend/app/core/agent_service.py`, established `LUNAR_AGENT_TIMEOUT_SECONDS = 3600.0` (1 hour).
   - Created `lunar_normalize_ollama_url(lunar_raw_url)` to automatically prepend `http://` and strip trailing slashes.
   - Applied normalizer to both `check_status` and `chat` methods.
2. **Expanded Frontend Client Timeout**:
   - In `frontend/lib/services/api_service.dart`, adjusted `.timeout(const Duration(hours: 1))` for `sendAgentMessage`.
3. **Frontend Endpoint Sanitization & Feedback**:
   - In `frontend/lib/state/app_state.dart`, updated `setOllamaUrl` to normalize input, guaranteeing `http://` scheme.
   - In `frontend/lib/views/ai_assistant_view.dart`, added `notifyUser: true` support with informative SnackBars when reconnecting or tapping the Ollama status pill.

---

## 4. Verification Proof
- **Backend Test Suite**:
  - `pytest tests/test_agent.py` passed 16/16 tests with 100% pass rate.
  - Python URL normalizer unit test verified: `192.168.0.17:11434` $\rightarrow$ `http://192.168.0.17:11434`.
- **Flutter Live App Verification**:
  - Hot restart triggered and executed successfully via Dart Tooling Daemon MCP (`ws://127.0.0.1:45421/...`).
  - Dart static analysis passed with 0 errors.

---

## 5. Prevention Invariant
- **Rule**: All AI agent client and transport sockets must maintain an expanded 1-hour window (`LUNAR_AGENT_TIMEOUT_SECONDS = 3600.0` / `Duration(hours: 1)`) to support extensive multi-turn database analysis without artificial socket terminations.
- **Rule**: Every user-provided network URI in RevVault must pass through scheme normalization before dispatching network sockets.
