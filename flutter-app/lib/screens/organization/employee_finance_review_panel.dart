import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';

/// Finance-only live WordPress V7 read model. No financial writes or fake
/// cross-source balances; intentionally NOT the employee dashboard.
class EmployeeFinanceReviewPanel extends ConsumerStatefulWidget {
  const EmployeeFinanceReviewPanel({
    super.key,
    required this.employeeId,
    required this.from,
    required this.to,
    this.onOpenCashControl,
    this.onOpenPersonLedger,
  });

  final int employeeId;
  final String from;
  final String to;
  /// Opens the existing paginated finance register; never posts a transaction.
  final VoidCallback? onOpenCashControl;
  final VoidCallback? onOpenPersonLedger;

  @override
  ConsumerState<EmployeeFinanceReviewPanel> createState() =>
      _EmployeeFinanceReviewPanelState();
}

class _EmployeeFinanceReviewPanelState
    extends ConsumerState<EmployeeFinanceReviewPanel> {
  late Future<EmployeeFinanceReviewSnapshot> _result;

  @override
  void initState() {
    super.initState();
    _result = _fetch();
  }

  @override
  void didUpdateWidget(covariant EmployeeFinanceReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employeeId != widget.employeeId ||
        oldWidget.from != widget.from || oldWidget.to != widget.to) {
      _result = _fetch();
    }
  }

  Future<EmployeeFinanceReviewSnapshot> _fetch() async {
    // Defense in depth: a hidden finance tab must not start authenticated
    // Cash/GL requests after a role change. V7 REST rechecks permission.
    if (!ref.read(appStateProvider).can('finance.accounting.view')) {
      throw StateError('Finance permission required.');
    }
    final api = ref.read(apiClientProvider);
    final data = await Future.wait<dynamic>([
      api.get(
        ApiPaths.employee360CashControl(widget.employeeId),
        query: {
          'from': widget.from, 'to': widget.to,
          'page': 1, 'page_size': 25,
        },
      ),
      api.get(
        ApiPaths.employee360Register(widget.employeeId),
        query: {
          'type': 'person_ledger', 'from': widget.from,
          'to': widget.to, 'page': 1, 'page_size': 25,
        },
      ),
    ]);
    return EmployeeFinanceReviewSnapshot.fromResponses(
      employeeId: widget.employeeId,
      from: widget.from,
      to: widget.to,
      cashResponse: data[0],
      ledgerResponse: data[1],
    );
  }

  void _refresh() => setState(() => _result = _fetch());

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(appStateProvider).can('finance.accounting.view')) {
      return const Center(child: Text('Finance permission required.'));
    }
    return FutureBuilder<EmployeeFinanceReviewSnapshot>(
      future: _result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Finance Review unavailable: ' + UiError.message(snapshot.error!)),
                TextButton(onPressed: _refresh, child: const Text('Retry')),
              ],
            ),
          );
        }
        return EmployeeFinanceReviewView(
          snapshot: snapshot.data!,
          onRefresh: _refresh,
          onOpenCashControl: widget.onOpenCashControl,
          onOpenPersonLedger: widget.onOpenPersonLedger,
        );
      },
    );
  }
}

/// Validates both canonical REST contracts before any finance values render.
class EmployeeFinanceReviewSnapshot {
  EmployeeFinanceReviewSnapshot._({
    required this.cashBookedPaise,
    required this.upiBookedPaise,
    required this.mismatches,
    required this.unprovenCash,
    required this.hasMore,
    required this.ledgerHasMore,
    required this.ledgerEventPageCount,
    required this.closings,
    required this.accounts,
  });

  final int cashBookedPaise;
  final int upiBookedPaise;
  final int mismatches;
  final int unprovenCash;
  final bool hasMore;
  final bool ledgerHasMore;
  final int ledgerEventPageCount;
  final List<Map<String, dynamic>> closings;
  final List<Map<String, dynamic>> accounts;

