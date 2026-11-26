import 'transaction_guardrails.dart';

abstract final class BankReconciliationInput {
  static String? validate({
    required int? accountId,
    required String from,
    required String to,
    required String opening,
    required String closing,
  }) {
    if (accountId == null || accountId <= 0) return 'Select a bank account.';
    final dateError = TransactionGuardrails.dateRange(from.trim(), to.trim());
    if (dateError != null) return dateError;
    for (final value in [opening, closing]) {
      final text = value.trim();
      if (!RegExp(r'^-?\d{1,12}(?:\.\d{1,2})?$').hasMatch(text)) {
        return 'Enter valid opening and closing balances with up to 2 decimal places.';
      }
      final amount = double.tryParse(text);
      if (amount == null || !amount.isFinite) return 'Invalid balance.';
    }
    return null;
  }
}