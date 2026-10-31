import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/entity_relations.dart';

void main() {
  test('sameId normalizes numeric strings and numbers', () {
    expect(EntityRelations.sameId('12', 12), isTrue);
    expect(EntityRelations.sameId(12.0, '12'), isTrue);
    expect(EntityRelations.sameId('12', 13), isFalse);
  });

  test('byForeignKey returns only related rows', () {
    final rows = <Map<String, dynamic>>[
      {'id': '1', 'customer_id': '7'},
      {'id': '2', 'customer_id': 8},
      {'id': '3', 'customer_id': 7},
    ];
    final related = EntityRelations.byForeignKey(rows, 'customer_id', '7');
    expect(related.map((e) => e['id']).toList(), ['1', '3']);
  });

  test('sum parses decimal strings without losing values', () {
    final rows = <Map<String, dynamic>>[
      {'amount': '10.50'},
      {'amount': 20},
      {'amount': '1,000.25'},
      {'amount': null},
    ];
    expect(EntityRelations.sum(rows, 'amount'), closeTo(1030.75, 0.0001));
  });

  test('firstById uses normalized identifiers', () {
    final rows = <Map<String, dynamic>>[
      {'id': '4', 'name': 'A'},
      {'id': '5', 'name': 'B'},
    ];
    expect(EntityRelations.firstById(rows, 5)?['name'], 'B');
    expect(EntityRelations.firstById(rows, 9), isNull);
  });
}
