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

  static String? nonNegativeMoneyText(
    String raw, {
    required String label,
  }) {
    final value = double.tryParse(raw.trim());
    if (value == null || !value.isFinite || value < 0) {
      return '$label must be a valid non-negative amount.';
    }
    return null;
  }

  static String? candidateRegister({
    required String fullName,
    required String? designationCode,
    required String mobile,
    required String email,
    required bool validateSalary,
    required String salaryText,
  }) {
    if (fullName.trim().isEmpty) return 'Full Name is required.';
    if (designationCode == null || designationCode.trim().isEmpty) {
      return 'Proposed Designation is required.';
    }
    final contactError = _personContact(
      mobile: mobile,
      email: email,
      requireAny: true,
      emailError: 'Enter a valid candidate email address.',
    );
    if (contactError != null) return contactError;
    if (validateSalary) {
      return nonNegativeMoneyText(
        salaryText,
        label: 'Offered Monthly Salary',
      );
    }
    return null;
  }

  static String? employeeCreate({
    required String employeeCode,
    required String fullName,
    required String? designationCode,
    required String mobile,
    required String email,
    required String joiningDate,
  }) {
    if (employeeCode.trim().isEmpty) return 'Employee Code is required.';
    if (fullName.trim().isEmpty) return 'Full Name is required.';
    if (designationCode == null || designationCode.trim().isEmpty) {
      return 'Designation is required.';
    }
    final contactError = _personContact(
      mobile: mobile,
      email: email,
      requireAny: false,
      emailError: 'Enter a valid employee email address.',
    );
    if (contactError != null) return contactError;
    if (!_validIsoDate(joiningDate)) {
      return 'Joining Date must be a valid YYYY-MM-DD date.';
    }
    return null;
  }

  static String? _personContact({
    required String mobile,
    required String email,
    required bool requireAny,
    required String emailError,
  }) {
    final rawMobile = mobile.trim();
    final cleanEmail = email.trim();
    if (requireAny && rawMobile.isEmpty && cleanEmail.isEmpty) {
      return 'Mobile or Email is required.';
    }
    if (rawMobile.isNotEmpty) {
      if (!RegExp(r'^[0-9+\-\s()]+$').hasMatch(rawMobile)) {
        return 'Mobile number contains invalid characters.';
      }
      final digits = rawMobile.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 8 || digits.length > 15) {
        return 'Mobile number must contain 8 to 15 digits.';
      }
    }
    if (cleanEmail.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(cleanEmail)) {
      return emailError;
    }
    return null;
  }

  static String? productCreate({
    required String sku,
    required String name,
    required String uom,
    required String batchMode,
    required bool expiryTracking,
  }) {
    final cleanSku = sku.trim();
    final cleanName = name.trim();
    final cleanUom = uom.trim();
    if (cleanSku.isEmpty) return 'SKU is required.';
    if (cleanSku.length > 80) return 'SKU must be 80 characters or fewer.';
    if (cleanName.isEmpty) return 'Product Name is required.';
    if (cleanName.length > 190) {
      return 'Product Name must be 190 characters or fewer.';
    }
    if (cleanUom.isEmpty) return 'UOM is required.';
    if (cleanUom.length > 40) return 'UOM must be 40 characters or fewer.';
    if (!const {'off', 'optional', 'required'}.contains(batchMode)) {
      return 'Select a valid Batch Tracking mode.';
    }
    if (expiryTracking && batchMode == 'off') {
      return 'Expiry Tracking requires Batch Tracking.';
    }
    return null;
  }

  static String? stockTransfer({
    required int? sourceBranchId,
    required int? destinationBranchId,
    required bool itemSelected,
    required num quantity,
    required num available,
  }) {
    if (sourceBranchId == null) return 'Source Branch is required.';
    if (destinationBranchId == null) return 'Destination Branch is required.';
    if (sourceBranchId == destinationBranchId) {
      return 'Destination Branch must be different from Source Branch.';
    }
    if (!itemSelected) return 'Select a stock item.';
    final qty = quantity.toDouble();
    final availableQty = available.toDouble();
    if (!qty.isFinite || qty <= 0) {
      return 'Transfer quantity must be greater than zero.';
    }
    if (!availableQty.isFinite || availableQty <= 0) {
      return 'Selected stock item has no transferable quantity.';
    }
    if (qty > availableQty + 0.0001) {
      return 'Transfer quantity cannot exceed available stock.';
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
