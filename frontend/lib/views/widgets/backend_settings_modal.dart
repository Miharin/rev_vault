import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/backend_config_service.dart';
import '../../state/app_state.dart';

/// Modal dialog for inspecting, testing, and updating the RevVault backend endpoint,
/// allowing Android devices and remote clients to connect over Wi-Fi.
Future<void> showBackendSettingsModal(BuildContext context) {
  return showDialog(
    context: context,
    builder: (ctx) => const BackendSettingsModal(),
  );
}

class BackendSettingsModal extends StatefulWidget {
  const BackendSettingsModal({super.key});

  @override
  State<BackendSettingsModal> createState() => _BackendSettingsModalState();
}

class _BackendSettingsModalState extends State<BackendSettingsModal> {
  late TextEditingController _urlController;
  bool _isTesting = false;
  bool _isSaving = false;
  String? _testResult;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _urlController = TextEditingController(text: state.backendBaseUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _runConnectionTest() async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
    });

    final res = await BackendConfigService.testEndpoint(rawUrl);

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testSuccess = res.success;
        _testResult = res.message;
      });
    }
  }

  Future<void> _saveAndConnect() async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) return;

    setState(() {
      _isSaving = true;
    });

    final state = context.read<AppState>();
    final ok = await state.updateBackendUrl(rawUrl, persist: true);

    if (mounted) {
      setState(() {
        _isSaving = false;
      });

      if (ok) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to backend at ${state.backendBaseUrl}'),
            backgroundColor: Colors.teal.shade800,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _testSuccess = false;
          _testResult = 'Connection failed: Backend is not reachable at $rawUrl';
        });
      }
    }
  }

  void _applyPreset(String presetUrl) {
    _urlController.text = presetUrl;
    setState(() {
      _testResult = null;
      _testSuccess = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final state = context.watch<AppState>();

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accent.withValues(alpha: 0.3), width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withValues(alpha: 0.35)),
                    ),
                    child: Icon(Icons.router, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Backend Network Configuration',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Connect Android companion or remote client to PC',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: state.isBackendOnline
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: state.isBackendOnline
                        ? Colors.green.withValues(alpha: 0.4)
                        : Colors.red.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      state.isBackendOnline ? Icons.check_circle : Icons.error_outline,
                      size: 16,
                      color: state.isBackendOnline ? Colors.greenAccent : Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.isBackendOnline
                            ? 'Online: ${state.backendBaseUrl}'
                            : 'Offline / Disconnected',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: state.isBackendOnline ? Colors.greenAccent : Colors.redAccent,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Input Label
              Text(
                'HOST & PORT (HTTP / WS ENDPOINT)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 6),

              // URL Text Field
              TextField(
                controller: _urlController,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'http://192.168.1.50:8000',
                  prefixIcon: const Icon(Icons.link, size: 18),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: theme.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Presets
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.computer, size: 14),
                    label: const Text('Localhost (127.0.0.1:8000)', style: TextStyle(fontSize: 11)),
                    onPressed: () => _applyPreset('http://127.0.0.1:8000'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.phone_android, size: 14),
                    label: const Text('AVD Emulator (10.0.2.2:8000)', style: TextStyle(fontSize: 11)),
                    onPressed: () => _applyPreset('http://10.0.2.2:8000'),
                  ),
                  if (state.customBackendUrl != null)
                    ActionChip(
                      avatar: const Icon(Icons.restore, size: 14),
                      label: const Text('Reset Default', style: TextStyle(fontSize: 11)),
                      onPressed: () async {
                        await state.resetBackendUrl();
                        if (context.mounted) {
                          _urlController.text = state.backendBaseUrl;
                          setState(() {
                            _testResult = null;
                            _testSuccess = null;
                          });
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Test Result Feedback Banner
              if (_testResult != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (_testSuccess == true)
                        ? Colors.green.withValues(alpha: 0.12)
                        : Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (_testSuccess == true)
                          ? Colors.green.withValues(alpha: 0.35)
                          : Colors.red.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        (_testSuccess == true) ? Icons.check_circle : Icons.warning,
                        size: 16,
                        color: (_testSuccess == true) ? Colors.greenAccent : Colors.redAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            fontSize: 12,
                            color: (_testSuccess == true) ? Colors.greenAccent : Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Wi-Fi Quick Guide Tip
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tip: Connect your phone to the same Wi-Fi as your PC, then enter your PC LAN IP (e.g. 192.168.x.x:8000).',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.8)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Actions
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isTesting ? null : _runConnectionTest,
                      icon: _isTesting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check, size: 16),
                      label: const Text('Test Ping'),
                    ),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveAndConnect,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.sync, size: 16),
                      label: const Text('Save & Connect'),
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
