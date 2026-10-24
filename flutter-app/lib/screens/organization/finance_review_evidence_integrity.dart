/// Validates original V7 Daily Order source rows against displayed page totals.
/// It cannot verify a physical Cash receipt, bank settlement or employee debt.
abstract final class FinanceReviewEvidenceIntegrity {
  static const maxSafe = 9007199254740991;

  static bool validDay(dynamic value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return false;
    }
    final date = DateTime.tryParse('${value}T00:00:00Z');
    return date != null && date.toIso8601String().startsWith('${value}T');
  }

  static int money(dynamic raw) {
    if (raw is! int && raw is! String ||
        !RegExp(r'^(0|[1-9][0-9]{0,15})$').hasMatch(raw.toString())) {
      throw const FormatException('Finance evidence amount invalid.');
    }
    final value = int.tryParse(raw.toString());
    if (value == null || value > maxSafe) {
      throw const FormatException('Finance paise unsafe for Flutter Web.');
    }
    return value;
  }

  static void validate({
    required List<Map<String, dynamic>> rows,
    required String from,
    required String to,
    required dynamic pageCash,
    required dynamic pageUpi,
    required dynamic pageMismatches,
  }) {
    if (!validDay(from) || !validDay(to) || from.compareTo(to) > 0) {
      throw const FormatException('Finance reporting period invalid.');
    }
    final sourceIds = <int>{};
    var cashTotal = 0;
    var upiTotal = 0;
    var mismatches = 0;
    for (final row in rows) {
      final id = money(row['daily_cycle_id']);
      if (id == 0 || !sourceIds.add(id)) {
        throw const FormatException('Duplicate Daily Order cash evidence source.');
      }
      final date = row['business_date'];
      if (!validDay(date) ||
          (date as String).compareTo(from) < 0 || date.compareTo(to) > 0) {
        throw const FormatException('Daily Order evidence escaped selected period.');
      }
      final cash = money(row['reported_cash_paise']);
      final upi = money(row['reported_upi_paise']);
      if (cash > maxSafe - cashTotal || upi > maxSafe - upiTotal) {
        throw const FormatException('Finance page sum exceeds safe precision.');
      }
      cashTotal += cash;
      upiTotal += upi;
      final journal = row['journal_check'];
      if (!const {
        'journal_amounts_match', 'journal_amount_mismatch',
        'missing_journal', 'duplicate_journal',
      }.contains(journal)) {
        throw const FormatException('Unknown canonical journal state.');
      }
      if (journal != 'journal_amounts_match') mismatches++;
      if (row.containsKey('cash_remittance_proof') &&
          row['cash_remittance_proof'] !=
              (cash > 0 ? 'not_evidenced_in_legacy_v7' : 'not_applicable')) {
        throw const FormatException('Untrusted physical Cash proof.');
      }
      if (row.containsKey('upi_bank_settlement_proof') &&
          row['upi_bank_settlement_proof'] !=
              (upi > 0 ? 'not_verified_by_this_report' : 'not_applicable')) {
        throw const FormatException('Untrusted UPI bank settlement proof.');
      }
    }
    if (cashTotal != money(pageCash) || upiTotal != money(pageUpi) ||
        mismatches != money(pageMismatches)) {
      throw const FormatException('Finance page totals and source rows disagree.');
    }
  }
}
