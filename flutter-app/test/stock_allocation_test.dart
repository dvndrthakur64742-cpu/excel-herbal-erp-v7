import 'package:excel_herbal_erp/core/stock_allocation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FEFO allocation consumes earliest expiry first', () {
    final allocations = StockAllocation.fefo(
      requestLines: [
        {'id': 10, 'product_id': 1, 'product_name': 'P1', 'quantity': 6},
      ],
      stock: [
        {
          'product_id': 1,
          'custodian_key': 0,
          'quantity': 5,
          'batch_key': 20,
          'expires_on': '2027-12-31',
        },
        {
          'product_id': 1,
          'custodian_key': 0,
          'quantity': 4,
          'batch_key': 10,
          'expires_on': '2027-01-31',
        },
      ],
    );
    expect(allocations.length, 2);
    expect(allocations[0]['batch_id'], 10);
    expect(allocations[0]['quantity'], 4);
    expect(allocations[1]['batch_id'], 20);
    expect(allocations[1]['quantity'], 2);
  });

  test('allocation fails when authorised stock is insufficient', () {
    expect(
      () => StockAllocation.fefo(
        requestLines: [
          {'id': 10, 'product_id': 1, 'product_name': 'P1', 'quantity': 6},
        ],
        stock: [
          {'product_id': 1, 'custodian_key': 0, 'quantity': 5},
        ],
      ),
      throwsA(isA<StockAllocationException>()),
    );
  });
}
