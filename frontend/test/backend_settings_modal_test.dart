import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rev_vault/services/backend_config_service.dart';
import 'package:rev_vault/state/app_state.dart';
import 'package:rev_vault/views/widgets/backend_settings_modal.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BackendConfigService URL normalization & WebSocket conversion', () {
    test('normalizes raw host and port', () {
      expect(BackendConfigService.normalizeUrl('192.168.1.45:8000'), 'http://192.168.1.45:8000');
      expect(BackendConfigService.normalizeUrl('http://192.168.1.45:8000/'), 'http://192.168.1.45:8000');
      expect(BackendConfigService.normalizeUrl('https://remote.example.com'), 'https://remote.example.com:8000');
    });

    test('converts http and https to ws and wss correctly', () {
      expect(
        BackendConfigService.toWebSocketUrl('http://192.168.1.45:8000'),
        'ws://192.168.1.45:8000/api/audit/ws',
      );
      expect(
        BackendConfigService.toWebSocketUrl('https://api.domain.com:8443'),
        'wss://api.domain.com:8443/api/audit/ws',
      );
    });

    test('persists and clears url in SharedPreferences', () async {
      await BackendConfigService.saveUrl('http://192.168.1.99:8000');
      final loaded = await BackendConfigService.loadSavedUrl();
      expect(loaded, 'http://192.168.1.99:8000');

      await BackendConfigService.resetToDefault();
      final reset = await BackendConfigService.loadSavedUrl();
      expect(reset, isNull);
    });
  });

  group('BackendSettingsModal Widget Tests', () {
    testWidgets('renders BackendSettingsModal and applies preset chips', (WidgetTester tester) async {
      final appState = AppState();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: Scaffold(
              body: BackendSettingsModal(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Backend Network Configuration'), findsOneWidget);
      expect(find.text('HOST & PORT (HTTP / WS ENDPOINT)'), findsOneWidget);
      expect(find.text('Localhost (127.0.0.1:8000)'), findsOneWidget);
      expect(find.text('AVD Emulator (10.0.2.2:8000)'), findsOneWidget);
      expect(find.text('Test Ping'), findsOneWidget);
      expect(find.text('Save & Connect'), findsOneWidget);

      // Tap AVD Emulator chip
      await tester.tap(find.text('AVD Emulator (10.0.2.2:8000)'));
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'http://10.0.2.2:8000');
    });
  });
}
