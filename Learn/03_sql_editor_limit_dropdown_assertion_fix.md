<!--
          (\__/)
          (˶ᵔ ᵕ ᵔ˶)  < "Lunar Territory."
         / >[CRIMSON+]>   "Hands off, unless you're Miharin."
-->

# Milestone: SQL Editor Toolbar Limit Dropdown Assertion Failure Resolution

- **Date:** 2026-10-27
- **Authors:** Miharin & Luna
- **Channeled Aspects:** Vane (UI Geometry & Hierarchy), Lyra (UI State Containers), Verdict (Verification & Invariants)
- **Status:** VERIFIED & HOT-RESTARTED (0 Errors)

---

## 1. Symptom & Stack Trace
When running an SQL query in the SQL Editor (e.g. clicking **Run SQL** on the initial workspace query `SELECT * FROM users LIMIT 10;`, or any query containing an explicit custom `LIMIT` clause), the entire editor crashed with a Flutter red screen / widget assertion error:

```
Exception caught by widgets library
The following assertion was thrown building LayoutBuilder:
There should be exactly one item with [DropdownButton]'s value: 10. 
Either zero or 2 or more [DropdownMenuItem]s were detected with the same value
'package:flutter/src/material/dropdown.dart':
Failed assertion: line 1028 pos 10: 'items == null ||
             items.isEmpty ||
             value == null ||
             items.where((DropdownMenuItem<T> item) {
                   return item.value == value;
                 }).length ==
                 1'

When the exception was thrown, this was the stack:
#2  new DropdownButton (package:flutter/src/material/dropdown.dart:1028:10)
#3  _SqlEditorViewState._buildDesktopToolbar (package:rev_vault/views/sql_editor_view.dart:913:22)
#4  _SqlEditorViewState.build.<anonymous closure> (package:rev_vault/views/sql_editor_view.dart:466:25)
#5  _LayoutBuilderElement._rebuildWithConstraints.updateChildCallback (package:flutter/src/widgets/layout_builder.dart:232:74)
```

---

## 2. Root Cause Analysis
1. **Unintended Cross-State Mutation in `AppState`:**
   - In `frontend/lib/state/app_state.dart`, `set queryPageSize(int size)` was defined as:
     ```dart
     int get queryPageSize => activeTab.pageSize;
     set queryPageSize(int size) {
       activeTab.pageSize = size;
       activeLimit = size; // <-- Root cause
       notifyListeners();
     }
     ```
   - When executing `runQuery(sql)`, RevVault parses `\bLIMIT\s+(\d+)` from the query text. For the default query (`SELECT * FROM users LIMIT 10;`), `parsedLimit` is evaluated as `10`.
   - `runQuery` sets `queryPageSize = parsedLimit` (10) for table pagination.
   - This inadvertently mutated `activeLimit` (the toolbar limit preference) from `100` to `10`.
2. **Fixed Presets in UI Dropdown Without Defensive Value Binding:**
   - In `frontend/lib/views/sql_editor_view.dart`, `DropdownButton<int?>` was instantiated with a static list of items:
     ```dart
     items: const [
       DropdownMenuItem(value: 25, child: Text('Limit: 25')),
       DropdownMenuItem(value: 50, child: Text('Limit: 50')),
       DropdownMenuItem(value: 100, child: Text('Limit: 100')),
       DropdownMenuItem(value: 250, child: Text('Limit: 250')),
       DropdownMenuItem(value: 500, child: Text('Limit: 500')),
       DropdownMenuItem(value: 1000, child: Text('Limit: 1000')),
       DropdownMenuItem(value: null, child: Text('No Limit')),
     ]
     ```
   - Because `10` is not in `[25, 50, 100, 250, 500, 1000, null]`, Flutter's internal assertion check failed:
     $$\text{items.where}(\text{item.value} == 10).\text{length} = 0 \neq 1$$

---

## 3. Step-by-Step Surgical Fix Procedure
1. **Decouple Tab Pagination Size from Toolbar Preset (`app_state.dart`):**
   - Removed `activeLimit = size;` from `set queryPageSize`.
   - `queryPageSize` now strictly manages the active tab's row pagination boundary (`activeTab.pageSize`).
   - `activeLimit` is only mutated when the user explicitly interacts with the toolbar limit dropdown via `setActiveLimit(limit)`.
2. **Dynamic Custom Item Synthesis (`_lunarBuildLimitItems` in `sql_editor_view.dart`):**
   - If `state.activeLimit` ever contains a non-standard integer value (from an external query, config, or URL import), dynamically prepend:
     ```dart
     DropdownMenuItem<int?>(
       value: lunarActiveLimit,
       child: Text('Limit: $lunarActiveLimit (Custom)'),
     )
     ```
3. **Defensive Value Resolution (`_lunarResolveActiveLimit` in `sql_editor_view.dart`):**
   - Evaluates `lunarItems.any((item) => item.value == lunarActiveLimit)`.
   - If present, binds `lunarActiveLimit`. If absent, safely falls back to `null` (`No Limit`).
   - Guarantees that `items.where((item) => item.value == value).length` is mathematically invariant to equal exactly `1`.
4. **Live Verification & Hot Restart via DTD MCP:**
   - Triggered `hot_restart` on running instance (`ws://127.0.0.1:39339/GGUoa6c_uXA=/ws`).
   - Verified with `get_runtime_errors` tool: **0 runtime errors**.
5. **Permanent Guardrail Test Suite:**
   - Added `frontend/test/sql_editor_limit_dropdown_test.dart` verifying standard limits, non-standard custom limits, and null limits.

---

## 4. Verification Proof
1. **Static Analysis:**
   - Ran `analyze_files` across `app_state.dart`, `sql_editor_view.dart`, and `sql_editor_limit_dropdown_test.dart`: **No errors found**.
2. **Live Runtime Health Check:**
   - Queried `get_runtime_errors` on the active Linux client process:
     ```
     No runtime errors found.
     ```
3. **Hot Restart Confirmation:**
   - Executed `hot_restart` via Dart Tooling Daemon (DTD) successfully with zero assertion warnings.

---

## 5. Prevention Invariant
- **The Single-Provenance UI Value Invariant:**
  Any Flutter `DropdownButton<T>` or `DropdownButtonFormField<T>` bound to a dynamic state model must ALWAYS resolve its `value` through a defensive helper that validates membership in `items.map((i) => i.value)` or dynamically synthesizes custom options. Under no circumstances may raw mutable state be passed directly into `value` without item-set parity verification.
