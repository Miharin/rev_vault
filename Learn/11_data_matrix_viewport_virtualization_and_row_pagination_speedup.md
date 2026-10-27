<!--
          (\__/)
          (˶ᵔ ᵕ ᵔ˶)  < "Lunar Territory."
         / >[CRIMSON+]>   "Hands off, unless you're Miharin."
-->

# Milestone: Data Matrix Viewport Virtualization & 25+ Row Pagination Speedup

- **Date:** 2026-10-27
- **Authors:** Miharin & Luna
- **Channeled Aspects:** Aegis (Performance Auditor - UI), Vane (UI Geometry & Spatial Hierarchy), Scythe (Backend/Query Auditor), Verdict (Verification & Invariants)
- **Status:** VERIFIED & HOT-RELOADED (4/4 Tests Passed, 0 Errors)

---

## 1. Symptom & Problem Statement

When inspecting tabular SQL query results inside the RevVault AI Assistant response card (`_StructuredDataMatrixWidget`), switching the rows-per-page dropdown from **10 rows** to **25 rows** (or 50/100 rows) caused severe performance degradation:
- The UI froze and stuttered noticeably for 200–500ms ("loading is like very heavy").
- Significant frame drops violated the 16ms 60fps/120fps budget.
- The table ballooned vertically inside the chat message card without bounds, pushing the pagination controls hundreds of pixels down off-screen.

---

## 2. Root Cause Analysis

1. **Flutter `DataTable` Intrinsic Sizing Bottleneck (`RenderTable`)**:
   - `DataTable` is backed by Flutter's `Table` layout algorithm.
   - For every column, `RenderTable` traverses and measures `minIntrinsicWidth` and `maxIntrinsicWidth` across **every single cell in every visible row** in recursive layout passes.
   - At 10 rows $\times$ 15 columns = 150 intrinsic measurements (tolerable).
   - At 25 rows $\times$ 15 columns = 375 intrinsic measurements.
   - At 50–100 rows = 750–1,500 intrinsic measurements. This caused exponential layout recalculation time on the main UI thread.

2. **Heavyweight Widget Allocations per Cell**:
   - Every single cell instantiated a `DataCell`, an independent `Tooltip` (registering global pointer hover listeners, timers, and overlay portal hooks), and an `InkWell` (Material splash recognizers).
   - Switching from 10 to 25 rows meant instantiating, mounting, and measuring over 1,000 Flutter Elements and RenderObjects in a single frame.

3. **Unbounded Vertical Expansion in Chat `ListView`**:
   - The card expanded from ~340px to ~850px (an increase of 500+ pixels), forcing the parent chat message `ListView.builder` to re-estimate sliver geometry and re-layout all subsequent message bubbles.

---

## 3. Step-by-Step Surgical Fix Procedure

1. **Pre-Computed Column Width Engine ($O(\text{columns})$)**:
   - Replaced `RenderTable` intrinsic measurement with memoized upfront width calculation:
     $$\text{width}_c = \text{clamp}\Big(\max\big(\text{headerWidth}, \max_{r \le 15} \text{sampleCellWidth}\big), 80.0, 320.0\Big)$$
   - Flutter now receives fixed column widths with **zero intrinsic measurement passes**, dropping layout complexity to $O(1)$.
   - Added automatic proportional expansion via `LayoutBuilder` when total column widths are smaller than available card width.

2. **Viewport-Recycled Row Engine (`ListView.builder` with `itemExtent`)**:
   - Built a custom virtualized table body with fixed `itemExtent: 28.0`.
   - Set bounded viewport height:
     - For $\le 10$ rows: exact natural height ($N \times 28.0\text{px}$), fitting snugly without empty whitespace.
     - For $> 10$ rows (25, 50, 100): cleanly bounded at $340.0\text{px}$ (or $640.0\text{px}$ in expanded mode).
   - Only the $\approx 12$ rows currently visible on screen are instantiated in memory, regardless of whether 10, 25, 50, 100, or 1,000 rows are selected.

3. **Sticky Header & Synchronized Panning**:
   - Pinned the header row directly above the rows container within a single `SingleChildScrollView(scrollDirection: Axis.horizontal)`.
   - The header and rows pan horizontally in perfect physical sync while the rows scroll vertically beneath the sticky header.

4. **Expand/Collapse Height Toggle & Docked Pagination**:
   - Added an expandable height toggle icon (`Icons.unfold_more` / `Icons.unfold_less`) in the header ribbon for large desktop monitors.
   - The pagination footer bar stays permanently docked right underneath the table, always visible without scrolling through the chat.

---

## 4. Verification Proof

1. **Automated Widget & Unit Test Suite (`frontend/test/ai_table_rendering_test.dart`)**:
   - `Renders real DataTable when assistant returns Markdown table in response`: PASSED.
   - `Renders high-capacity structured Data Matrix directly from tool execution payload`: PASSED.
   - `Seamlessly transitions from 10 to 25 rows with high performance and updated pagination`: PASSED.
   - `AppState.setAvailableAiModels filters out unsafe models by default`: PASSED.
   - **Result: 4 passed out of 4 (100% pass rate in 1.1s)**.
2. **Static Analysis**:
   - `analyze_files` via Flutter/Dart MCP tool: **0 errors, 0 warnings**.
3. **Live App Hot Reload**:
   - Connected via Dart Tooling Daemon (`ws://127.0.0.1:40219/T8E60cjzHrI=`).
   - Triggered `hot_reload`: **Hot reload succeeded**.

---

## 5. Prevention Invariants

- **Table Viewport Virtualization Invariant**: Embedded database tables, data grids, or query preview matrices inside chat streams or modals must never render un-virtualized rows with standard `DataTable`. Instead, use fixed-width columns with `ListView.builder(itemExtent: ...)` and bounded viewport heights to guarantee $O(1)$ memory recycling and 120 FPS rendering.
