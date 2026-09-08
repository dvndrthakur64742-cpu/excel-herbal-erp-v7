import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/commercial_integrity.dart';

void main() {
  group('CommercialIntegrity', () {
    test('accepts balanced commercial values', () {
      final error = CommercialIntegrity.validate(
        mrp: 200,
        salePrice: 170,
        hoAmount: 100,
        bmProfit: 20,
        salaryFund: 30,
        officeExpense: 20,
        points: 10,
        purchaseCost: 55,
      );
      expect(error, isNull);
    });

    test('blocks sale price above MRP', () {
      final error = CommercialIntegrity.validate(
        mrp: 145,
        salePrice: 170,
        hoAmount: 100,
        bmProfit: 20,
        salaryFund: 30,
        officeExpense: 20,
        points: 10,
        purchaseCost: 55,
      );
      expect(error, contains('MRP'));
    });

    test('blocks distribution imbalance', () {
      final error = CommercialIntegrity.validate(
        mrp: 200,
        salePrice: 170,
        hoAmount: 100,
        bmProfit: 20,
        salaryFund: 30,
        officeExpense: 10,
        points: 10,
        purchaseCost: 55,
      );
      expect(error, contains('Sale Price'));
    });

    test('blank numeric text is not silently converted to zero', () {
      expect(CommercialIntegrity.parseRequired(''), isNull);
      expect(CommercialIntegrity.parseRequired('abc'), isNull);
      expect(CommercialIntegrity.parseRequired('0'), 0);
    });

    test('negative values are rejected', () {
      final error = CommercialIntegrity.validate(
        mrp: 200,
        salePrice: 170,
        hoAmount: -1,
        bmProfit: 21,
        salaryFund: 30,
        officeExpense: 20,
        points: 10,
        purchaseCost: 55,
      );
      expect(error, contains('negative'));
    });

    test('business date validation is strict', () {
      expect(CommercialIntegrity.validBusinessDate('2026-09-08'), isTrue);
      expect(CommercialIntegrity.validBusinessDate('2026-02-30'), isFalse);
      expect(CommercialIntegrity.validBusinessDate('08-09-2026'), isFalse);
    });

    test('payload preserves explicit zero purchase cost', () {
      final values = CommercialIntegrity.values(
        mrp: 200,
        salePrice: 170,
        hoAmount: 100,
        bmProfit: 20,
        salaryFund: 30,
        officeExpense: 20,
        points: 10,
        purchaseCost: 0,
      );
      expect(values.toPayload()['purchase_cost'], 0);
      expect(values.distributionTotal, 170);
      expect(values.discount, 30);
    });
  });
}
