import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Service for persisting and managing the RevVault backend endpoint address,
/// enabling Wi-Fi / LAN connection across mobile devices (Android) and remote clients.
class BackendConfigService {
  static const String _keyBackendUrl = 'revvault_backend_url';

  /// Normalizes user-entered address into a valid `http(s)://host:port` string.
  static String normalizeUrl(String input) {
    var raw = input.trim();
    if (raw.isEmpty) {
      return defaultUrl;
    }
    // Remove trailing slashes
    while (raw.endsWith('/')) {
      raw = raw.substring(0, raw.length - 1);
    }
    // Prepend http:// scheme if absent
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      raw = 'http://$raw';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) {
      return defaultUrl;
    }
    final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'http';
    final host = uri.host;
    final port = uri.hasPort ? uri.port : 8000;
    return '$scheme://$host:$port';
  }

  /// Converts an HTTP base URL to its corresponding WebSocket endpoint.
  static String toWebSocketUrl(String httpBaseUrl) {
    final normalized = normalizeUrl(httpBaseUrl);
    final uri = Uri.parse(normalized);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '$wsScheme://${uri.host}$port/api/audit/ws';
  }

  /// Default endpoint based on runtime environment.
  static String get defaultUrl {
    if (kIsWeb) {
      final host = Uri.base.host.isNotEmpty ? Uri.base.host : '127.0.0.1';
      final scheme = Uri.base.scheme.startsWith('https') ? 'https' : 'http';
      final port = Uri.base.hasPort && Uri.base.port != 80 && Uri.base.port != 443 ? Uri.base.port : 8000;
      return '$scheme://$host:$port';
    }
    return 'http://127.0.0.1:8000';
  }

  /// Fetches saved custom URL from persistent preferences, if any.
  static Future<String?> loadSavedUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString(_keyBackendUrl);
      if (val != null && val.trim().isNotEmpty) {
        return normalizeUrl(val);
      }
    } catch (e) {
      debugPrint('[BackendConfig] Error loading saved backend URL: $e');
    }
    return null;
  }

  /// Persists a custom backend URL to preferences.
  static Future<void> saveUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyBackendUrl, normalizeUrl(url));
    } catch (e) {
      debugPrint('[BackendConfig] Error saving backend URL: $e');
    }
  }

  /// Clears custom URL, reverting to default sidecar/localhost.
  static Future<void> resetToDefault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyBackendUrl);
    } catch (e) {
      debugPrint('[BackendConfig] Error resetting backend URL: $e');
    }
  }

  /// Quickly tests connectivity to a specific backend address without mutating state.
  static Future<({bool success, int statusCode, String message, double latencyMs})> testEndpoint(
    String url, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final target = normalizeUrl(url);
    final sw = Stopwatch()..start();
    try {
      final response = await http
          .get(Uri.parse('$target/health'))
          .timeout(timeout);
      sw.stop();
      if (response.statusCode == 200) {
        return (
          success: true,
          statusCode: 200,
          message: 'Connected successfully (${sw.elapsedMilliseconds} ms)',
          latencyMs: sw.elapsedMilliseconds.toDouble(),
        );
      } else {
        return (
          success: false,
          statusCode: response.statusCode,
          message: 'Server responded with status ${response.statusCode}',
          latencyMs: sw.elapsedMilliseconds.toDouble(),
        );
      }
    } catch (e) {
      sw.stop();
      return (
        success: false,
        statusCode: 0,
        message: 'Unable to reach $target: $e',
        latencyMs: sw.elapsedMilliseconds.toDouble(),
      );
    }
  }
}
