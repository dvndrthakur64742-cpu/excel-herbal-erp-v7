import 'package:excel_herbal_erp/core/business_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('product expiry and batch tracking render human Yes/No values', () {
    expect(BusinessFormat.label('expiry_tracking'), 'Expiry Tracking');
    expect(BusinessFormat.label('batch_tracking'), 'Batch Tracking');
    for (final value in [true, 1, '1', 'yes', 'on', 'enabled']) {
      expect(BusinessFormat.value('expiry_tracking', value), 'Yes');
    }
    for (final value in [false, 0, '0', 'no', 'off', 'disabled']) {
      expect(BusinessFormat.value('expiry_tracking', value), 'No');
    }
    expect(BusinessFormat.value('batch_tracking', 'off'), 'No');
    expect(BusinessFormat.value('batch_tracking', 'on'), 'Yes');
    expect(BusinessFormat.value('expiry_tracking', null), '—');
    expect(BusinessFormat.value('expiry_tracking', 'unexpected'), '—');
  });

  test('product commercial fields retain currency, casing and acronym labels', () {
    expect(BusinessFormat.label('mrp'), 'MRP');
    expect(BusinessFormat.label('sku'), 'SKU');
    expect(BusinessFormat.value('mrp', 499), startsWith('₹'));
    expect(BusinessFormat.value('sale_price', '449.00'), startsWith('₹'));
    expect(BusinessFormat.value('product_name', 'HERBAL BODY OIL'),
        'Herbal Body Oil');
  });
}
