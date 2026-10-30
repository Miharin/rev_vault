# Milestone 12: Ollama Model Path Resolution, HTTP 400 Tool-Less Fallback & 404 Resilience

- **Status:** `VERIFIED`
- **Date:** 2026-10-30
- **Overseeing Aspects:** `[Rune & Scythe]` (Backend & API Contracts), `[Cipher]` (AI & LLM Model Integration), `[Verdict]` (Verification)
- **Target Files:**
  - `backend/app/core/agent_service.py`
  - `backend/tests/test_agent.py`

---

## 1. Symptom & Root Cause Analysis

### Symptom
1. Previously, selecting or requesting `gemma:2b` resulted in `HTTP 404 Not Found` when Ollama was run without `OLLAMA_MODELS=/var/lib/ollama`.
2. Once `gemma:2b` was pulled and recognized by Ollama, sending a chat message produced:
   `Ollama connection error (HTTP 400). Ensure Ollama is running and model 'gemma:2b' is installed.`
   The underlying raw payload from Ollama was:
   `HTTP 400: {"error": "gemma:2b does not support tools"}`.

### Root Cause Analysis
- RevVault is an autonomous database agent. By default, [`agent_service.py`](backend/app/core/agent_service.py) attaches `tools: AGENT_TOOLS_SCHEMA` (inspect schema, preview tables, execute queries, etc.) to all Ollama `/api/chat` requests.
- While `gemma4:e4b` has a chat template supporting structured tool calling, the official base **`gemma:2b` does not support function calling**.
- When Ollama receives a request containing the `"tools"` array for a model that lacks tool support, it rejects the request outright with **HTTP 400 (`<model> does not support tools`)**.

---

## 2. Step-by-Step Surgical Fix Procedure

1. **Automatic Non-Tool Fallback (`AgentService.chat`):**
   - Intercepted Ollama's `HTTP 400` error when it indicates tools are not supported (`"does not support tools"` / `"tools are not supported"`).
   - Automatically dispatched an immediate retry payload omitting the `"tools"` parameter block.
   - Prepended a helpful diagnostic banner to the response:
     > `ℹ️ Notice: Model gemma:2b does not support native function/tool calling in Ollama. Operating in conversational & SQL assistance mode (database tools are disabled).`
2. **Model Name Normalizer (`lunar_resolve_model_name`):**
   - Maintained intelligent resolution for shorthand model tags (`gemma:e4b` -> `gemma4:e4b`).
3. **Automated Verification Proof:**
   - Implemented `test_agent_chat_400_no_tool_fallback` in `backend/tests/test_agent.py`.
   - Simulates Ollama's 400 rejection and verifies that RevVault automatically strips `tools`, successfully fetches the model's text response, and returns it to the user.

---

## 3. Verification Proof

```bash
backend/.venv/bin/pytest -v backend/tests/test_agent.py
# Result: 21 passed in 0.38s
# Including test_agent_chat_400_no_tool_fallback and test_agent_chat_404_helpful_message

backend/.venv/bin/pytest backend/tests
# Result: 60 passed in 0.84s
```

---

## 4. Permanent Guardrail & Invariant

- **Universal Model Degradation Invariant:** RevVault must never fail with an HTTP 400 when an end-user selects a smaller or older model lacking tool-calling capability. The backend must detect the limitation and transparently fallback to conversational SQL generation mode without interrupting the user.
