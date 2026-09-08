class CommercialValues {
  const CommercialValues({
    required this.mrp,
    required this.salePrice,
    required this.hoAmount,
    required this.bmProfit,
    required this.salaryFund,
    required this.officeExpense,
    required this.points,
    required this.purchaseCost,
  });

  final double mrp;
  final double salePrice;
  final double hoAmount;
  final double bmProfit;
  final double salaryFund;
  final double officeExpense;
  final double points;
  final double purchaseCost;

  double get distributionTotal =>
      hoAmount + bmProfit + salaryFund + officeExpense;

  double get discount => mrp - salePrice;

  Map<String, dynamic> toPayload() => {
        'mrp': mrp,
        'sale_price': salePrice,
        'ho_amount': hoAmount,
        'bm_profit': bmProfit,
        'salary_fund': salaryFund,
        'office_expense': officeExpense,
        'points': points,
        'purchase_cost': purchaseCost,
      };
}

abstract final class CommercialIntegrity {
  static double? parseRequired(String text) {
    final value = double.tryParse(text.trim());
    if (value == null || !value.isFinite) return null;
    return value;
  }

  static String? validate({
    required double? mrp,
    required double? salePrice,
    required double? hoAmount,
    required double? bmProfit,
    required double? salaryFund,
    required double? officeExpense,
    required double? points,
    required double? purchaseCost,
  }) {
    final values = <String, double?>{
      'MRP': mrp,
      'Sale Price': salePrice,
      'HO Amount': hoAmount,
      'BM Profit': bmProfit,
      'Salary Fund': salaryFund,
      'Office Expense': officeExpense,
      'Points': points,
      'Purchase Cost': purchaseCost,
    };
    for (final entry in values.entries) {
      final value = entry.value;
      if (value == null) return '${entry.key} valid number hona chahiye.';
      if (value < 0) return '${entry.key} negative nahi ho sakta.';
    }
    if (mrp! <= 0) return 'MRP zero se zyada hona chahiye.';
    if (salePrice! <= 0) return 'Sale Price zero se zyada hona chahiye.';
    if (salePrice - mrp > 0.005) {
      return 'Sale Price MRP se zyada nahi ho sakta.';
    }
    final distribution = hoAmount! + bmProfit! + salaryFund! + officeExpense!;
    if ((distribution - salePrice).abs() > 0.01) {
      return 'HO Amount + BM Profit + Salary Fund + Office Expense ka total Sale Price ke barabar hona chahiye.';
    }
    return null;
  }

  static CommercialValues values({
    required double mrp,
    required double salePrice,
    required double hoAmount,
    required double bmProfit,
    required double salaryFund,
    required double officeExpense,
    required double points,
    required double purchaseCost,
  }) =>
      CommercialValues(
        mrp: mrp,
        salePrice: salePrice,
        hoAmount: hoAmount,
        bmProfit: bmProfit,
        salaryFund: salaryFund,
        officeExpense: officeExpense,
        points: points,
        purchaseCost: purchaseCost,
      );

  static bool validBusinessDate(String text) {
    final raw = text.trim();
    final match = RegExp(r'^\d{4}-\d{2}-\d{2}$').firstMatch(raw);
    if (match == null) return false;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return false;
    final canonical =
        '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    return canonical == raw;
  }
}