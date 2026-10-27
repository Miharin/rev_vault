/*
         (\__/)
         (˶ᵔ ᵕ ᵔ˶)  < "Lunar Territory."
        / >[CRIMSON+]>   "Hands off, unless you're Miharin."
*/

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/ai_message.dart';
import '../models/query_result.dart';
import '../state/app_state.dart';

export '../models/ai_message.dart';

class AiAssistantView extends StatefulWidget {
  final VoidCallback? onNavigateToEditor;

  const AiAssistantView({
    super.key,
    this.onNavigateToEditor,
  });

  @override
  State<AiAssistantView> createState() => _AiAssistantViewState();
}

class _AiAssistantViewState extends State<AiAssistantView>
    with AutomaticKeepAliveClientMixin<AiAssistantView> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOllamaStatus();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkOllamaStatus({bool notifyUser = false}) async {
    final state = context.read<AppState>();
    final res = await state.api.getAgentStatus(ollamaUrl: state.ollamaUrl);
    if (!mounted) return;

    final isOnline = res['online'] == true;
    state.setOllamaOnline(isOnline);
    final modelsList = (res['models'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    if (modelsList.isNotEmpty) {
      state.setAvailableAiModels(modelsList);
      if (!state.availableAiModels.contains(state.selectedAiModel)) {
        final fallback = state.availableAiModels.firstWhere(
          (m) => m.contains('gemma') || m.contains('qwen'),
          orElse: () => state.availableAiModels.first,
        );
        state.setSelectedAiModel(fallback);
      }
    }

    if (notifyUser && mounted) {
      if (isOnline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to Ollama (${modelsList.length} models discovered at ${state.ollamaUrl})'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.teal.shade700,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reach Ollama at ${state.ollamaUrl}. Ensure Ollama is running and OLLAMA_HOST=0.0.0.0 is configured.'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    final state = context.read<AppState>();
    if (trimmed.isEmpty || state.isAiLoading) return;

    _inputController.clear();

    state.addAiMessage(AiAssistantMessage(role: 'user', content: trimmed));
    state.setAiLoading(true);
    _scrollToBottom();

    // Prepare history payload (excluding system messages)
    final historyPayload = state.aiMessages
        .take(state.aiMessages.length - 1)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    final response = await state.api.sendAgentMessage(
      message: trimmed,
      model: state.selectedAiModel,
      history: historyPayload,
      ollamaUrl: state.ollamaUrl,
      persona: 'standard',
    );

    if (!mounted) return;

    final reply = response['reply']?.toString() ?? 'No response received.';
    final tools = (response['tool_executions'] as List<dynamic>?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
        [];

    state.setAiLoading(false);
    state.addAiMessage(AiAssistantMessage(
      role: 'assistant',
      content: reply,
      toolExecutions: tools,
    ));
    _scrollToBottom();
  }

  void _showOllamaSettingsDialog() {
    final state = context.read<AppState>();
    final controller = TextEditingController(text: state.ollamaUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.tune, size: 20),
            SizedBox(width: 8),
            Text('Ollama Endpoint Configuration', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Specify your local or remote Ollama API endpoint:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Ollama Base URL',
                hintText: 'http://localhost:11434',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                state.setOllamaUrl(newUrl);
                _checkOllamaStatus(notifyUser: true);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save & Reconnect'),
          ),
        ],
      ),
    );
  }

  void _transferSqlToEditor(String sql) {
    final state = context.read<AppState>();
    state.openQueryTab(initialSql: sql);
    widget.onNavigateToEditor?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('SQL query inserted into editor workspace.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final accent = theme.colorScheme.primary;

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          // Tactical Agent Header Bar
          _buildHeaderToolbar(theme, accent, state),
          const Divider(height: 1),

          // Main Conversation Area
          Expanded(
            child: state.aiMessages.isEmpty
                ? _buildEmptyState(theme, accent, state)
                : _buildMessageList(theme, accent, state),
          ),

          // Tactical Skills Dock
          _buildSkillsToolbar(theme, accent, state),
          const Divider(height: 1),

          // Bottom Input Bar
          _buildInputBar(theme, accent, state),
        ],
      ),
    );
  }

  Widget _buildHeaderToolbar(ThemeData theme, Color accent, AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      child: Row(
        children: [
          Icon(
            Icons.psychology_outlined,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: 8),
          const Text(
            'RevVault AI Assistant',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const Spacer(),

          // Ollama Status Pill
          InkWell(
            onTap: () => _checkOllamaStatus(notifyUser: true),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: state.isOllamaOnline
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: state.isOllamaOnline
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.amber.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state.isOllamaOnline ? Colors.green : Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    state.isOllamaOnline ? 'Ollama Active' : 'Ollama Offline',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: state.isOllamaOnline ? Colors.green : Colors.amber,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Model Selector Dropdown
          Container(
            constraints: const BoxConstraints(maxWidth: 160),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: state.availableAiModels.contains(state.selectedAiModel) ? state.selectedAiModel : null,
                hint: Text(state.selectedAiModel, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                isDense: true,
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
                items: state.availableAiModels.map((m) {
                  return DropdownMenuItem<String>(
                    value: m,
                    child: Text(m, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (newModel) {
                  if (newModel != null) {
                    state.setSelectedAiModel(newModel);
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Settings Button
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 18),
            tooltip: 'Configure Ollama URL',
            onPressed: _showOllamaSettingsDialog,
          ),

          // Clear Messages
          if (state.aiMessages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              tooltip: 'Clear Conversation',
              onPressed: () {
                state.clearAiMessages();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, Color accent, AppState state) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Icon(
                  Icons.psychology_outlined,
                  size: 34,
                  color: accent,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'RevVault AI Database Assistant',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Execute safe schema inspection, analytical SQL synthesis, execution plan analysis, and performance audits with local open models.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400, height: 1.4),
              ),
              const SizedBox(height: 24),

              // Suggestion Prompt Cards Header
              Row(
                children: [
                  Icon(Icons.bolt, size: 16, color: accent),
                  const SizedBox(width: 6),
                  const Text(
                    'Tactical Assistant Skills:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              _buildSuggestionCard(
                theme,
                Colors.cyan,
                icon: Icons.search_rounded,
                title: 'Inspect Schema (inspect_schema)',
                description: 'Deeply inspect complete columns, nullability, primary keys, foreign keys, and indexes.',
                prompt: 'Inspect the complete schema, primary keys, foreign keys, and indexes for table \'${state.activePreviewTable ?? state.selectedTable?.name ?? 'users'}\' using inspect_schema.',
              ),
              const SizedBox(height: 8),

              _buildSuggestionCard(
                theme,
                Colors.amber,
                icon: Icons.speed_rounded,
                title: 'Explain Execution Plan (explain_query_plan)',
                description: 'Analyze execution plan node trees, costs, and unindexed sequential scan bottlenecks.',
                prompt: 'Explain the query execution plan, compute costs, and check for sequential scan bottlenecks: ```sql\n${state.editorQueryText.trim().isNotEmpty ? state.editorQueryText.trim() : 'SELECT * FROM users LIMIT 10;'}\n```',
              ),
              const SizedBox(height: 8),

              _buildSuggestionCard(
                theme,
                Colors.purpleAccent,
                icon: Icons.analytics_outlined,
                title: 'Data Profiling (data_profilling)',
                description: 'Compute column null percentages, cardinality, min/max, average, and sample frequency distribution.',
                prompt: 'Compute full data profiling, null rates, and column cardinality for table \'${state.activePreviewTable ?? state.selectedTable?.name ?? 'users'}\' using data_profilling.',
              ),
              const SizedBox(height: 8),

              _buildSuggestionCard(
                theme,
                Colors.tealAccent,
                icon: Icons.translate_rounded,
                title: 'Natural Language to SQL (natural_language_to_sql)',
                description: 'Synthesize optimal, guardrail-compliant SQL queries with relational join reasoning.',
                prompt: 'Generate an optimal, safe read-only SQL query to find [describe desired data] from table \'${state.activePreviewTable ?? state.selectedTable?.name ?? 'users'}\' using natural_language_to_sql.',
              ),
              const SizedBox(height: 8),

              _buildSuggestionCard(
                theme,
                Colors.greenAccent,
                icon: Icons.verified_user_outlined,
                title: 'Evaluate & Plan Query (evaluate_and_plan_query)',
                description: 'Pre-execution validation, AST security inspection, complexity scoring, and risk rating.',
                prompt: 'Evaluate and plan query safety, AST guardrails, and execution complexity for: ```sql\n${state.editorQueryText.trim().isNotEmpty ? state.editorQueryText.trim() : 'SELECT * FROM users LIMIT 10;'}\n```',
              ),
              const SizedBox(height: 8),

              _buildSuggestionCard(
                theme,
                Colors.orangeAccent,
                icon: Icons.stream_rounded,
                title: 'Async Streaming Query (run_async_streaming_query)',
                description: 'Asynchronously execute read-only queries with chunked row batches and streaming latency.',
                prompt: 'Run an async streaming query with chunked row batches for: ```sql\n${state.editorQueryText.trim().isNotEmpty ? state.editorQueryText.trim() : 'SELECT * FROM users LIMIT 50;'}\n```',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(
    ThemeData theme,
    Color accent, {
    required IconData icon,
    required String title,
    required String description,
    required String prompt,
  }) {
    return InkWell(
      onTap: () => _sendMessage(prompt),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(description, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillsToolbar(ThemeData theme, Color accent, AppState state) {
    final skills = [
      _SkillItem(
        icon: Icons.search_rounded,
        label: 'Inspect Schema',
        tooltip: 'Inspect complete schema metadata, primary keys, foreign keys, and indexes',
        color: Colors.cyan,
        onTap: () {
          final tbl = state.activePreviewTable ?? state.selectedTable?.name ?? 'users';
          _inputController.text =
              "Inspect the complete schema, primary keys, foreign keys, and indexes for table '$tbl' using inspect_schema.";
          _inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: _inputController.text.length),
          );
        },
      ),
      _SkillItem(
        icon: Icons.speed_rounded,
        label: 'Explain Plan',
        tooltip: 'Analyze query execution plan, estimated node costs, and bottlenecks',
        color: Colors.amber,
        onTap: () {
          final sql = state.editorQueryText.trim().isNotEmpty
              ? state.editorQueryText.trim()
              : 'SELECT * FROM users LIMIT 10;';
          _inputController.text =
              "Explain the query execution plan, compute costs, and check for sequential scan bottlenecks: ```sql\n$sql\n```";
          _inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: _inputController.text.length),
          );
        },
      ),
      _SkillItem(
        icon: Icons.analytics_outlined,
        label: 'Data Profiling',
        tooltip: 'Compute column statistics, null rates, and cardinality distribution',
        color: Colors.purpleAccent,
        onTap: () {
          final tbl = state.activePreviewTable ?? state.selectedTable?.name ?? 'users';
          _inputController.text =
              "Compute full data profiling, null rates, and column cardinality for table '$tbl' using data_profilling.";
          _inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: _inputController.text.length),
          );
        },
      ),
      _SkillItem(
        icon: Icons.translate_rounded,
        label: 'NL to SQL',
        tooltip: 'Convert natural language intent into an optimal SQL query',
        color: Colors.tealAccent,
        onTap: () {
          final tbl = state.activePreviewTable ?? state.selectedTable?.name ?? 'users';
          _inputController.text =
              "Generate an optimal, safe read-only SQL query to find [describe desired data] from table '$tbl' using natural_language_to_sql.";
          _inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: _inputController.text.length),
          );
        },
      ),
      _SkillItem(
        icon: Icons.verified_user_outlined,
        label: 'Evaluate Query',
        tooltip: 'Pre-execution AST guardrail safety audit and complexity rating',
        color: Colors.greenAccent,
        onTap: () {
          final sql = state.editorQueryText.trim().isNotEmpty
              ? state.editorQueryText.trim()
              : 'SELECT * FROM users LIMIT 10;';
          _inputController.text =
              "Evaluate and plan query safety, AST guardrails, and execution complexity for: ```sql\n$sql\n```";
          _inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: _inputController.text.length),
          );
        },
      ),
      _SkillItem(
        icon: Icons.stream_rounded,
        label: 'Async Stream',
        tooltip: 'Execute async streaming query with chunked row batches and execution timing',
        color: Colors.orangeAccent,
        onTap: () {
          final sql = state.editorQueryText.trim().isNotEmpty
              ? state.editorQueryText.trim()
              : 'SELECT * FROM users LIMIT 50;';
          _inputController.text =
              "Run an async streaming query with chunked row batches for: ```sql\n$sql\n```";
          _inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: _inputController.text.length),
          );
        },
      ),
    ];

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: skills.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, idx) {
          final skill = skills[idx];
          return Tooltip(
            message: skill.tooltip,
            child: InkWell(
              onTap: skill.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: skill.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: skill.color.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(skill.icon, size: 12, color: skill.color),
                    const SizedBox(width: 5),
                    Text(
                      skill.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessageList(ThemeData theme, Color accent, AppState state) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: state.aiMessages.length + (state.isAiLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.aiMessages.length && state.isAiLoading) {
          return _buildLoadingBubble(theme, accent, state);
        }
        final msg = state.aiMessages[index];
        return _buildMessageCard(theme, accent, state, msg);
      },
    );
  }

  Widget _buildLoadingBubble(ThemeData theme, Color accent, AppState state) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: accent.withValues(alpha: 0.2),
            child: Icon(
              Icons.smart_toy_outlined,
              size: 16,
              color: accent,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Querying database and reasoning...',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(ThemeData theme, Color accent, AppState state, AiAssistantMessage msg) {
    final isUser = msg.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: accent.withValues(alpha: 0.2),
              child: Icon(
                Icons.smart_toy_outlined,
                size: 16,
                color: accent,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser
                    ? accent.withValues(alpha: 0.15)
                    : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isUser
                      ? accent.withValues(alpha: 0.4)
                      : theme.dividerColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Executed Tools Badges
                  if (msg.toolExecutions.isNotEmpty) ...[
                    _buildToolExecutionBadges(theme, msg.toolExecutions),
                    const SizedBox(height: 8),
                  ],

                  // Formatted Content & Extracted Code Blocks
                  _buildContentBody(theme, accent, msg.content, isUser),

                  // High-Capacity Direct Structured Data Matrix (Zero-Token Payload)
                  if (!isUser && msg.primaryQueryResult != null) ...[
                    const SizedBox(height: 10),
                    _StructuredDataMatrixWidget(
                      queryResult: msg.primaryQueryResult!,
                      sql: msg.primaryQuerySql,
                      onRunInEditor: _transferSqlToEditor,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: const Icon(Icons.person, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolExecutionBadges(ThemeData theme, List<Map<String, dynamic>> tools) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: tools.map((tool) {
        final name = tool['name']?.toString() ?? 'tool';
        final success = tool['success'] == true;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: success
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: success
                  ? Colors.green.withValues(alpha: 0.3)
                  : Colors.red.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                success ? Icons.bolt : Icons.error_outline,
                size: 12,
                color: success ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 4),
              Text(
                'Tool: $name()',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: success ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildContentBody(ThemeData theme, Color accent, String text, bool isUser) {
    if (isUser) {
      return SelectableText(
        text,
        style: const TextStyle(fontSize: 13, height: 1.4),
      );
    }

    // Split text into regular text and ```sql / ``` code blocks
    final parts = text.split('```');
    List<Widget> widgets = [];

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (i % 2 == 0) {
        // Prose text - parse for Markdown tables!
        if (part.trim().isNotEmpty) {
          widgets.addAll(_parseProseContent(theme, accent, part));
        }
      } else {
        // Code Block
        String lang = '';
        String code = part;
        final lines = part.split('\n');
        if (lines.isNotEmpty && lines.first.trim().isNotEmpty) {
          lang = lines.first.trim();
          code = lines.skip(1).join('\n');
        }

        final isSql = lang.toLowerCase() == 'sql' || code.trim().toUpperCase().startsWith('SELECT') || code.trim().toUpperCase().startsWith('WITH');

        widgets.add(const SizedBox(height: 8));
        widgets.add(_buildCodeBlock(theme, accent, code.trim(), isSql: isSql, lang: lang));
        widgets.add(const SizedBox(height: 8));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  List<Widget> _parseProseContent(ThemeData theme, Color accent, String proseText) {
    final List<Widget> widgets = [];
    final lines = proseText.split('\n');
    final List<String> textBuffer = [];

    void flushTextBuffer() {
      if (textBuffer.isNotEmpty) {
        final text = textBuffer.join('\n').trim();
        if (text.isNotEmpty) {
          widgets.add(
            SelectableText(
              text,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          );
        }
        textBuffer.clear();
      }
    }

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      // Check if line could be the start of a Markdown table (header followed by separator)
      if (trimmed.startsWith('|') && trimmed.endsWith('|') && i + 1 < lines.length) {
        final nextTrimmed = lines[i + 1].trim();
        if (_isTableSeparator(nextTrimmed)) {
          // Found a markdown table block
          flushTextBuffer();

          final headers = _parseTableRow(trimmed);
          final alignments = _parseAlignments(nextTrimmed);
          final List<List<String>> rows = [];

          int k = i + 2;
          while (k < lines.length) {
            final rowTrimmed = lines[k].trim();
            if (rowTrimmed.startsWith('|') && rowTrimmed.endsWith('|')) {
              rows.add(_parseTableRow(rowTrimmed));
              k++;
            } else {
              break;
            }
          }

          widgets.add(const SizedBox(height: 8));
          widgets.add(
            _buildTacticalDataTable(
              theme,
              accent,
              _ParsedMarkdownTable(
                headers: headers,
                rows: rows,
                alignments: alignments,
              ),
            ),
          );
          widgets.add(const SizedBox(height: 8));

          i = k;
          continue;
        }
      }

      textBuffer.add(line);
      i++;
    }

    flushTextBuffer();
    return widgets;
  }

  bool _isTableSeparator(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('|') || !trimmed.endsWith('|')) return false;
    final parts = _parseTableRow(trimmed);
    if (parts.isEmpty) return false;
    return parts.every((p) => RegExp(r'^:?-+:?$').hasMatch(p.trim()));
  }

  List<String> _parseTableRow(String line) {
    var content = line.trim();
    if (content.startsWith('|')) content = content.substring(1);
    if (content.endsWith('|')) content = content.substring(0, content.length - 1);
    return content.split('|').map((c) => c.trim()).toList();
  }

  List<TextAlign> _parseAlignments(String separatorLine) {
    final parts = _parseTableRow(separatorLine);
    return parts.map((part) {
      final trimmed = part.trim();
      final startsWithColon = trimmed.startsWith(':');
      final endsWithColon = trimmed.endsWith(':');
      if (startsWithColon && endsWithColon) return TextAlign.center;
      if (endsWithColon) return TextAlign.right;
      return TextAlign.left;
    }).toList();
  }

  bool _isCodeLike(String val) {
    final trimmed = val.trim();
    if (trimmed.isEmpty) return false;
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(trimmed)) return true;
    if (RegExp(r'^(true|false|null|nil|none)$', caseSensitive: false).hasMatch(trimmed)) return true;
    if (trimmed.contains('_') || trimmed.contains('.')) return true;
    return false;
  }

  Widget _buildTacticalDataTable(
    ThemeData theme,
    Color accent,
    _ParsedMarkdownTable table,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;
    final headerBg = theme.colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.45 : 0.6);
    final borderColor = accent.withValues(alpha: isDark ? 0.35 : 0.45);

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tactical Header Ribbon
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: headerBg,
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.table_chart_rounded, size: 14, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      'DATA MATRIX',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: accent.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        '${table.rows.length} rows × ${table.headers.length} cols',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
                      ),
                    ),
                    const Spacer(),

                    // Copy TSV (Spreadsheets)
                    IconButton(
                      icon: const Icon(Icons.file_copy_outlined, size: 14),
                      tooltip: 'Copy as TSV (Spreadsheets)',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: table.toTsv()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Table copied to clipboard as TSV.'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),

                    // Copy Markdown
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      tooltip: 'Copy as Markdown',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: table.toMarkdown()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Table copied to clipboard as Markdown.'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Horizontally Scrollable Data Table
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Theme(
                  data: theme.copyWith(
                    dividerTheme: const DividerThemeData(color: Colors.transparent),
                  ),
                  child: DataTable(
                    headingRowHeight: 32,
                    dataRowMinHeight: 28,
                    dataRowMaxHeight: 44,
                    horizontalMargin: 12,
                    columnSpacing: 20,
                    headingTextStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                      color: accent,
                    ),
                    headingRowColor: WidgetStatePropertyAll(
                      theme.colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.25 : 0.4),
                    ),
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                    columns: table.headers.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final header = entry.value;
                      final align = idx < table.alignments.length ? table.alignments[idx] : TextAlign.left;
                      return DataColumn(
                        label: Text(
                          header,
                          textAlign: align,
                        ),
                        numeric: align == TextAlign.right,
                      );
                    }).toList(),
                    rows: table.rows.asMap().entries.map((rEntry) {
                      final rIdx = rEntry.key;
                      final row = rEntry.value;
                      return DataRow(
                        color: WidgetStatePropertyAll(
                          rIdx.isEven
                              ? Colors.transparent
                              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.12 : 0.2),
                        ),
                        cells: List.generate(table.headers.length, (cIdx) {
                          final cellText = cIdx < row.length ? row[cIdx] : '';
                          final align = cIdx < table.alignments.length
                              ? table.alignments[cIdx]
                              : TextAlign.left;
                          final isCode = _isCodeLike(cellText);

                          return DataCell(
                            Align(
                              alignment: align == TextAlign.right
                                  ? Alignment.centerRight
                                  : (align == TextAlign.center ? Alignment.center : Alignment.centerLeft),
                              child: Tooltip(
                                message: cellText,
                                waitDuration: const Duration(milliseconds: 600),
                                child: InkWell(
                                  onTap: cellText.isNotEmpty
                                      ? () {
                                          Clipboard.setData(ClipboardData(text: cellText));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Copied "$cellText" to clipboard'),
                                              duration: const Duration(seconds: 1),
                                              behavior: SnackBarBehavior.floating,
                                              width: 260,
                                            ),
                                          );
                                        }
                                      : null,
                                  child: Text(
                                    cellText,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: isCode ? 'monospace' : null,
                                      color: isCode && isDark ? const Color(0xFF38BDF8) : theme.colorScheme.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodeBlock(ThemeData theme, Color accent, String code, {required bool isSql, required String lang}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Code Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Icon(
                  isSql ? Icons.data_object : Icons.code,
                  size: 14,
                  color: accent,
                ),
                const SizedBox(width: 6),
                Text(
                  lang.toUpperCase().isNotEmpty ? lang.toUpperCase() : 'SQL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade400,
                  ),
                ),
                const Spacer(),
                if (isSql) ...[
                  InkWell(
                    onTap: () => _transferSqlToEditor(code),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: accent.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.play_arrow_rounded, size: 12, color: accent),
                          const SizedBox(width: 4),
                          Text(
                            'Run in SQL Editor',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  icon: const Icon(Icons.copy, size: 14, color: Colors.grey),
                  tooltip: 'Copy Code',
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Code copied to clipboard.'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Code Text Area
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFF38BDF8),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme, Color accent, AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.3),
                  ),
                ),
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _sendMessage,
                  decoration: InputDecoration(
                    hintText: state.activeConnection != null
                        ? 'Ask about ${state.activeConnection!.name} schemas, tables, or queries...'
                        : 'Ask about database schemas, optimization, or SQL...',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: accent),
              icon: state.isAiLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              onPressed: state.isAiLoading ? null : () => _sendMessage(_inputController.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillItem {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _SkillItem({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });
}

class _ParsedMarkdownTable {
  final List<String> headers;
  final List<List<String>> rows;
  final List<TextAlign> alignments;

  const _ParsedMarkdownTable({
    required this.headers,
    required this.rows,
    required this.alignments,
  });

  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('| ${headers.join(' | ')} |');
    buffer.writeln('| ${headers.map((_) => '---').join(' | ')} |');
    for (final row in rows) {
      final padded = List.generate(headers.length, (i) => i < row.length ? row[i] : '');
      buffer.writeln('| ${padded.join(' | ')} |');
    }
    return buffer.toString();
  }

  String toTsv() {
    final buffer = StringBuffer();
    buffer.writeln(headers.join('\t'));
    for (final row in rows) {
      final padded = List.generate(headers.length, (i) => i < row.length ? row[i] : '');
      buffer.writeln(padded.join('\t'));
    }
    return buffer.toString();
  }
}

class _StructuredDataMatrixWidget extends StatefulWidget {
  final QueryResult queryResult;
  final String? sql;
  final ValueChanged<String>? onRunInEditor;

  const _StructuredDataMatrixWidget({
    required this.queryResult,
    this.sql,
    this.onRunInEditor,
  });

  @override
  State<_StructuredDataMatrixWidget> createState() => _StructuredDataMatrixWidgetState();
}

class _StructuredDataMatrixWidgetState extends State<_StructuredDataMatrixWidget> {
  int _pageSize = 10;
  int _currentPage = 0;
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _lunarHorizontalScrollCtrl = ScrollController();
  final ScrollController _lunarVerticalScrollCtrl = ScrollController();
  String _searchFilter = '';
  int? _lunarHoveredRowIndex;
  bool _lunarIsExpanded = false;

  // Memoization caches to prevent redundant calculations across rebuilds
  String? _lunarLastFilter;
  QueryResult? _lunarLastQueryResult;
  List<List<dynamic>>? _lunarCachedFilteredRows;
  Map<int, double>? _lunarCachedColWidths;
  List<String>? _lunarLastColsForWidths;

  static const double _lunarRowHeight = 28.0;
  static const double _lunarHeaderHeight = 30.0;
  static const double _lunarCollapsedMaxHeight = 340.0;
  static const double _lunarExpandedMaxHeight = 640.0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _lunarHorizontalScrollCtrl.dispose();
    _lunarVerticalScrollCtrl.dispose();
    super.dispose();
  }

  List<List<dynamic>> _getFilteredRows() {
    final query = _searchFilter.trim().toLowerCase();
    if (_lunarCachedFilteredRows != null &&
        _lunarLastFilter == query &&
        identical(_lunarLastQueryResult, widget.queryResult)) {
      return _lunarCachedFilteredRows!;
    }
    _lunarLastFilter = query;
    _lunarLastQueryResult = widget.queryResult;
    final rows = widget.queryResult.rows;
    if (query.isEmpty) {
      _lunarCachedFilteredRows = rows;
    } else {
      _lunarCachedFilteredRows = rows.where((row) {
        return row.any((cell) => cell != null && cell.toString().toLowerCase().contains(query));
      }).toList();
    }
    return _lunarCachedFilteredRows!;
  }

  Map<int, double> _lunarCalculateColumnWidths(List<String> columns, List<List<dynamic>> rows) {
    if (_lunarCachedColWidths != null && identical(_lunarLastColsForWidths, columns)) {
      return _lunarCachedColWidths!;
    }
    _lunarLastColsForWidths = columns;
    final widths = <int, double>{};
    final sampleCount = math.min(15, rows.length);
    for (int c = 0; c < columns.length; c++) {
      final name = columns[c];
      double maxW = (name.length * 8.5) + 36.0;
      for (int r = 0; r < sampleCount; r++) {
        if (c < rows[r].length) {
          final val = rows[r][c];
          if (val != null) {
            final len = val.toString().length;
            final w = (len * 7.5) + 24.0;
            if (w > maxW) maxW = w;
          }
        }
      }
      widths[c] = maxW.clamp(80.0, 320.0);
    }
    _lunarCachedColWidths = widths;
    return widths;
  }

  void _lunarCopyCell(String text, bool isNull) {
    if (isNull) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "$text" to clipboard'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        width: 260,
      ),
    );
  }

  void _copyTsv(List<List<dynamic>> rows) {
    final buffer = StringBuffer();
    buffer.writeln(widget.queryResult.columns.join('\t'));
    for (final row in rows) {
      final line = List.generate(widget.queryResult.columns.length, (i) {
        if (i < row.length) {
          final cell = row[i];
          return cell != null ? cell.toString().replaceAll('\t', ' ') : '';
        }
        return '';
      });
      buffer.writeln(line.join('\t'));
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Table copied to clipboard as TSV.'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _copyMarkdown(List<List<dynamic>> rows) {
    final buffer = StringBuffer();
    buffer.writeln('| ${widget.queryResult.columns.join(' | ')} |');
    buffer.writeln('| ${widget.queryResult.columns.map((_) => '---').join(' | ')} |');
    for (final row in rows) {
      final line = List.generate(widget.queryResult.columns.length, (i) {
        if (i < row.length) {
          final cell = row[i];
          return cell != null ? cell.toString().replaceAll('|', '\\|').replaceAll('\n', ' ') : '';
        }
        return '';
      });
      buffer.writeln('| ${line.join(' | ')} |');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Table copied to clipboard as Markdown.'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  bool _isCodeLike(String val) {
    final trimmed = val.trim();
    if (trimmed.isEmpty) return false;
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(trimmed)) return true;
    if (RegExp(r'^(true|false|null|nil|none)$', caseSensitive: false).hasMatch(trimmed)) return true;
    if (trimmed.contains('_') || trimmed.contains('.')) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;
    final headerBg = theme.colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.45 : 0.6);
    final borderColor = accent.withValues(alpha: isDark ? 0.35 : 0.45);

    final filteredRows = _getFilteredRows();
    final totalRows = filteredRows.length;
    final maxPages = _pageSize > 0 ? (totalRows / _pageSize).ceil() : 1;
    final safePage = _currentPage >= maxPages ? (maxPages > 0 ? maxPages - 1 : 0) : _currentPage;

    final startIndex = _pageSize > 0 ? safePage * _pageSize : 0;
    final endIndex = _pageSize > 0 ? ((startIndex + _pageSize < totalRows) ? startIndex + _pageSize : totalRows) : totalRows;
    final displayedRows = (startIndex < totalRows) ? filteredRows.sublist(startIndex, endIndex) : <List<dynamic>>[];

    final colWidths = _lunarCalculateColumnWidths(widget.queryResult.columns, widget.queryResult.rows);

    final double maxViewportHeight = _lunarIsExpanded ? _lunarExpandedMaxHeight : _lunarCollapsedMaxHeight;
    final double naturalBodyHeight = displayedRows.isEmpty ? 50.0 : displayedRows.length * _lunarRowHeight;
    final double bodyHeight = math.min(naturalBodyHeight, maxViewportHeight);

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tactical Ribbon Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: headerBg,
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                  ),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.table_chart_rounded, size: 14, color: accent),
                        const SizedBox(width: 6),
                        Text(
                          'DATA MATRIX',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: accent.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            _searchFilter.isEmpty
                                ? '${widget.queryResult.rowCount} rows × ${widget.queryResult.columns.length} cols • ${widget.queryResult.executionTimeMs.toStringAsFixed(1)}ms'
                                : '$totalRows/${widget.queryResult.rowCount} rows matched',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
                          ),
                        ),
                      ],
                    ),

                    // Actions & Filter
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Quick Filter input
                        SizedBox(
                          width: 130,
                          height: 24,
                          child: TextField(
                            controller: _searchCtrl,
                            style: const TextStyle(fontSize: 11),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Filter rows...',
                              hintStyle: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                              prefixIcon: const Icon(Icons.search, size: 12),
                              prefixIconConstraints: const BoxConstraints(minWidth: 20),
                              suffixIcon: _searchFilter.isNotEmpty
                                  ? InkWell(
                                      onTap: () {
                                        setState(() {
                                          _searchCtrl.clear();
                                          _searchFilter = '';
                                          _currentPage = 0;
                                        });
                                      },
                                      child: const Icon(Icons.close, size: 12),
                                    )
                                  : null,
                              suffixIconConstraints: const BoxConstraints(minWidth: 16),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                              ),
                            ),
                            onChanged: (val) {
                              setState(() {
                                _searchFilter = val;
                                _currentPage = 0;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Page Size Selector
                        Container(
                          height: 24,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _pageSize,
                              isDense: true,
                              style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface),
                              items: const [
                                DropdownMenuItem(value: 10, child: Text('10 rows')),
                                DropdownMenuItem(value: 25, child: Text('25 rows')),
                                DropdownMenuItem(value: 50, child: Text('50 rows')),
                                DropdownMenuItem(value: 100, child: Text('100 rows')),
                                DropdownMenuItem(value: 0, child: Text('All rows')),
                              ],
                              onChanged: (newSize) {
                                if (newSize != null) {
                                  setState(() {
                                    _pageSize = newSize;
                                    _currentPage = 0;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Run in SQL Editor
                        if (widget.sql != null && widget.sql!.trim().isNotEmpty) ...[
                          InkWell(
                            onTap: () => widget.onRunInEditor?.call(widget.sql!),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: accent.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.play_arrow_rounded, size: 12, color: accent),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Run in Editor',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accent),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],

                        // Expand / Collapse Matrix Height
                        if (displayedRows.length > 10) ...[
                          IconButton(
                            icon: Icon(
                              _lunarIsExpanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
                              size: 14,
                              color: _lunarIsExpanded ? accent : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            tooltip: _lunarIsExpanded ? 'Collapse matrix height' : 'Expand matrix height',
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            onPressed: () => setState(() => _lunarIsExpanded = !_lunarIsExpanded),
                          ),
                          const SizedBox(width: 2),
                        ],

                        // Copy TSV
                        IconButton(
                          icon: const Icon(Icons.file_copy_outlined, size: 14),
                          tooltip: 'Copy as TSV (Spreadsheets)',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          onPressed: () => _copyTsv(filteredRows),
                        ),

                        // Copy Markdown
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 14),
                          tooltip: 'Copy as Markdown',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          onPressed: () => _copyMarkdown(filteredRows),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // High-Performance Virtualized Data Grid (Zero-Intrinsic Table Measurement)
              LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
                  final totalColsWidth = colWidths.values.fold(0.0, (sum, w) => sum + w);
                  final bool canStretch = totalColsWidth < availableWidth && widget.queryResult.columns.isNotEmpty;
                  final extraPerCol = canStretch ? (availableWidth - totalColsWidth) / widget.queryResult.columns.length : 0.0;
                  final effectiveTotalWidth = canStretch ? availableWidth : totalColsWidth;

                  return SingleChildScrollView(
                    controller: _lunarHorizontalScrollCtrl,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: effectiveTotalWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Sticky Header Row
                          Container(
                            height: _lunarHeaderHeight,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.25 : 0.4),
                              border: Border(
                                bottom: BorderSide(
                                  color: theme.dividerColor.withValues(alpha: 0.15),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              children: List.generate(widget.queryResult.columns.length, (cIdx) {
                                final col = widget.queryResult.columns[cIdx];
                                final width = (colWidths[cIdx] ?? 120.0) + extraPerCol;
                                return Container(
                                  width: width,
                                  height: _lunarHeaderHeight,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    col,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.4,
                                      color: accent,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                );
                              }),
                            ),
                          ),

                          // Viewport-Recycled Rows Container
                          SizedBox(
                            height: bodyHeight,
                            child: displayedRows.isEmpty
                                ? Center(
                                    child: Text(
                                      _searchFilter.isEmpty ? 'No data' : 'No rows matching filter',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                    ),
                                  )
                                : Scrollbar(
                                    controller: _lunarVerticalScrollCtrl,
                                    thumbVisibility: displayedRows.length * _lunarRowHeight > bodyHeight,
                                    child: ListView.builder(
                                      controller: _lunarVerticalScrollCtrl,
                                      itemCount: displayedRows.length,
                                      itemExtent: _lunarRowHeight,
                                      physics: const ClampingScrollPhysics(),
                                      itemBuilder: (context, rIdx) {
                                        final row = displayedRows[rIdx];
                                        final isEven = rIdx % 2 == 0;
                                        final isHovered = _lunarHoveredRowIndex == rIdx;
                                        final rowBg = isHovered
                                            ? accent.withValues(alpha: isDark ? 0.08 : 0.06)
                                            : (isEven
                                                ? Colors.transparent
                                                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.12 : 0.2));

                                        return MouseRegion(
                                          onEnter: (_) => setState(() => _lunarHoveredRowIndex = rIdx),
                                          onExit: (_) {
                                            if (_lunarHoveredRowIndex == rIdx) {
                                              setState(() => _lunarHoveredRowIndex = null);
                                            }
                                          },
                                          child: Container(
                                            height: _lunarRowHeight,
                                            decoration: BoxDecoration(
                                              color: rowBg,
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: theme.dividerColor.withValues(alpha: 0.1),
                                                  width: 0.5,
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              children: List.generate(widget.queryResult.columns.length, (cIdx) {
                                                final width = (colWidths[cIdx] ?? 120.0) + extraPerCol;
                                                final cellVal = cIdx < row.length ? row[cIdx] : null;
                                                final cellText = cellVal != null ? cellVal.toString() : 'null';
                                                final isNull = cellVal == null;
                                                final isCode = _isCodeLike(cellText);

                                                return Container(
                                                  width: width,
                                                  height: _lunarRowHeight,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                                  alignment: Alignment.centerLeft,
                                                  child: Tooltip(
                                                    message: isNull ? 'NULL' : cellText,
                                                    waitDuration: const Duration(milliseconds: 600),
                                                    child: InkWell(
                                                      onTap: () => _lunarCopyCell(cellText, isNull),
                                                      borderRadius: BorderRadius.circular(3),
                                                      child: Text(
                                                        cellText,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontStyle: isNull ? FontStyle.italic : null,
                                                          fontFamily: isCode ? 'monospace' : null,
                                                          color: isNull
                                                              ? Colors.grey.shade500
                                                              : (isCode && isDark ? const Color(0xFF38BDF8) : theme.colorScheme.onSurface),
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // Pagination Footer Bar
              if (_pageSize > 0 && totalRows > _pageSize)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: headerBg,
                    border: Border(
                      top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Showing ${startIndex + 1}–$endIndex of $totalRows rows',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.first_page, size: 14),
                        tooltip: 'First Page',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onPressed: safePage > 0 ? () => setState(() => _currentPage = 0) : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_left, size: 14),
                        tooltip: 'Previous Page',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onPressed: safePage > 0 ? () => setState(() => _currentPage = safePage - 1) : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          'Page ${safePage + 1} of $maxPages',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, size: 14),
                        tooltip: 'Next Page',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onPressed: safePage < maxPages - 1 ? () => setState(() => _currentPage = safePage + 1) : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.last_page, size: 14),
                        tooltip: 'Last Page',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onPressed: safePage < maxPages - 1 ? () => setState(() => _currentPage = maxPages - 1) : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}



