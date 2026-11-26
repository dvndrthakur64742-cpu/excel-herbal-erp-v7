import 'package:excel_herbal_erp/core/purchase_bill_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('purchase total rounds each four-decimal cost line to paise', () {
    expect(PurchaseBillPreview.total([
      (quantity: '2', unitCost: '12.3456'),
      (quantity: '1', unitCost: '0.0050'),
      (quantity: '4', unitCost: '0'),
    ]), 24.70);
  });
  test('incomplete, invalid and excessive lines have no estimated total', () {
    for (final line in [
      (quantity: '', unitCost: '2'),
      (quantity: '0', unitCost: '2'),
      (quantity: '1.5', unitCost: '2'),
      (quantity: '2', unitCost: ''),
      (quantity: '2', unitCost: '-1'),
      (quantity: '2', unitCost: 'NaN'),
      (quantity: '2', unitCost: '1.00001'),
      (quantity: '999999999', unitCost: '9999999999.9999'),
    ]) {
      expect(PurchaseBillPreview.total([line]), isNull);
    }
  });
}