  static int unsigned(dynamic value) {
    if (value is! int && value is! String) {
      throw const FormatException('Invalid financial integer.');
    }
    final raw = value.toString();
    if (!RegExp(r'^(0|[1-9][0-9]{0,15})$').hasMatch(raw)) {
      throw const FormatException('Invalid financial integer precision.');
    }
    final number = int.tryParse(raw);
    if (number == null) {
      throw const FormatException('Financial integer overflow.');
    }
    return number;
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) throw const FormatException('Finance source invalid.');
    return Map<String, dynamic>.from(value);
  }

  factory EmployeeFinanceReviewSnapshot.fromResponses({
    required int employeeId,
    required String from,
    required String to,
    required dynamic cashResponse,
    required dynamic ledgerResponse,
  }) {
    final cash = _map(cashResponse);
    final ledger = _map(ledgerResponse);
    // A stale/cross-period response must never be shown as the currently
    // selected employee accounting period, even if its employee ID matches.
    final cashPeriod = _map(cash['period']);
    final ledgerPeriod = _map(ledger['period']);
    if (DateTime.tryParse(from) == null ||
        DateTime.tryParse(to) == null ||
        from.compareTo(to) > 0 ||
        cashPeriod['from'] != from || cashPeriod['to'] != to ||
        ledgerPeriod['from'] != from || ledgerPeriod['to'] != to) {
      throw const FormatException('Finance Review reporting period mismatch.');
    }
    if (cash['read_only'] != true ||
        cash['scope'] != 'canonical_posted_daily_cycles_only' ||
        cash['cash_remittance_status'] != 'not_available_in_legacy_v7' ||
        unsigned(cash['employee_id']) != employeeId ||
        unsigned(cash['page']) != 1 ||
        unsigned(cash['page_size']) != 25 ||
        cash['has_more'] is! bool ||
        ledger['read_only'] != true ||
        ledger['register'] != 'person_ledger' ||
        ledger['scope'] != 'posted_gl_employee_tagged_and_canonical_stock_sales_points' ||
        ledger['balance_basis'] != 'complete_tagged_movement_history_not_visible_page' ||
        ledger['employee_cash_handover_verified'] != false ||
        ledger['upi_bank_settlement_verified'] != false ||
        unsigned(ledger['employee_id']) != employeeId ||
        unsigned(ledger['page']) != 1 ||
        unsigned(ledger['page_size']) != 25 ||
        ledger['has_more'] is! bool ||
        ledger['rows'] is! List ||
        ledger['financial_accounts'] is! List) {
      throw const FormatException('Employee Finance Review safety contract mismatch.');
    }
    final totals = _map(cash['page_totals']);
    final flags = _map(cash['page_flags']);
    final rawClosings = cash['rows'];
    final rawAccounts = ledger['financial_accounts'] as List;
    final rawLedgerEvents = ledger['rows'] as List;
    if (rawClosings is! List || rawClosings.length > 25 ||
        rawLedgerEvents.length > 25 || rawAccounts.length > 2000) {
      throw const FormatException('Employee Finance Review response exceeds bounds.');
    }
    final closings = rawClosings.map(_map).toList(growable: false);
    final accounts = rawAccounts.map(_map).toList(growable: false);
    for (final row in closings) {
      unsigned(row['daily_cycle_id']);
      unsigned(row['reported_cash_paise']);
      unsigned(row['reported_upi_paise']);
      if (row['business_date'] is! String ||
          (row['business_date'] as String).compareTo(from) < 0 ||
          (row['business_date'] as String).compareTo(to) > 0) {
        throw const FormatException('Cash closure escaped selected period.');
      }
      if (row['journal_check'] is! String) {
        throw const FormatException('Invalid canonical daily journal status.');
      }
    }
    for (final account in accounts) {
      if (account['account_code'] is! String ||
          account['currency'] != 'INR' ||
          !RegExp(r'^-?[0-9]{1,12}\.[0-9]{2}$')
              .hasMatch(account['opening_debit_minus_credit'].toString()) ||
          !RegExp(r'^-?[0-9]{1,12}\.[0-9]{2}$')
              .hasMatch(account['closing_debit_minus_credit'].toString())) {
        throw const FormatException('Invalid employee-tagged GL account.');
      }
    }
    final mismatches = unsigned(flags['journal_mismatch_count']);
    final unprovenCash = unsigned(flags['cash_remittance_unproven_count']);
    if (mismatches > closings.length || unprovenCash > closings.length) {
      throw const FormatException('Cash Control page flags are inconsistent.');
    }
    return EmployeeFinanceReviewSnapshot._(
      cashBookedPaise: unsigned(totals['cash_reported_paise']),
      upiBookedPaise: unsigned(totals['upi_reported_paise']),
      mismatches: mismatches,
      unprovenCash: unprovenCash,
      hasMore: cash['has_more'] == true,
      ledgerHasMore: ledger['has_more'] == true,
      ledgerEventPageCount: rawLedgerEvents.length,
      closings: closings,
      accounts: accounts,
    );
  }

  static String inr(int paise) =>
      '₹' + (paise ~/ 100).toString() + '.' +
      (paise % 100).toString().padLeft(2, '0');
}

/// Testable visual summary backed by original V7 read-only response data.
class EmployeeFinanceReviewView extends StatelessWidget {
  const EmployeeFinanceReviewView({
    super.key,
    required this.snapshot,
    this.onRefresh,
    this.onOpenCashControl,
    this.onOpenPersonLedger,
  });

