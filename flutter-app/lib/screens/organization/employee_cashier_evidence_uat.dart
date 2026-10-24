import 'package:flutter/material.dart';

/// Strict read-only contract from isolated v8_test; no live WordPress V7
/// endpoint currently provides cashier-verified Cash or PSP evidence.
class CashierEvidenceUatPage {
  const CashierEvidenceUatPage._({
    required this.records,
    required this.unverified,
    required this.hasMore,
  });

  final List<CashierEvidenceUatRecord> records;
  /// Original B2B sources with no independently proven receipt/approval.
  /// These are review candidates, never employee outstanding balances.
  final List<UnverifiedCashEvidenceUatRecord> unverified;
  final bool hasMore;

  static Map<String, dynamic> map(dynamic raw) {
    if (raw is! Map) throw const FormatException('UAT evidence must be an object.');
    return Map<String, dynamic>.from(raw);
  }

  static int id(dynamic raw) {
    if (raw is! int && raw is! String ||
        !RegExp(r'^[1-9][0-9]{0,14}$').hasMatch(raw.toString())) {
      throw const FormatException('UAT evidence identity invalid.');
    }
    final value = int.tryParse(raw.toString());
    if (value == null) throw const FormatException('UAT evidence identity overflow.');
    return value;
  }

  static int paise(dynamic raw) {
    if (raw is! int && raw is! String ||
        !RegExp(r'^[1-9][0-9]{0,13}$').hasMatch(raw.toString())) {
      throw const FormatException('UAT evidence amount invalid.');
    }
    final value = int.tryParse(raw.toString());
    if (value == null) throw const FormatException('UAT evidence amount overflow.');
    return value;
  }

  static String inr(int paise) =>
      '₹${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

  factory CashierEvidenceUatPage.fromResponse({
    required dynamic response,
    required int companyId,
    required int branchId,
    required int employeeId,
    required String from,
    required String to,
  }) {
    final data = map(response);
    final period = map(data['period']);
    final sources = map(data['source_pages']);
    final canonical = map(sources['canonical_b2b_field_cash']);
    final legacy = map(sources['legacy_daily_orders']);
    if (data['read_only'] != true ||
        data['scope'] != 'disposable_v8_test_finance_review_only' ||
        data['source_keys_independent'] != true ||
        data['same_sale_across_sources_not_proven'] != true ||
        data['combined_sale_total_paise'] != null ||
        data['combined_employee_cash_outstanding_paise'] != null ||
        data['physical_legacy_daily_cash_verified'] != false ||
        data['external_bank_deposit_verified'] != false ||
        data['snapshot_isolation_guaranteed'] != false ||
        data['page_totals_not_a_full_period'] != true ||
        data['cross_source_duplicate_prevention_active'] != false ||
        data['verified_transaction_links'] is! List ||
        (data['verified_transaction_links'] as List).isNotEmpty ||
        id(data['company_id']) != companyId ||
        id(data['branch_id']) != branchId ||
        id(data['employee_id']) != employeeId ||
        period['from'] != from || period['to'] != to ||
        DateTime.tryParse(from) == null || DateTime.tryParse(to) == null ||
        from.compareTo(to) > 0 ||
        canonical['has_more'] is! bool || legacy['has_more'] is! bool ||
        canonical['rows'] is! List || legacy['rows'] is! List) {
      throw const FormatException('UAT source identity or period mismatch.');
    }
    final cashRows = canonical['rows'] as List;
    final dailyRows = legacy['rows'] as List;
    if (cashRows.length > 25 || dailyRows.length > 25) {
      throw const FormatException('UAT finance page size invalid.');
    }
    for (final raw in dailyRows) {
      final row = map(raw);
      if (row['source_type'] != 'daily_cycle' ||
          row['cash_handover_verified'] != false ||
          row['source_key'] != 'daily_cycle:${id(row['source_id'])}') {
        throw const FormatException('Legacy Daily Order cannot prove a cashier receipt.');
      }
    }
    final records = <CashierEvidenceUatRecord>[];
    final unverified = <UnverifiedCashEvidenceUatRecord>[];
    final sourceSeen = <int>{};
    final receiptSeen = <int>{};
    final remittanceSeen = <int>{};
    final journalSeen = <int>{};
    for (final raw in cashRows) {
      final row = map(raw);
      final saleId = id(row['source_id']);
      final amount = paise(row['field_cash_reported_paise']);
      final key = 'b2b_retailer_sale:${saleId}';
      final date = row['business_date'];
      if (!sourceSeen.add(saleId) ||
          row['source_type'] != 'b2b_retailer_sale' ||
          row['source_key'] != key ||
          date is! String || date.compareTo(from) < 0 ||
          date.compareTo(to) > 0 ||
          paise(row['posted_sale_paise']) != amount ||
          row['upi_reported_paise'] != 0 ||
          row['upi_bank_verified'] != false) {
        throw const FormatException('UAT B2B Cash page source invalid.');
      }
      final verified = row['cash_handover_verified'] == true &&
          row['journal_consistent'] == true &&
          row['cash_custody_state'] == 'cashier_handover_reconciled_uat';
      final rawProof = row['cashier_finance_evidence'];
      if (!verified) {
        if (row['cash_handover_verified'] != false || rawProof != null) {
          throw const FormatException('Unverified cashier proof is not permitted.');
        }
        unverified.add(UnverifiedCashEvidenceUatRecord(saleId: saleId, date: date));
        continue;
      }
      final proof = map(rawProof);
      final receipt = map(proof['cashier_receipt']);
      final check = map(proof['finance_check']);
      final receiptId = id(receipt['receipt_id']);
      final cashierUser = id(receipt['cashier_user_id']);
      final cashierEmployee = id(receipt['cashier_employee_id']);
      final checkerUser = id(check['checker_user_id']);
      final checkerEmployee = id(check['checker_employee_id']);
      final journalId = id(check['journal_id']);
      final remittanceId = id(check['remittance_id']);
      final reference = receipt['reference'];
      if (proof['evidence_scope'] !=
              'disposable_v8_test_verified_canonical_b2b_only' ||
          proof['source_key'] != key ||
          proof['cash_transit_reclassification_verified_uat'] != true ||
          proof['physical_cash_confirmed_on_office_staging'] != false ||
          proof['production_financial_status'] != 'not_certified' ||
          receipt['state'] != 'confirmed_uat' ||
          check['state'] != 'posted_uat' ||
          reference is! String ||
          !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/-]{7,127}$').hasMatch(reference) ||
          paise(receipt['amount_paise']) != amount ||
          paise(check['amount_paise']) != amount ||
          cashierUser == checkerUser || cashierEmployee == checkerEmployee ||
          cashierEmployee == employeeId || checkerEmployee == employeeId ||
          !receiptSeen.add(receiptId) || !remittanceSeen.add(remittanceId) ||
          !journalSeen.add(journalId)) {
        throw const FormatException('Cashier / Finance evidence chain invalid.');
      }
      records.add(CashierEvidenceUatRecord(
        saleId: saleId, date: date, amountPaise: amount,
        receiptId: receiptId, reference: reference,
        cashierEmployeeId: cashierEmployee, checkerEmployeeId: checkerEmployee,
        remittanceId: remittanceId, journalId: journalId,
      ));
    }
    return CashierEvidenceUatPage._(
      records: List.unmodifiable(records),
      unverified: List.unmodifiable(unverified),
      hasMore: canonical['has_more'] == true,
    );
  }
}

