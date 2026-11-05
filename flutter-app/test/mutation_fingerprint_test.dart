import 'package:excel_herbal_erp/core/mutation_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mutation fingerprint is stable for equivalent map ordering', () {
    final first = buildMutationFingerprint(
      'POST',
      '/inventory/adjustments',
      query: {'branch_id': 7, 'mode': 'draft'},
      data: {
        'reason': 'count',
        'lines': [
          {'product_id': 2, 'quantity': 3},
        ],
      },
    );
    final second = buildMutationFingerprint(
      'POST',
      '/inventory/adjustments',
      query: {'mode': 'draft', 'branch_id': 7},
      data: {
        'lines': [
          {'quantity': 3, 'product_id': 2},
        ],
        'reason': 'count',
      },
    );

    expect(second, first);
  });

  test('mutation fingerprint changes when query scope changes', () {
    final branch7 = buildMutationFingerprint(
      'POST',
      '/inventory/adjustments',
      query: {'branch_id': 7},
      data: const {'reason': 'count'},
    );
    final branch8 = buildMutationFingerprint(
      'POST',
      '/inventory/adjustments',
      query: {'branch_id': 8},
      data: const {'reason': 'count'},
    );

    expect(branch8, isNot(branch7));
  });
}