  final EmployeeFinanceReviewSnapshot snapshot;
  final VoidCallback? onRefresh;
  final VoidCallback? onOpenCashControl;
  final VoidCallback? onOpenPersonLedger;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.shield_outlined),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Employee Finance Review', style: textTheme.titleMedium)),
                  if (onRefresh != null)
                    IconButton(
                      tooltip: 'Refresh finance evidence',
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                ]),
                const Text('Read-only · Canonical WordPress V7 records · Finance-only'),
                const SizedBox(height: 6),
                const Text('Booked Cash/UPI is NOT physical cashier handover or bank settlement. '
                    'Account ledger lines are separate accounting evidence; do not add the two views together.'),
                if (onOpenCashControl != null || onOpenPersonLedger != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (onOpenCashControl != null)
                          OutlinedButton.icon(
                            onPressed: onOpenCashControl,
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('Open Cash Control'),
                          ),
                        if (onOpenPersonLedger != null)
                          OutlinedButton.icon(
                            onPressed: onOpenPersonLedger,
                            icon: const Icon(Icons.menu_book_outlined),
                            label: const Text('Open Person Ledger'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FinanceMetric(label: 'Cash booked · first 25', value: EmployeeFinanceReviewSnapshot.inr(snapshot.cashBookedPaise)),
            _FinanceMetric(label: 'UPI booked · first 25', value: EmployeeFinanceReviewSnapshot.inr(snapshot.upiBookedPaise)),
            _FinanceMetric(label: 'Journal mismatches · first 25', value: snapshot.mismatches.toString(), alert: snapshot.mismatches > 0),
            _FinanceMetric(label: 'Cash handovers unproven · first 25', value: snapshot.unprovenCash.toString(), alert: snapshot.unprovenCash > 0),
          ],
        ),
        if (snapshot.ledgerHasMore)
          Card(
            child: ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: const Text('More Person Ledger transactions exist'),
              subtitle: Text(
                'Only ${snapshot.ledgerEventPageCount} transaction events were loaded '
                'from page 1. Open Person Ledger for all remaining pages. '
                'Account balances below are separate full-history summaries.',
              ),
            ),
          ),
        if (snapshot.hasMore)
          const Card(
            child: ListTile(
              title: Text('More Daily Order records exist'),
              subtitle: Text('Totals cover page 1 only. Open Cash Control for the next pages.'),
              leading: Icon(Icons.info_outline),
            ),
          ),
        const Card(
          child: Column(children: [
            ListTile(
              title: Text('Cashier handover: NOT VERIFIED'),
              subtitle: Text('Legacy V7 has no independent employee-to-cashier Cash receipt proof.'),
              leading: Icon(Icons.receipt_long_outlined),
            ),
            Divider(height: 1),
            ListTile(
              title: Text('UPI bank settlement: NOT VERIFIED'),
              subtitle: Text('Booked UPI does not prove independent PSP/bank settlement.'),
              leading: Icon(Icons.account_balance_outlined),
            ),
            Divider(height: 1),
            ListTile(
              title: Text('Daily Orders / B2B linking: NOT VERIFIED'),
              subtitle: Text('No verified cross-source total, duplicate adjustment or employee shortage.'),
              leading: Icon(Icons.link_off_outlined),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Text('Daily Order journal checks', style: textTheme.titleMedium),
        if (snapshot.closings.isEmpty)
          const Card(child: ListTile(title: Text('No posted daily closings on this page.'))),
        for (final row in snapshot.closings)
          Card(
            child: ListTile(
              leading: Icon(
                row['journal_check'] == 'journal_amounts_match'
                    ? Icons.fact_check_outlined : Icons.warning_amber_rounded,
                color: row['journal_check'] == 'journal_amounts_match'
                    ? null : Theme.of(context).colorScheme.error,
              ),
              title: Text('Daily #' + row['daily_cycle_id'].toString() +
                  ' · ' + row['business_date'].toString()),
              subtitle: Text('Cash ' + EmployeeFinanceReviewSnapshot.inr(
                  EmployeeFinanceReviewSnapshot.unsigned(row['reported_cash_paise'])) +
                  ' · UPI ' + EmployeeFinanceReviewSnapshot.inr(
                  EmployeeFinanceReviewSnapshot.unsigned(row['reported_upi_paise'])) +
                  '\nJournal: ' + row['journal_check'].toString()),
            ),
          ),
        const SizedBox(height: 12),
        Text('Employee-tagged GL accounts', style: textTheme.titleMedium),
        const Text('Opening/closing Dr − Cr is not physical Cash on hand. '
            'These ledger amounts are never added to booked Daily Order amounts.'),
        if (snapshot.accounts.isEmpty)
          const Card(child: ListTile(title: Text('No employee-tagged GL accounts.'))),
        for (final account in snapshot.accounts.take(30))
          Card(
            child: ListTile(
              title: Text(account['account_code'].toString()),
              subtitle: Text('Opening ' + account['opening_debit_minus_credit'].toString() +
                  ' INR · Closing ' + account['closing_debit_minus_credit'].toString() + ' INR (Dr − Cr)'),
            ),
          ),
        if (snapshot.accounts.length > 30)
          const Text('More accounts exist: open Person Ledger for complete account balances.'),
      ],
    );
  }
}

class _FinanceMetric extends StatelessWidget {
  const _FinanceMetric({required this.label, required this.value, this.alert = false});
  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 5),
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: alert ? Theme.of(context).colorScheme.error : null)),
          ],
        ),
      ),
    ),
  );
}
