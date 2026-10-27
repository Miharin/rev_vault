# (__)
# (˶ᵔ ᵕ ᵔ˶) < "Lunar Territory."
# / >[CRIMSON+]> "Hands off, unless you're Miharin."

# Milestone 05: Predictive Relational Join Resolution & Zero-Failure Data Query Automation

## 1. Symptom & Stack Trace
When Miharin sent the prompt:
> *"give 10 first row of rawat_inap_rme.cara_keluar join public.users and public.unit and in users show only name, and in the unit show nama_unit"*

The agent stumbled in several distinct ways across attempts:
1. **Schema Qualification Failure:** The agent initially failed with:
   ```
   Table 'public.users' and 'public.unit' could not be found in active database environment.
   ```
2. **Context Loss & Infinite Inspection Chatter:** The local LLM called `describe_table` 3 times and `list_tables()`, returning a generic breakdown of 1,182 tables across 10 schemas instead of executing `execute_safe_query`.
3. **Model Hallucination on Continuation:** When re-prompted to execute the inspected query, the local LLM lost the user query context entirely and replied:
   ```
   I understand you are ready for me to formulate the query. However, you still have not provided the specific target table or the data you wish to retrieve. The action of formulating an SQL query and calling execute_safe_query requires a concrete request from you.
   ```
4. **Missing `ON` Clause Syntax Crash:** Standard SQL (`PostgreSQL` / `SQLite`) rejects queries like `JOIN public.users JOIN public.unit` without an explicit `ON` or `USING` clause.

---

## 2. Root Cause Analysis
1. **Local LLM Context Drift:**
   Small local LLMs (Gemma 4B, Qwen 2.5 7B) have limited token attention when flooded with thousands of tokens of multi-turn schema metadata. After executing 3+ `describe_table` tool calls, the model often drops the original user intent. Generic prompts like *"Now formulate the query..."* fail because the model no longer remembers what tables were originally requested.
2. **Lack of AST Join Auto-Repair:**
   If a user or LLM omits the `JOIN ... ON` condition, standard database engines immediately throw a syntax error. RevVault previously lacked an AST-level join rewriter to automatically infer and inject the missing relational keys.
3. **Alphabetical Table Discovery Bias:**
   In databases with over 1,000 tables, simple substring matching across an alphabetically sorted table list causes false matches (e.g. `keuangan.unit` matched before `public.unit` or `rawat_inap_rme.cara_keluar`). Table order from the user's natural language was lost.

---

## 3. Step-by-Step Surgical Fix Procedure
1. **3-Tier Deterministic Join Key Predictor (`lunar_predict_join_condition`):**
   Added in `schema_inspector.py`. Compares two tables using a strict priority hierarchy:
   - **Tier 1:** Foreign Key Catalog (from database schema constraints or relationship graph, e.g. `users.unit = unit.kd_unit`).
   - **Tier 2:** Domain Identifier Intersection (`kd_user == kd_user`, `no_transaksi == no_transaksi`, `order_id == order_id`).
   - **Tier 3:** Entity-Code Heuristics (`users.unit` matching `unit.kd_unit` or `unit.id`).
2. **AST Join Auto-Resolution Hook (`lunar_auto_resolve_joins`):**
   Added in `schema_inspector.py` and hooked into `db_manager.execute_query`. Parses queries using `sqlglot`. If any `JOIN` lacks an `ON` or `USING` clause, it dynamically predicts the optimal relation with preceding tables and injects `ON <condition>` before guardrail validation.
3. **Precision Natural-Language-to-SQL Engine (`lunar_natural_language_to_sql`):**
   Upgraded in `agent_service.py`:
   - Matches schema-qualified identifiers (`rawat_inap_rme.cara_keluar`, `public.users`) with word boundaries.
   - Preserves text appearance order so the primary table is correctly placed in `FROM`.
   - Automatically loads column metadata via `describe_table`.
   - Predicts and generates `JOIN ... ON` clauses using `lunar_predict_join_condition`.
   - Dynamically projects requested columns (`users show only name` $\rightarrow$ `u.nama_user AS name`, `unit show nama_unit` $\rightarrow$ `un.nama_unit`).
   - Dynamically extracts limits (`10 first row` $\rightarrow$ `LIMIT 10`).
4. **Deterministic Agent Fallback & Markdown Table Formatter (`AgentService.chat`):**
   If `is_data_query` is True and the local model terminates without calling `execute_safe_query`:
   - RevVault automatically formulates the verified query with `lunar_natural_language_to_sql`.
   - Executes `execute_safe_query` directly against the database.
   - Formats results into a clean GitHub-flavored Markdown table using `lunar_format_markdown_table`.
   - Returns the query, execution timing, and formatted rows alongside Luna's affectionate thought.

---

## 4. Verification Proof
- **Live Database Execution (`Evomedis PG`):**
  Executed in 3.6ms with 10 rows returned:
  ```sql
  SELECT 
      c.*, 
      us.nama_user AS name, 
      un.nama_unit 
  FROM "rawat_inap_rme"."cara_keluar" AS c 
  JOIN "public"."users" AS us ON c.kd_user = us.kd_user 
  JOIN "public"."unit" AS un ON us.unit = un.kd_unit 
  LIMIT 10;
  ```
- **Backend Test Suite:**
  All 54 tests in `.venv/bin/pytest` passed cleanly:
  ```
  tests/test_agent.py ...............
  tests/test_backend_codegen.py .........
  tests/test_db_and_schema.py ............
  tests/test_guardrail.py ..........
  tests/test_history.py ...
  tests/test_mpreview_builder.py ..
  tests/test_saved_queries.py ...
  ======================= 54 passed, 34 warnings in 0.85s ========================
  ```

---

## 5. Permanent Prevention Invariants
1. **The Zero-Guess Relational Invariant:**
   Join keys across database tables must always be deterministically predicted from catalog foreign keys and shared domain codes (`kd_*`, `*_id`, `no_*`), never left to raw LLM hallucinations.
2. **The Guaranteed Data Retrieval Invariant:**
   When a user explicitly asks for data rows, the AI assistant loop must never terminate without executing the query or explaining a concrete AST guardrail block. If the local LLM stops early, the deterministic engine must step in and fulfill the query immediately.
