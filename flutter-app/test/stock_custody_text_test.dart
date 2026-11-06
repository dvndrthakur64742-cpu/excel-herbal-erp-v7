import 'package:excel_herbal_erp/core/stock_custody_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('warehouse and employee-held balances are visibly distinct', () {
    expect(StockCustodyText.holder({'custodian_key': 0}), 'Branch warehouse');
    expect(
      StockCustodyText.holder({
        'custodian_key': 4,
        'custodian_name': 'Amit Sharma',
      }),
      'Employee: Amit Sharma',
    );
    expect(StockCustodyText.holder({'custodian_key': 8}), 'Employee #8');
  });

  test('stock rows include units, selected branch, batch and expiry', () {
    const row = {
      'uom': 'pcs',
      'batch_no': 'B-001',
      'expires_on': '2027-04-30',
    };
    expect(StockCustodyText.unit(row), 'pcs');
    expect(
      StockCustodyText.details(row, branchName: 'Head Office'),
      'Head Office · Batch: B-001 · Expiry: 2027-04-30',
    );
  });

  test('incomplete batch/custodian records have readable fallbacks', () {
    expect(StockCustodyText.unit({}), 'units');
    expect(StockCustodyText.details({}), 'Selected branch');
    expect(
      StockCustodyText.details({'batch_key': 5}, branchName: 'Mandi'),
      'Mandi · Batch #5',
    );
  });
}
