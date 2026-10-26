import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

class AiAssistantMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final List<Map<String, dynamic>> toolExecutions;
  final DateTime timestamp;

  AiAssistantMessage({
    required this.role,
    required this.content,
    this.toolExecutions = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AiAssistantView extends StatefulWidget {
  final VoidCallback? onNavigateToEditor;

  const AiAssistantView({
    super.key,
    this.onNavigateToEditor,
  });

  @override
  State<AiAssistantView> createState() => _AiAssistantViewState();
}

class _AiAssistantViewState extends State<AiAssistantView> {
  final List<AiAssistantMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  bool _ollamaOnline = false;
  String _ollamaUrl = 'http://localhost:11434';
  String _selectedModel = 'gemma4:e4b';
  List<String> _availableModels = ['gemma4:e4b'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOllamaStatus();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkOllamaStatus() async {
    final state = context.read<AppState>();
    final res = await state.api.getAgentStatus(ollamaUrl: _ollamaUrl);
    if (!mounted) return;

    setState(() {
      _ollamaOnline = res['online'] == true;
      final modelsList = (res['models'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      if (modelsList.isNotEmpty) {
        _availableModels = modelsList;
        if (!_availableModels.contains(_selectedModel)) {
          _selectedModel = _availableModels.firstWhere(
            (m) => m.contains('gemma') || m.contains('qwen'),
            orElse: () => _availableModels.first,
          );
        }
      }
    });
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
    if (trimmed.isEmpty || _isLoading) return;

    final state = context.read<AppState>();
    _inputController.clear();

    setState(() {
      _messages.add(AiAssistantMessage(role: 'user', content: trimmed));
      _isLoading = true;
    });
    _scrollToBottom();

    // Prepare history payload (excluding system messages)
    final historyPayload = _messages
        .take(_messages.length - 1)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    final response = await state.api.sendAgentMessage(
      message: trimmed,
      model: _selectedModel,
      history: historyPayload,
      ollamaUrl: _ollamaUrl,
    );

    if (!mounted) return;

    final reply = response['reply']?.toString() ?? 'No response received.';
    final tools = (response['tool_executions'] as List<dynamic>?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
        [];

    setState(() {
      _isLoading = false;
      _messages.add(AiAssistantMessage(
        role: 'assistant',
        content: reply,
        toolExecutions: tools,
      ));
    });
    _scrollToBottom();
  }

  void _showOllamaSettingsDialog() {
    final controller = TextEditingController(text: _ollamaUrl);
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
                setState(() => _ollamaUrl = newUrl);
                _checkOllamaStatus();
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
            child: _messages.isEmpty
                ? _buildEmptyState(theme, accent)
                : _buildMessageList(theme, accent),
          ),

          // Bottom Input Bar
          const Divider(height: 1),
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
          Icon(Icons.smart_toy, size: 20, color: accent),
          const SizedBox(width: 8),
          const Text(
            'RevVault AI Assistant',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: const Text(
              'Public Agent',
              style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
          const Spacer(),

          // Ollama Status Pill
          InkWell(
            onTap: _checkOllamaStatus,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _ollamaOnline
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _ollamaOnline
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
                      color: _ollamaOnline ? Colors.green : Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _ollamaOnline ? 'Ollama Active' : 'Ollama Offline',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _ollamaOnline ? Colors.green : Colors.amber,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Model Selector Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _availableModels.contains(_selectedModel) ? _selectedModel : null,
                hint: Text(_selectedModel, style: const TextStyle(fontSize: 12)),
                isDense: true,
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
                items: _availableModels.map((m) {
                  return DropdownMenuItem<String>(
                    value: m,
                    child: Text(m, style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
                onChanged: (newModel) {
                  if (newModel != null) {
                    setState(() => _selectedModel = newModel);
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
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              tooltip: 'Clear Conversation',
              onPressed: () {
                setState(() => _messages.clear());
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, Color accent) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.3)),
                ),
                child: Icon(Icons.psychology, size: 36, color: accent),
              ),
              const SizedBox(height: 16),
              const Text(
                'RevVault AI Database Assistant',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Execute safe schema inspection, analytical SQL synthesis, and performance audits with local open models.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400, height: 1.4),
              ),
              const SizedBox(height: 24),

              // Suggestion Prompt Cards
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Suggested Inquiries:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 10),
              _buildSuggestionCard(
                theme,
                accent,
                icon: Icons.table_chart_outlined,
                title: 'List All Tables & Views',
                description: 'Introspect active database and list registered schemas and views.',
                prompt: 'List all tables and views available in the active database.',
              ),
              const SizedBox(height: 8),
              _buildSuggestionCard(
                theme,
                accent,
                icon: Icons.account_tree_outlined,
                title: 'Inspect Foreign Key Relationships',
                description: 'Map entity relationships and join conditions across tables.',
                prompt: 'Get all Foreign Key relationships across tables in the active database.',
              ),
              const SizedBox(height: 8),
              _buildSuggestionCard(
                theme,
                accent,
                icon: Icons.code,
                title: 'Generate Safe Read-Only Query',
                description: 'Generate a paginated SELECT statement to examine sample records.',
                prompt: 'Generate and execute a safe query to inspect recent records from the primary table.',
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
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
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

  Widget _buildMessageList(ThemeData theme, Color accent) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isLoading) {
          return _buildLoadingBubble(theme, accent);
        }
        final msg = _messages[index];
        return _buildMessageCard(theme, accent, msg);
      },
    );
  }

  Widget _buildLoadingBubble(ThemeData theme, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: accent.withValues(alpha: 0.2),
            child: Icon(Icons.smart_toy, size: 16, color: accent),
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

  Widget _buildMessageCard(ThemeData theme, Color accent, AiAssistantMessage msg) {
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
              child: Icon(Icons.smart_toy, size: 16, color: accent),
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
        // Prose text
        if (part.trim().isNotEmpty) {
          widgets.add(
            SelectableText(
              part.trim(),
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          );
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
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
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
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              onPressed: _isLoading ? null : () => _sendMessage(_inputController.text),
            ),
          ],
        ),
      ),
    );
  }
}
