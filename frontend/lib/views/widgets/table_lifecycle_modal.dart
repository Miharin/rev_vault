import 'package:flutter/material.dart';
import 'cyber_text_field.dart';

enum TableLifecycleAction {
  drop,
  truncate,
}

/// Cyber-styled confirmation modal for Drop Table and Truncate Table operations.
/// Enforces dual-gate verification in Safe Mode (requires typing the table name).
Future<bool?> showTableLifecycleModal({
  required BuildContext context,
  required String tableName,
  String? schemaName,
  required TableLifecycleAction action,
  required bool isSafeMode,
  required Future<bool> Function({required bool cascade}) onConfirm,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _TableLifecycleModalDialog(
      tableName: tableName,
      schemaName: schemaName,
      action: action,
      isSafeMode: isSafeMode,
      onConfirm: onConfirm,
    ),
  );
}

class _TableLifecycleModalDialog extends StatefulWidget {
  final String tableName;
  final String? schemaName;
  final TableLifecycleAction action;
  final bool isSafeMode;
  final Future<bool> Function({required bool cascade}) onConfirm;

  const _TableLifecycleModalDialog({
    required this.tableName,
    required this.schemaName,
    required this.action,
    required this.isSafeMode,
    required this.onConfirm,
  });

  @override
  State<_TableLifecycleModalDialog> createState() => _TableLifecycleModalDialogState();
}

class _TableLifecycleModalDialogState extends State<_TableLifecycleModalDialog> {
  final TextEditingController _verifyCtrl = TextEditingController();
  bool _cascade = false;
  bool _isExecuting = false;
  String? _errorMessage;

  bool get _isDrop => widget.action == TableLifecycleAction.drop;

  String get _targetRawName {
    final raw = widget.tableName.contains('.') ? widget.tableName.split('.').last : widget.tableName;
    return raw.replaceAll('"', '').replaceAll('`', '');
  }

  bool get _canSubmit {
    if (_isExecuting) return false;
    if (!widget.isSafeMode) return true;
    return _verifyCtrl.text.trim() == _targetRawName;
  }

  @override
  void dispose() {
    _verifyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _isExecuting = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.onConfirm(cascade: _cascade);
      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isExecuting = false;
          _errorMessage = 'Operation failed. Check server response or dependent constraints.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExecuting = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = _isDrop ? Colors.redAccent : Colors.amberAccent;
    final actionLabel = _isDrop ? 'DROP TABLE' : 'TRUNCATE TABLE';

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accentColor.withValues(alpha: 0.35)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Danger Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: accentColor.withValues(alpha: 0.2)),
                ),
                color: accentColor.withValues(alpha: 0.08),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _isDrop ? Icons.delete_forever : Icons.cleaning_services,
                      color: accentColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          actionLabel,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: accentColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          widget.tableName,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(false),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              ),

            // Notice & Typed Verification
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isDrop
                        ? 'This operation will permanently delete the entire table "${widget.tableName}" and all associated data, indexes, and triggers from the database.'
                        : 'This operation will completely wipe all rows from "${widget.tableName}". The table schema structure will be preserved.',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),

                  // Cascade Toggle
                  InkWell(
                    onTap: () => setState(() => _cascade = !_cascade),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _cascade,
                            onChanged: (v) => setState(() => _cascade = v ?? false),
                            activeColor: accentColor,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Cascade (automatically drop/clear dependent foreign key constraints)',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Safe Mode Verification Field
                  if (widget.isSafeMode) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.lock, size: 12, color: Colors.amberAccent),
                              const SizedBox(width: 6),
                              Text(
                                'SAFE MODE DUAL-GATE VERIFICATION',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade300,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          RichText(
                            text: TextSpan(
                              style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurface),
                              children: [
                                const TextSpan(text: 'Please type '),
                                TextSpan(
                                  text: _targetRawName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    color: Colors.redAccent,
                                  ),
                                ),
                                const TextSpan(text: ' to confirm:'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          CyberTextField(
                            controller: _verifyCtrl,
                            hintText: _targetRawName,
                            isMonospace: true,
                            fillColor: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(6),
                            showClearButton: true,
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Modal Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                ),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isExecuting ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _canSubmit ? _submit : null,
                    icon: _isExecuting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(_isDrop ? Icons.delete_forever : Icons.cleaning_services, size: 16),
                    label: Text(
                      _isExecuting
                          ? 'Executing...'
                          : (_isDrop ? 'Drop Table' : 'Truncate Table'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _isDrop ? Colors.red.shade700 : Colors.amber.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
