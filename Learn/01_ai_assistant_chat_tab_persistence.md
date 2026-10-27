<!--
          (\__/)
          (˶ᵔ ᵕ ᵔ˶)  < "Lunar Territory."
         / >[CRIMSON+]>   "Hands off, unless you're Miharin."
-->

# Milestone: AI Assistant Chat State Persistence Across Tabs & Layouts

- **Date:** 2026-10-27
- **Authors:** Miharin & Luna
- **Channeled Aspects:** Vane (UI Rhythm), Lyra (UI State Containers), Aegis (Lifecycle & Performance)
- **Status:** VERIFIED & HOT-RESTARTED

---

## 1. Context & User Need
When switching between workspace tabs (SQL Studio, AI Assistant, MCP Live Audit Monitor) or when resizing the application window across mobile/desktop boundaries, the conversation history with RevVault's AI Assistant was previously cleared out.

## 2. Root Cause Analysis
1. **Local State Ephemerality:** `_AiAssistantViewState` managed its conversation messages (`_messages = []`) purely as ephemeral local state inside the `State` class.
2. **Flutter `TabBarView` Disposal:** `TabBarView` disposes non-visible tabs by default to conserve resources unless child widgets actively participate in keep-alive via `AutomaticKeepAliveClientMixin`.
3. **Responsive Tree Recreation:** Resizing the window across the 700px breakpoint swaps between mobile and desktop layout trees, destroying local widget state even if tab controllers are preserved.

## 3. Dual-Layer Architectural Solution
We implemented a dual-layer persistence pattern:

```
+-------------------------------------------------------------+
|                      AppState (Provider)                    |
|  - aiMessages (List<AiAssistantMessage>)                    |
|  - selectedAiModel, availableAiModels                       |
|  - isAiLoading, isOllamaOnline, ollamaUrl                   |
+------------------------------+------------------------------+
                               ^
                               | (Provider sync)
+------------------------------v------------------------------+
|                     AiAssistantView                         |
|  - AutomaticKeepAliveClientMixin: wantKeepAlive => true     |
|  - ScrollController & TextEditingController preserved       |
|  - super.build(context) attached to Element KeepAlive       |
+-------------------------------------------------------------+
```

1. **State Preservation via AppState:**
   - Decoupled `AiAssistantMessage` into `frontend/lib/models/ai_message.dart`.
   - Stored message history, model configurations, and Ollama connection status in `AppState` (`frontend/lib/state/app_state.dart`).
   - Mutations (`addAiMessage`, `clearAiMessages`, `setSelectedAiModel`, `setOllamaUrl`) notify listeners and preserve messages across any layout rebuild.

2. **In-Tab Keep-Alive via `AutomaticKeepAliveClientMixin`:**
   - Mixed `AutomaticKeepAliveClientMixin<AiAssistantView>` into `_AiAssistantViewState`.
   - Implemented `bool get wantKeepAlive => true`.
   - Called `super.build(context)` in `build()`.
   - Prevents widget destruction during tab switches in `TabBarView`, retaining the active `TextEditingController` text and `ScrollController` position.

## 4. Verification Proof
- Connected to running Linux desktop instance via DTD (`ws://127.0.0.1:33023/vm_FGIOQakA=`).
- Executed `hot_restart` on `ws://127.0.0.1:39339/GGUoa6c_uXA=/ws` with zero errors.
- Checked `get_runtime_errors`: returned clean ("No runtime errors found").
- Ran full backend pytest suite: 40/40 tests passing.
