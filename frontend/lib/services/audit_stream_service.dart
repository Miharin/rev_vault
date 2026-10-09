import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/audit_event.dart';

String getDefaultWsUrl() {
  if (kIsWeb) {
    final host = Uri.base.host.isNotEmpty ? Uri.base.host : '127.0.0.1';
    final scheme = Uri.base.scheme.startsWith('https') ? 'wss' : 'ws';
    return '$scheme://$host:8000/api/audit/ws';
  }
  return 'ws://127.0.0.1:8000/api/audit/ws';
}

class AuditStreamService {
  String _wsUrl;
  String get wsUrl => _wsUrl;
  WebSocketChannel? _channel;
  final StreamController<AuditEvent> _controller = StreamController<AuditEvent>.broadcast();
  bool _isConnected = false;
  Timer? _reconnectTimer;

  AuditStreamService({String? wsUrl}) : _wsUrl = wsUrl ?? getDefaultWsUrl();

  void setWsUrl(String url) {
    _wsUrl = url;
  }

  int _reconnectAttempts = 0;

  Stream<AuditEvent> get stream => _controller.stream;
  bool get isConnected => _isConnected;

  void connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;

      _channel!.stream.listen(
        (message) {
          _reconnectAttempts = 0;
          try {
            final data = jsonDecode(message.toString()) as Map<String, dynamic>;
            final event = AuditEvent.fromJson(data);
            _controller.add(event);
          } catch (_) {}
        },
        onError: (err) {
          _isConnected = false;
          _scheduleReconnect();
        },
        onDone: () {
          _isConnected = false;
          _scheduleReconnect();
        },
      );
    } catch (_) {
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    // Exponential backoff: 2s, 4s, 8s, 16s, capped at 30s
    final delaySeconds = (_reconnectAttempts < 5)
        ? (2 << _reconnectAttempts)
        : 30;
    _reconnectAttempts++;

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      connect();
    });
  }

  /// Disconnects current channel and stops reconnect attempts.
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;
    _reconnectAttempts = 0;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
