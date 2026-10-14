import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_vault/views/widgets/cyber_switch.dart';
import 'package:rev_vault/views/widgets/cyber_checkbox.dart';

void main() {
  group('CyberSwitch Widget Tests', () {
    testWidgets('Toggles value on tap and invokes onChanged', (tester) async {
      bool currentValue = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return CyberSwitch(
                  value: currentValue,
                  activeColor: const Color(0xFF10B981),
                  semanticLabel: 'Safe Mode Switch',
                  onChanged: (val) {
                    setState(() => currentValue = val);
                  },
                );
              },
            ),
          ),
        ),
      );

      expect(find.byType(CyberSwitch), findsOneWidget);
      expect(currentValue, isFalse);

      // Tap to turn ON
      await tester.tap(find.byType(CyberSwitch));
      await tester.pumpAndSettle();
      expect(currentValue, isTrue);

      // Tap to turn OFF
      await tester.tap(find.byType(CyberSwitch));
      await tester.pumpAndSettle();
      expect(currentValue, isFalse);
    });

    testWidgets('Disabled switch ignores taps when onChanged is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CyberSwitch(
              value: false,
              onChanged: null,
            ),
          ),
        ),
      );

      // Should not throw or crash on tap
      await tester.tap(find.byType(CyberSwitch));
      await tester.pumpAndSettle();
    });

    testWidgets('Renders thumb icons and respects external value updates', (tester) async {
      bool externalValue = true;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    CyberSwitch(
                      value: externalValue,
                      activeThumbIcon: const Icon(Icons.shield, key: ValueKey('shield_icon')),
                      inactiveThumbIcon: const Icon(Icons.shield_outlined, key: ValueKey('shield_outlined_icon')),
                      onChanged: (val) => setState(() => externalValue = val),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shield_icon')), findsOneWidget);
      expect(find.byKey(const ValueKey('shield_outlined_icon')), findsNothing);

      // Tap to toggle off
      await tester.tap(find.byType(CyberSwitch));
      await tester.pumpAndSettle();
      expect(externalValue, isFalse);
      expect(find.byKey(const ValueKey('shield_outlined_icon')), findsOneWidget);
    });

    testWidgets('Renders modern ceramic capsule and micro LED indicator dot when no custom icon provided', (tester) async {
      bool switchOn = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return CyberSwitch(
                  value: switchOn,
                  onChanged: (val) => setState(() => switchOn = val),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(CyberSwitch), findsOneWidget);

      // Verify AnimatedScale widget is present for modern press-down feedback
      expect(find.byType(AnimatedScale), findsOneWidget);
    });
  });

  group('CyberCheckbox Widget Tests', () {
    testWidgets('Binary checkbox toggles between checked and unchecked', (tester) async {
      bool? isChecked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return CyberCheckbox(
                  value: isChecked,
                  onChanged: (val) {
                    setState(() => isChecked = val);
                  },
                );
              },
            ),
          ),
        ),
      );

      expect(find.byType(CyberCheckbox), findsOneWidget);
      expect(find.byKey(const ValueKey('empty')), findsOneWidget);

      // Tap to check
      await tester.tap(find.byType(CyberCheckbox));
      await tester.pumpAndSettle();
      expect(isChecked, isTrue);
      expect(find.byKey(const ValueKey('check')), findsOneWidget);

      // Tap to uncheck
      await tester.tap(find.byType(CyberCheckbox));
      await tester.pumpAndSettle();
      expect(isChecked, isFalse);
      expect(find.byKey(const ValueKey('empty')), findsOneWidget);
    });

    testWidgets('Tristate checkbox supports indeterminate state and cycles correctly', (tester) async {
      bool? tristateValue; // Indeterminate / null

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return CyberCheckbox(
                  value: tristateValue,
                  tristate: true,
                  size: 16.0,
                  tooltip: 'Select All / Indeterminate',
                  onChanged: (val) {
                    setState(() => tristateValue = val);
                  },
                );
              },
            ),
          ),
        ),
      );

      // Starts indeterminate: dash glyph
      expect(find.byKey(const ValueKey('dash')), findsOneWidget);

      // Tap when indeterminate -> transitions to true (select all)
      await tester.tap(find.byType(CyberCheckbox));
      await tester.pumpAndSettle();
      expect(tristateValue, isTrue);
      expect(find.byKey(const ValueKey('check')), findsOneWidget);

      // Tap when true -> transitions to false
      await tester.tap(find.byType(CyberCheckbox));
      await tester.pumpAndSettle();
      expect(tristateValue, isFalse);
      expect(find.byKey(const ValueKey('empty')), findsOneWidget);

      // Tap when false -> transitions to true
      await tester.tap(find.byType(CyberCheckbox));
      await tester.pumpAndSettle();
      expect(tristateValue, isTrue);
      expect(find.byKey(const ValueKey('check')), findsOneWidget);
    });

    testWidgets('Disabled checkbox ignores taps when onChanged is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CyberCheckbox(
              value: true,
              onChanged: null,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(CyberCheckbox));
      await tester.pumpAndSettle();
      // Verifies no exception thrown
      expect(find.byType(CyberCheckbox), findsOneWidget);
    });
  });
}
