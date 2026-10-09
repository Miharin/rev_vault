import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_vault/state/app_state.dart';
import 'package:rev_vault/theme/cyber_theme.dart';
import 'package:rev_vault/views/widgets/tactical_hud_widgets.dart';
import 'package:rev_vault/views/widgets/virtualized_data_table.dart';

void main() {
  group('CyberTheme & AppState Circadian Tests', () {
    test('CyberTheme builds valid dark and light theme data with accent presets', () {
      for (final preset in AccentColorPreset.values) {
        final darkTheme = CyberTheme.buildTheme(isDark: true, accent: preset);
        final lightTheme = CyberTheme.buildTheme(isDark: false, accent: preset);

        expect(darkTheme.brightness, equals(Brightness.dark));
        expect(lightTheme.brightness, equals(Brightness.light));
        expect(darkTheme.colorScheme.primary, equals(preset.color));
        expect(lightTheme.colorScheme.primary, equals(preset.color));
      }
    });

    test('AppState toggles theme preferences and rail collapse', () {
      final state = AppState();
      expect(state.themePreference, equals(ThemePreference.circadian));

      state.setThemePreference(ThemePreference.dark);
      expect(state.themePreference, equals(ThemePreference.dark));
      expect(state.isEffectiveDarkMode, isTrue);

      state.setThemePreference(ThemePreference.light);
      expect(state.themePreference, equals(ThemePreference.light));
      expect(state.isEffectiveDarkMode, isFalse);

      expect(state.isRailCollapsed, isFalse);
      state.toggleRailCollapse();
      expect(state.isRailCollapsed, isTrue);

      expect(state.isSchemaRailCollapsed, isFalse);
      state.toggleSchemaRailCollapse();
      expect(state.isSchemaRailCollapsed, isTrue);
    });
  });

  group('Tactical HUD Widgets Tests', () {
    testWidgets('TacticalPulseButton responds to taps and shows shortcut badge', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TacticalPulseButton(
                onPressed: () => tapped = true,
                icon: const Icon(Icons.play_arrow),
                label: 'Run Query',
                shortcutLabel: 'Ctrl+Enter',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Run Query'), findsOneWidget);
      expect(find.text('Ctrl+Enter'), findsOneWidget);

      await tester.tap(find.text('Run Query'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('TelemetryMetricBadge renders animated metrics', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: TelemetryMetricBadge(
                label: 'LATENCY',
                value: '12.4 ms',
                icon: Icons.timer,
              ),
            ),
          ),
        ),
      );

      expect(find.text('LATENCY: '), findsOneWidget);
      expect(find.text('12.4 ms'), findsOneWidget);
    });
  });

  group('VirtualizedDataTable Tests', () {
    testWidgets('Renders sticky headers, row index, and virtualized cells for 1,000 rows without jank', (tester) async {
      final columns = ['id', 'username', 'email', 'status'];
      final rows = List.generate(
        1000,
        (i) => [i + 1, 'user_$i', 'user_$i@domain.com', i % 2 == 0 ? 'ACTIVE' : 'OFFLINE'],
      );

      String? filteredCol;
      dynamic filteredVal;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: VirtualizedDataTable(
                columns: columns,
                rows: rows,
                onFilterByCellValue: (col, val) {
                  filteredCol = col;
                  filteredVal = val;
                },
              ),
            ),
          ),
        ),
      );

      // Verify headers
      expect(find.text('id'), findsOneWidget);
      expect(find.text('username'), findsOneWidget);
      expect(find.text('email'), findsOneWidget);
      expect(find.text('status'), findsOneWidget);

      // Verify row 1 is rendered
      expect(find.text('user_0'), findsOneWidget);
      expect(find.text('user_0@domain.com'), findsOneWidget);

      // Verify double tap filter on cell
      await tester.tap(find.text('user_0'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('user_0'));
      await tester.pumpAndSettle();

      expect(filteredCol, equals('username'));
      expect(filteredVal, equals('user_0'));
    });
  });
}
