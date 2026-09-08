abstract final class TransactionGuardrails {
  static const double moneyTolerance = 0.005;

  static String? counterSale({
    required num gross,
    required num paid,
    required int? customerId,
    required int? paymentAccountId,
  }) {
    final grossValue = gross.toDouble();
    final paidValue = paid.toDouble();
    if (!grossValue.isFinite || grossValue <= 0) {
      return 'Sale total valid aur positive hona chahiye.';
    }
    if (!paidValue.isFinite || paidValue < 0) {
      return 'Paid amount negative ya invalid nahi ho sakta.';
    }
    if (paidValue > grossValue + moneyTolerance) {
      return 'Paid amount sale total se zyada nahi ho sakta.';
    }
    final outstanding = grossValue - paidValue;
    if (outstanding > moneyTolerance && customerId == null) {
      return 'Credit sale ke liye registered customer select karein.';
    }
    if (paidValue > moneyTolerance && paymentAccountId == null) {
      return 'Received amount ke liye Cash / Bank / UPI account select karein.';
    }
    return null;
  }

  static String? customerReceipt({
    required int? saleId,
    required int? paymentAccountId,
    required num amount,
    required num outstanding,
  }) {
    if (saleId == null) return 'Outstanding sale select karein.';
    if (paymentAccountId == null) return 'Payment account select karein.';
    final value = amount.toDouble();
    final due = outstanding.toDouble();
    if (!value.isFinite || value <= 0) {
      return 'Receipt amount positive hona chahiye.';
    }
    if (!due.isFinite || due <= 0) {
      return 'Selected sale par outstanding amount available nahi hai.';
    }
    if (value > due + moneyTolerance) {
      return 'Receipt selected sale ke outstanding se zyada nahi ho sakti.';
    }
    return null;
  }

  static String? purchaseLine({
    required num quantity,
    required num unitCost,
    required bool batchRequired,
    required String batchNo,
  }) {
    final qty = quantity.toDouble();
    final cost = unitCost.toDouble();
    if (!qty.isFinite || qty <= 0) return 'Purchase quantity positive honi chahiye.';
    if (!cost.isFinite || cost < 0) return 'Unit Cost valid aur non-negative hona chahiye.';
    if (batchRequired && batchNo.trim().isEmpty) {
      return 'Is product ke liye Batch No. required hai.';
    }
    return null;
  }

  static String? supplierPayment({
    required int? billId,
    required int? paymentAccountId,
    required num amount,
    required num outstanding,
  }) {
    if (billId == null) return 'Outstanding supplier bill select karein.';
    if (paymentAccountId == null) return 'Payment account select karein.';
    final value = amount.toDouble();
    final due = outstanding.toDouble();
    if (!value.isFinite || value <= 0) {
      return 'Supplier payment amount positive hona chahiye.';
    }
    if (!due.isFinite || due <= 0) {
      return 'Selected bill par outstanding amount available nahi hai.';
    }
    if (value > due + moneyTolerance) {
      return 'Supplier payment bill outstanding se zyada nahi ho sakti.';
    }
    return null;
  }

  static String? expense({
    required int? expenseHeadId,
    required int? paymentAccountId,
    required num amount,
  }) {
    if (expenseHeadId == null) return 'Expense Head select karein.';
    if (paymentAccountId == null) return 'Payment account select karein.';
    final value = amount.toDouble();
    if (!value.isFinite || value <= 0) return 'Expense amount positive hona chahiye.';
    return null;
  }

  static String? bankStatementLine({
    required String date,
    required num debit,
    required num credit,
  }) {
    if (!_validIsoDate(date)) return 'Valid transaction date YYYY-MM-DD me enter karein.';
    final dr = debit.toDouble();
    final cr = credit.toDouble();
    if (!dr.isFinite || !cr.isFinite || dr < 0 || cr < 0) {
      return 'Debit/Credit valid non-negative amount hona chahiye.';
    }
    if ((dr > moneyTolerance) == (cr > moneyTolerance)) {
      return 'Statement line me Debit ya Credit me se sirf ek positive amount enter karein.';
    }
    return null;
  }

  static String? dateRange(String from, String to) {
    if (!_validIsoDate(from) || !_validIsoDate(to)) {
      return 'Valid date range YYYY-MM-DD format me enter karein.';
    }
    final start = DateTime.parse(from.trim());
    final end = DateTime.parse(to.trim());
    if (start.isAfter(end)) return 'From date To date ke baad nahi ho sakti.';
    return null;
  }

  static bool _validIsoDate(String raw) {
    final value = raw.trim();
    final match = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
    if (!match) return false;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return false;
    final normalized =
        '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    return normalized == value;
  }
}