class CashierEvidenceUatRecord {
  const CashierEvidenceUatRecord({
    required this.saleId, required this.date, required this.amountPaise,
    required this.receiptId, required this.reference,
    required this.cashierEmployeeId, required this.checkerEmployeeId,
    required this.remittanceId, required this.journalId,
  });
  final int saleId;
  final String date;
  final int amountPaise;
  final int receiptId;
  final String reference;
  final int cashierEmployeeId;
  final int checkerEmployeeId;
  final int remittanceId;
  final int journalId;
}

class UnverifiedCashEvidenceUatRecord {
  const UnverifiedCashEvidenceUatRecord({required this.saleId, required this.date});
  final int saleId;
  final String date;
}

/// Testable UAT-only Finance Review section; never shown without an explicitly
/// provided, fully verified and scope-validated isolated cross-source page.
class CashierEvidenceUatSection extends StatelessWidget {
  const CashierEvidenceUatSection({super.key, required this.page});
  final CashierEvidenceUatPage page;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cashier → Finance Checker · UAT ONLY',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('Read-only original B2B journal evidence. NOT Office Cash proof, '
              'NOT bank settlement, NOT employee outstanding. Legacy Daily Orders excluded.'),
          const SizedBox(height: 8),
          Text('Page 1 · ${page.records.length} verified · '
              '${page.unverified.length} require evidence review'),
          for (final item in page.records)
            ListTile(
              key: ValueKey('uat-cash-evidence-${item.saleId}'),
              leading: const Icon(Icons.verified_user_outlined),
              title: Text('B2B #${item.saleId} · ${CashierEvidenceUatPage.inr(item.amountPaise)}'),
              subtitle: Text(
                '${item.date} · Receipt ${item.reference} (#${item.receiptId})\n'
                'Cashier employee #${item.cashierEmployeeId} → '
                'Finance checker #${item.checkerEmployeeId}\n'
                'Remittance #${item.remittanceId} → GL journal #${item.journalId}',
              ),
            ),
          if (page.unverified.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Unverified original Cash sources',
                style: Theme.of(context).textTheme.titleSmall),
            for (final item in page.unverified)
              ListTile(
                key: ValueKey('uat-cash-unverified-${item.saleId}'),
                leading: const Icon(Icons.pending_actions_outlined),
                title: Text('B2B #${item.saleId} · ${item.date}'),
                subtitle: const Text('Receipt and independent Finance approval NOT verified. '
                    'Review source records; do not infer an employee shortage.'),
              ),
          ],
          if (page.records.isEmpty)
            const Text('No independently verified B2B Cash handover on this UAT page.'),
          if (page.hasMore)
            const Text('More B2B sources exist. This is page 1, not the full period.'),
        ],
      ),
    ),
  );
}
