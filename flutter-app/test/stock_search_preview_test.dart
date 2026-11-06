import 'package:excel_herbal_erp/core/stock_search_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stock search explicitly shows branch, employee holder and actual unit',
      () {
    final source = <String, dynamic>{
      'id': 57, 'branch_id': 1, 'product_name': 'Air Freshener',
      'custodian_key': 4, 'custodian_name': 'Amit Sharma',
      'quantity': '2.000', 'uom': 'PCS',
    };
    final fields = StockSearchPreview.fields(
      source, selectedBranchName: 'Head Office',
    );
    expect(fields.map((x) => x.key).toList(), [
      'search_branch', 'search_custodian', 'search_quantity',
    ]);
    expect(fields.map((x) => x.value).toList(), [
      'Head Office', 'Employee: Amit Sharma', '2 PCS',
    ]);
    expect(source.containsKey('search_branch'), isFalse);
    expect(source['id'], 57);
  });

  test('warehouse and unidentified staff custody remain distinguishable', () {
    final warehouse = StockSearchPreview.fields(
      {'custodian_key': 0, 'quantity': 184, 'uom': 'PCS'},
      selectedBranchName: 'Mandi',
    );
    final unknownStaff = StockSearchPreview.fields(
      {'custodian_key': 9, 'quantity': 4, 'uom': 'PCS'},
      selectedBranchName: 'Mandi',
    );
    expect(warehouse[1].value, 'Branch warehouse');
    expect(unknownStaff[1].value, 'Employee #9');
    expect(warehouse[2].value, '184 PCS');
    expect(unknownStaff[2].value, '4 PCS');
  });

  test('incomplete search rows have accurate fallbacks, never guessed stock',
      () {
    final preview = StockSearchPreview.fields(
      <String, dynamic>{},
      selectedBranchName: '  ',
    );
    expect(preview[0].value, 'Selected branch');
    expect(preview[1].value, 'Branch warehouse');
    expect(preview[2].value, 'Not available');
  });
}
