import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../state/app_state.dart';

/// Modal dialog displaying local Wi-Fi pairing information and QR code
/// for instant Android phone & tablet connection.
Future<void> showMobileConnectModal(BuildContext context) {
  return showDialog(
    context: context,
    builder: (ctx) => const MobileConnectModal(),
  );
}

class MobileConnectModal extends StatefulWidget {
  const MobileConnectModal({super.key});

  @override
  State<MobileConnectModal> createState() => _MobileConnectModalState();
}

class _MobileConnectModalState extends State<MobileConnectModal> {
  String? _lanUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _resolveLanAddress();
  }

  Future<void> _resolveLanAddress() async {
    final state = context.read<AppState>();
    final uri = Uri.tryParse(state.backendBaseUrl);
    final port = uri?.port ?? 8000;

    String host = '127.0.0.1';

    if (kIsWeb) {
      host = Uri.base.host.isNotEmpty ? Uri.base.host : '127.0.0.1';
    } else {
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && !addr.address.startsWith('127.')) {
              host = addr.address;
              break;
            }
          }
          if (host != '127.0.0.1') break;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _lanUrl = 'http://$host:$port';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accent.withValues(alpha: 0.3), width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
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
                    child: Icon(Icons.qr_code_scanner, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connect Android Device',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Zero-install mobile web PWA & remote companion',
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
              const SizedBox(height: 20),

              // QR Code Card
              if (_isLoading)
                const SizedBox(
                  height: 190,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                )
              else if (_lanUrl != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.2),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: _lanUrl!,
                    version: QrVersions.auto,
                    size: 180.0,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // LAN URL Badge & Copy
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi, size: 14, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lanUrl!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 14),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Copy URL',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _lanUrl!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('LAN URL copied to clipboard'),
                              duration: Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                              width: 250,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Instructions
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.touch_app, size: 13, color: accent),
                          const SizedBox(width: 6),
                          Text(
                            'Step 1: Connect phone to same Wi-Fi network.',
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.85)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.camera_alt, size: 13, color: accent),
                          const SizedBox(width: 6),
                          Text(
                            'Step 2: Scan QR code with phone camera.',
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.85)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.add_to_home_screen, size: 13, color: accent),
                          const SizedBox(width: 6),
                          Text(
                            'Step 3: Tap "Add to Home Screen" to install PWA.',
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.85)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
