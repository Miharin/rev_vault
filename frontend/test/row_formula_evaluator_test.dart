import 'package:flutter_test/flutter_test.dart';
import 'package:rev_vault/views/widgets/row_duplicate_modal.dart';

void main() {
  group('RowFormulaEvaluator', () {
    test('evaluates arithmetic with i variable', () {
      // i is 0-indexed copy: 0, 1, 2, ...
      expect(RowFormulaEvaluator.evaluate(formula: 'i + 1', baseVal: 0, copyIndex: 0), 1);
      expect(RowFormulaEvaluator.evaluate(formula: 'i + 1', baseVal: 0, copyIndex: 1), 2);
      expect(RowFormulaEvaluator.evaluate(formula: 'i + 1', baseVal: 0, copyIndex: 2), 3);
    });

    test('evaluates arithmetic with val and i', () {
      // val is base value (e.g. counter = 10)
      expect(RowFormulaEvaluator.evaluate(formula: 'val + i', baseVal: 10, copyIndex: 0), 10);
      expect(RowFormulaEvaluator.evaluate(formula: 'val + i', baseVal: 10, copyIndex: 1), 11);
      expect(RowFormulaEvaluator.evaluate(formula: 'val + i', baseVal: 10, copyIndex: 2), 12);
    });

    test('evaluates relative shorthand + 1', () {
      expect(RowFormulaEvaluator.evaluate(formula: '+ 1', baseVal: 5, copyIndex: 0), 6);
      expect(RowFormulaEvaluator.evaluate(formula: '+ i', baseVal: 5, copyIndex: 2), 7);
    });

    test('evaluates step/index variable (1-based)', () {
      expect(RowFormulaEvaluator.evaluate(formula: 'val + step', baseVal: 100, copyIndex: 0), 101);
      expect(RowFormulaEvaluator.evaluate(formula: 'val + step', baseVal: 100, copyIndex: 1), 102);
    });

    test(r'evaluates string templates with ${...}', () {
      expect(
        RowFormulaEvaluator.evaluate(formula: r'INV-${i + 1}', baseVal: 'INV-0', copyIndex: 0),
        'INV-1',
      );
      expect(
        RowFormulaEvaluator.evaluate(formula: r'INV-${i + 1}', baseVal: 'INV-0', copyIndex: 1),
        'INV-2',
      );
    });

    test('handles empty or non-formula fallback gracefully', () {
      expect(RowFormulaEvaluator.evaluate(formula: '', baseVal: 'hello', copyIndex: 0), 'hello');
      expect(RowFormulaEvaluator.evaluate(formula: 'custom_fixed_str', baseVal: 'orig', copyIndex: 0), 'custom_fixed_str');
    });
  });
}
