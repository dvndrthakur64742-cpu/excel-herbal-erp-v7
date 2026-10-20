import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/providers.dart';
import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';
import '../../widgets/module_workspace.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String type = 'sales';
  String reportingCategory = '';
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final available = _availableReports(app);
    if (available.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No authorised reports.')),
      );
    }

    final activeType = available.any((item) => item.id == type)
        ? type
        : available.first.id;
    final config = _config(activeType);
    final needsBranch = const {
      'sales',
      'purchase',
      'stock',
      'finance',
      'stock_reconciliation',
      'branch_daily',
      'branch_weekly',
      'branch_monthly',
    }.contains(activeType);

    const periodReports = {
      'sales',
      'purchase',
      'finance',
      'profit_loss',
      'price_distribution',
      'account_ledger',
    };
    const asOfReports = {'trial', 'balance_sheet'};
    const dayReports = {'branch_daily', 'branch_weekly', 'branch_monthly'};
    final defaultFrom = DateTime.tryParse(app.businessMonthStart) ??
        DateTime(DateTime.now().year, DateTime.now().month, 1);
    final defaultTo = DateTime.tryParse(app.businessDate) ?? DateTime.now();
    final fromDate = _fromDate ?? defaultFrom;
    final toDate = _toDate ?? defaultTo;
    final fromValue = _dateKey(fromDate);
    final toValue = _dateKey(toDate);
    final query = <String, dynamic>{
      if (app.currentBranchId != null) 'branch_id': app.currentBranchId,
      if (periodReports.contains(activeType)) 'from': fromValue,
      if (periodReports.contains(activeType)) 'to': toValue,
      if (asOfReports.contains(activeType)) 'to': app.businessDate,
      if (dayReports.contains(activeType)) 'date': toValue,
      if (activeType == 'branch_weekly' || activeType == 'branch_monthly')
        'mode': activeType == 'branch_weekly' ? 'week' : 'month',
      if (activeType == 'price_distribution' && reportingCategory.isNotEmpty)
        'reporting_category': reportingCategory,
    };
    final baseScopeLabel = dayReports.contains(activeType)
        ? BusinessFormat.date(toValue)
        : activeType == 'stock'
        ? 'Live stock'
        : activeType == 'stock_reconciliation'
            ? 'Live stock reconciliation'
            : const {'receivables', 'payables', 'finance_reconciliation'}
                    .contains(activeType)
                ? 'Current position'
                : asOfReports.contains(activeType)
                    ? BusinessFormat.date(app.businessDate)
                    : '${BusinessFormat.date(fromValue)} – ${BusinessFormat.date(toValue)}';
    final scopeLabel = app.currentBranchId == null
        ? baseScopeLabel
        : '$baseScopeLabel · Branch ${app.currentBranchId}';

    final reportView = activeType == 'account_ledger'
        ? _AccountLedgerPanel(
            api: api,
            query: query,
            config: config,
            scope: scopeLabel,
          )
        : needsBranch && app.currentBranchId == null
            ? const _BranchRequired()
            : AsyncPanel(
                key: ValueKey(
                  '$activeType-${app.currentBranchId}-$fromValue-$toValue-$reportingCategory',
                ),
                future: api.get(config.path, query: query),
                emptyMessage: config.emptyMessage,
                builder: (context, data) {
                  if (activeType == 'branch_weekly' || activeType == 'branch_monthly') {
                    return _BranchPeriodControlPanel(data: data);
                  }
                  if (activeType == 'branch_daily') {
                    return _BranchDailyControlPanel(data: data);
                  }
                  if (activeType == 'price_distribution') {
                    return _PriceDistributionPanel(
                      data: data,
                      reportingCategory: reportingCategory,
                      onReportingCategoryChanged: (value) =>
                          setState(() => reportingCategory = value),
                    );
                  }
                  final rows = ((data as List?) ?? const [])
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .toList();
                  return Column(
                    children: [
                      _ReportExportActions(
                        title: config.title,
                        scope: scopeLabel,
                        rows: rows,
                      ),
                      Expanded(
                        child: RecordsList(
                          recordType: config.recordType,
                          rows: rows,
                        ),
                      ),
                    ],
                  );
                },
              );

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: ModuleWorkspaceHeader(
                title: 'Reports Centre',
                subtitle:
                    'Only reports allowed by your current capabilities are shown.',
                icon: Icons.analytics_outlined,
                contextLabel: scopeLabel,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: BranchSelector(allowAllAuthorised: !needsBranch),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final content = Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 7),
                        child: ModuleSectionHeader(
                          title: config.title,
                          subtitle: config.subtitle,
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              scopeLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                      if (dayReports.contains(activeType))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.today_outlined),
                            label: Text('Business date: ${BusinessFormat.date(toValue)}'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: toDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                                helpText: 'Branch daily reporting date',
                              );
                              if (picked != null && mounted) {
                                setState(() => _toDate = picked);
                              }
                            },
                          ),
                        ),
                      if (periodReports.contains(activeType))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.calendar_month_outlined),
                                label: Text('From ${BusinessFormat.date(fromValue)}'),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: fromDate,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                    helpText: 'Report start date',
                                  );
                                  if (picked == null || !mounted) return;
                                  if (picked.isAfter(toDate)) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('From date cannot be after To date.'),
                                      ),
                                    );
                                    return;
                                  }
                                  setState(() => _fromDate = picked);
                                },
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.event_outlined),
                                label: Text('To ${BusinessFormat.date(toValue)}'),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: toDate,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                    helpText: 'Report end date',
                                  );
                                  if (picked == null || !mounted) return;
                                  if (picked.isBefore(fromDate)) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('To date cannot be before From date.'),
                                      ),
                                    );
                                    return;
                                  }
                                  setState(() => _toDate = picked);
                                },
                              ),
                              TextButton.icon(
                                onPressed: () => setState(() {
                                  _fromDate = null;
                                  _toDate = null;
                                }),
                                icon: const Icon(Icons.restart_alt),
                                label: const Text('Reset'),
                              ),
                            ],
                          ),
                        ),
                      Expanded(child: reportView),
                    ],
                  );
                  if (constraints.maxWidth >= 900) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            child: SizedBox(
                              width: 220,
                              child: _reportRail(available, activeType),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: content),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      const SizedBox(height: 8),
                      _mobileReportSelector(available, activeType),
                      Expanded(child: content),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_ReportOption> _availableReports(AppState app) {
    final out = <_ReportOption>[];
    if (app.can('reports.view')) {
      out.addAll(const [
        _ReportOption('sales', 'Sales Summary', Icons.point_of_sale_outlined),
        _ReportOption('branch_daily', 'Branch Daily Control', Icons.assignment_turned_in_outlined),
        _ReportOption('branch_weekly', 'Branch Weekly Performance', Icons.date_range_outlined),
        _ReportOption('branch_monthly', 'Branch Monthly Performance', Icons.calendar_month_outlined),
        _ReportOption(
          'price_distribution',
          'Price Distribution',
          Icons.account_tree_outlined,
        ),
        _ReportOption(
          'purchase',
          'Purchase Summary',
          Icons.local_shipping_outlined,
        ),
        _ReportOption('stock', 'Stock Position', Icons.inventory_2_outlined),
        _ReportOption(
          'finance',
          'Finance Movement',
          Icons.account_balance_outlined,
        ),
        _ReportOption(
          'stock_reconciliation',
          'Stock Reconciliation',
          Icons.fact_check_outlined,
        ),
      ]);
    }
    if (app.can('finance.accounting.view')) {
      out.addAll(const [
        _ReportOption('trial', 'Trial Balance', Icons.balance_outlined),
        _ReportOption(
          'account_ledger',
          'Account Ledger',
          Icons.menu_book_outlined,
        ),
        _ReportOption('profit_loss', 'Profit & Loss', Icons.trending_up),
        _ReportOption(
          'balance_sheet',
          'Balance Sheet',
          Icons.account_balance_wallet_outlined,
        ),
        _ReportOption(
          'receivables',
          'Receivables',
          Icons.receipt_long_outlined,
        ),
        _ReportOption(
          'payables',
          'Payables',
          Icons.payments_outlined,
        ),
        _ReportOption(
          'finance_reconciliation',
          'Finance Reconciliation',
          Icons.rule_folder_outlined,
        ),
      ]);
    }
    return out;
  }

  Widget _mobileReportSelector(
    List<_ReportOption> available,
    String activeType,
  ) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          menuMaxHeight: 420,
          initialValue: activeType,
          decoration: const InputDecoration(
            labelText: 'Report view',
            prefixIcon: Icon(Icons.analytics_outlined, size: 20),
            isDense: true,
          ),
          items: [
            for (final item in available)
              DropdownMenuItem(value: item.id, child: Text(item.label)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => type = value);
          },
        ),
      );

  Widget _reportRail(List<_ReportOption> available, String activeType) {
    final selected = available.indexWhere((item) => item.id == activeType);
    return NavigationRail(
      selectedIndex: selected < 0 ? 0 : selected,
      extended: true,
      minExtendedWidth: 220,
      backgroundColor: Colors.transparent,
      onDestinationSelected: (index) =>
          setState(() => type = available[index].id),
      destinations: [
        for (final item in available)
          NavigationRailDestination(
            icon: Icon(item.icon),
            label: Text(item.label),
          ),
      ],
    );
  }

  _ReportConfig _config(String value) => switch (value) {
        'branch_weekly' => const _ReportConfig(
            title: 'Branch Weekly Performance',
            path: ApiPaths.branchPeriodControl,
            recordType: 'branch_period',
            subtitle: 'ISO Monday–Sunday, previous week comparison; posted sales, points, stock and pending closing.',
            emptyMessage: 'No weekly business activity for this branch.',
          ),
        'branch_monthly' => const _ReportConfig(
            title: 'Branch Monthly Performance',
            path: ApiPaths.branchPeriodControl,
            recordType: 'branch_period',
            subtitle: 'Calendar month, previous month comparison; employee activity and finance-only tagged Cash-in-Transit.',
            emptyMessage: 'No monthly business activity for this branch.',
          ),
        'branch_daily' => const _ReportConfig(
            title: 'Branch Daily Control',
            path: ApiPaths.branchDailyControl,
            recordType: 'branch_daily',
            subtitle: 'Posted Daily Orders, stock custody, points and pending approvals; Counter Sales separate.',
            emptyMessage: 'No branch activity on the selected business date.',
          ),
        'price_distribution' => const _ReportConfig(
            title: 'Price Distribution',
            path: ApiPaths.priceDistribution,
            recordType: 'price_distribution',
            subtitle:
                'Final posted sale distribution inside reporting hierarchy and branch authority.',
            emptyMessage: 'No posted distribution data for the selected period.',
          ),
        'purchase' => const _ReportConfig(
            title: 'Purchase Summary',
            path: ApiPaths.reportsPurchase,
            recordType: 'purchase',
            subtitle: 'Supplier billing, payments and outstanding summary.',
            emptyMessage: 'No purchase activity for the selected period.',
          ),
        'stock' => const _ReportConfig(
            title: 'Stock Position',
            path: ApiPaths.reportsStock,
            recordType: 'stock',
            subtitle: 'Current stock position for the selected branch.',
            emptyMessage: 'No stock records for the selected branch.',
          ),
        'finance' => const _ReportConfig(
            title: 'Finance Movement',
            path: ApiPaths.reportsFinance,
            recordType: 'finance',
            subtitle: 'Posted journals and accounting movement summary.',
            emptyMessage: 'No finance activity for the selected period.',
          ),
        'stock_reconciliation' => const _ReportConfig(
            title: 'Stock Reconciliation',
            path: ApiPaths.stockReconciliation,
            recordType: 'stock_reconciliation',
            subtitle:
                'Compare current stock balances with the movement ledger; mismatches are highlighted.',
            emptyMessage: 'No stock balance or ledger records for this branch.',
          ),
        'finance_reconciliation' => const _ReportConfig(
            title: 'Finance Reconciliation',
            path: ApiPaths.financeReconciliation,
            recordType: 'finance_reconciliation',
            subtitle:
                'Compare Accounts Receivable, Accounts Payable, inventory value and journal balance controls.',
            emptyMessage: 'No finance reconciliation checks are available.',
          ),
        'receivables' => const _ReportConfig(
            title: 'Receivables',
            path: ApiPaths.receivables,
            recordType: 'receivables',
            subtitle: 'Posted customer balances still outstanding, with ageing.',
            emptyMessage: 'No outstanding customer balances.',
          ),
        'payables' => const _ReportConfig(
            title: 'Payables',
            path: ApiPaths.payables,
            recordType: 'payables',
            subtitle: 'Posted supplier balances still outstanding, with ageing.',
            emptyMessage: 'No outstanding supplier balances.',
          ),
        'profit_loss' => const _ReportConfig(
            title: 'Profit & Loss',
            path: ApiPaths.profitLoss,
            recordType: 'profit_loss',
            subtitle: 'Income and expenses for the selected business period.',
            emptyMessage: 'No income or expense activity for this period.',
          ),
        'balance_sheet' => const _ReportConfig(
            title: 'Balance Sheet',
            path: ApiPaths.balanceSheet,
            recordType: 'balance_sheet',
            subtitle: 'Assets, liabilities and equity as of the business date.',
            emptyMessage: 'No balance sheet balances are available.',
          ),
        'trial' => const _ReportConfig(
            title: 'Trial Balance',
            path: ApiPaths.trialBalance,
            recordType: 'trial_balance',
            subtitle:
                'Ledger debit and credit balances as of the business date.',
            emptyMessage: 'No Trial Balance data is available.',
          ),
        'account_ledger' => const _ReportConfig(
            title: 'Account Ledger',
            path: ApiPaths.accountLedger,
            recordType: 'account_ledger',
            subtitle:
                'Posted journal entries for one account, with optional branch scope.',
            emptyMessage: 'No journal entries for this account and period.',
          ),
        _ => const _ReportConfig(
            title: 'Sales Summary',
            path: ApiPaths.reportsSales,
            recordType: 'sales',
            subtitle:
                'Counter Sales + posted Daily Orders, collections and outstanding (without double count).',
            emptyMessage: 'No sales activity for the selected period.',
          ),
      };
}

class _ReportOption {
  const _ReportOption(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}



class _BranchPeriodControlPanel extends StatelessWidget {
  const _BranchPeriodControlPanel({required this.data});
  final dynamic data;

  @override
  Widget build(BuildContext context) {
    if (data is! Map) {
      return const Center(child: Text('Branch performance response invalid.'));
    }
    final report = Map<String, dynamic>.from(data as Map);
    final coverage = report['coverage'];
    if (report['read_only'] != true ||
        report['scope'] != 'single_authorized_branch_canonical_v7' ||
        coverage is! Map ||
        coverage['cashier_handover_verified'] != false ||
        coverage['upi_bank_verified'] != false ||
        coverage['counter_sales_separate_from_daily_orders'] != true ||
        !const {'week', 'month'}.contains(report['mode'])) {
      return const Center(child: Text('Branch performance authority/verification contract mismatch.'));
    }
    final totals = Map<String, dynamic>.from((report['totals'] as Map?) ?? const {});
    final prior = (report['previous_period'] as Map?) ?? const {};
    final previous = Map<String, dynamic>.from((prior['totals'] as Map?) ?? const {});
    final period = Map<String, dynamic>.from((report['period'] as Map?) ?? const {});
    final employees = ((report['employees'] as List?) ?? const [])
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    final financeVisible = report['financial_visibility'] == 'accounting_role_only';
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 26),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Period: ${period['from']} – ${period['to']}. '
              'Previous full period shown for comparison. '
              'Cash/UPI are allocations, NOT bank/cashier verified. '
              'Cash-in-Transit is employee-tagged GL, not physical cash count.',
            ),
          ),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _MetricCard(label: 'Posted Daily Sales', value: BusinessFormat.money(totals['posted_daily_order_sales'])),
          _MetricCard(label: 'Previous Period Sales', value: BusinessFormat.money(previous['posted_daily_order_sales'])),
          _MetricCard(label: 'Sales Change (INR)', value: '${report['posted_daily_order_sales_delta']}'),
          _MetricCard(label: 'Cash Allocations', value: BusinessFormat.money(totals['daily_cash_allocations'])),
          _MetricCard(label: 'UPI Allocations', value: BusinessFormat.money(totals['daily_upi_allocations'])),
          _MetricCard(label: 'Counter Sales (separate)', value: BusinessFormat.money(totals['counter_sales_gross'])),
          _MetricCard(label: 'Issued PCS', value: BusinessFormat.quantity(totals['issued_quantity'])),
          _MetricCard(label: 'Sold PCS', value: BusinessFormat.quantity(totals['sold_quantity'])),
          _MetricCard(label: 'Returned PCS', value: BusinessFormat.quantity(totals['returned_quantity'])),
          _MetricCard(label: 'Points', value: BusinessFormat.quantity(totals['performance_points'])),
          _MetricCard(label: 'Pending Closings', value: '${totals['pending_daily_orders'] ?? 0}'),
          _MetricCard(label: 'Pending Requests', value: '${totals['pending_stock_requests'] ?? 0}'),
          _MetricCard(label: 'Needs Attention', value: '${totals['employees_needing_attention'] ?? 0}'),
        ]),
        const SizedBox(height: 12),
        Text('Employee-wise Weekly / Monthly Performance',
            style: Theme.of(context).textTheme.titleMedium),
        if (employees.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No posted or pending employee activity in this period.'),
          ),
        for (final employee in employees)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${employee['employee_name']} · #${employee['employee_id']}',
                      style: Theme.of(context).textTheme.titleSmall),
                  Text('Posted sales ${BusinessFormat.money(employee['posted_daily_order_sales'])} '
                      '· Points ${employee['performance_points']}'),
                  Text('Cash ${BusinessFormat.money(employee['daily_cash_allocations'])} '
                      '· UPI ${BusinessFormat.money(employee['daily_upi_allocations'])}'),
                  Text('Issue ${employee['issued_quantity']} / Sold ${employee['sold_quantity']} '
                      '/ Return ${employee['returned_quantity']} PCS'),
                  Text('Custody IN ${employee['custody_in_quantity']} / '
                      'OUT ${employee['custody_out_quantity']} PCS'),
                  Text('Posted days ${employee['posted_days']} · '
                      'Pending closing ${employee['pending_days']} · '
                      'Pending stock requests ${employee['pending_requests']}'),
                  if (employee['needs_attention'] == true)
                    Text('Attention: unresolved stock/sale/closing exception',
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  if (financeVisible && employee['tagged_cash_in_transit'] is Map)
                    Text(
                      'Finance-only tagged Cash-in-Transit INR '
                      '${(employee['tagged_cash_in_transit'] as Map)['closing_debit_minus_credit']} '
                      '(unverified physical receipt)',
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _BranchDailyControlPanel extends StatelessWidget {
  const _BranchDailyControlPanel({required this.data});
  final dynamic data;

  @override
  Widget build(BuildContext context) {
    if (data is! Map) {
      return const Center(child: Text('Branch daily report response is invalid.'));
    }
    final report = Map<String, dynamic>.from(data as Map);
    if (report['read_only'] != true ||
        report['scope'] != 'single_authorized_branch_canonical_v7' ||
        report['coverage'] is! Map ||
        (report['coverage'] as Map)['cashier_handover_verified'] != false ||
        (report['coverage'] as Map)['upi_bank_verified'] != false) {
      return const Center(child: Text('Branch daily reporting security contract mismatch.'));
    }
    final totals = Map<String, dynamic>.from((report['totals'] as Map?) ?? const {});
    final employees = ((report['employees'] as List?) ?? const [])
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Only posted Daily Orders are counted as employee sales. '
              'Counter Sales are separate. Cash/UPI allocations are NOT '
              'verified branch cash deposits or bank reconciliation.',
            ),
          ),
        ),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            _MetricCard(label: 'Daily Order Sales', value: BusinessFormat.money(totals['posted_daily_order_sales'])),
            _MetricCard(label: 'Cash Split', value: BusinessFormat.money(totals['daily_cash_split'])),
            _MetricCard(label: 'UPI Split', value: BusinessFormat.money(totals['daily_upi_split'])),
            _MetricCard(label: 'Counter Sales (separate)', value: BusinessFormat.money(totals['counter_sales_gross'])),
            _MetricCard(label: 'Issued PCS', value: BusinessFormat.quantity(totals['issued_quantity'])),
            _MetricCard(label: 'Sold PCS', value: BusinessFormat.quantity(totals['sold_quantity'])),
            _MetricCard(label: 'Returned PCS', value: BusinessFormat.quantity(totals['returned_quantity'])),
            _MetricCard(label: 'Points', value: BusinessFormat.quantity(totals['performance_points'])),
            _MetricCard(label: 'Pending Requests', value: '${totals['pending_requests'] ?? 0}'),
            _MetricCard(label: 'Needs Attention', value: '${totals['employees_needing_attention'] ?? 0}'),
          ],
        ),
        const SizedBox(height: 12),
        Text('Employee Daily Activity & Exceptions',
            style: Theme.of(context).textTheme.titleMedium),
        if (employees.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No Daily Order, custody or performance events for this branch/day.'),
          ),
        for (final employee in employees)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${employee['employee_name']} · #${employee['employee_id']}',
                      style: Theme.of(context).textTheme.titleSmall),
                  Text('Daily Order: ${employee['cycle_status']} · Evening: ${employee['settlement_status']}'),
                  Text('Posted sale: ${BusinessFormat.money(employee['posted_sale_amount'])} '
                      '· Cash ${BusinessFormat.money(employee['posted_cash_split'])} '
                      '· UPI ${BusinessFormat.money(employee['posted_upi_split'])}'),
                  Text('Issued ${employee['issued_quantity']} / Sold ${employee['sold_quantity']} '
                      '/ Returned ${employee['returned_quantity']} PCS'),
                  Text('Custody IN ${employee['custody_in_quantity']} / '
                      'OUT ${employee['custody_out_quantity']} PCS '
                      '· Points ${employee['performance_points']}'),
                  if ((employee['exceptions'] as List?)?.isNotEmpty == true)
                    Text('Attention: ${(employee['exceptions'] as List).join(', ')}',
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PriceDistributionPanel extends StatelessWidget {
  const _PriceDistributionPanel({
    required this.data,
    required this.reportingCategory,
    required this.onReportingCategoryChanged,
  });

  final dynamic data;
  final String reportingCategory;
  final ValueChanged<String> onReportingCategoryChanged;

  static const fields = [
    ('sale_price', 'Sale Price'),
    ('ho_amount', 'HO Amount'),
    ('bm_profit', 'BM Profit'),
    ('salary_fund', 'Salary Fund'),
    ('expense', 'Expense'),
    ('points', 'Points'),
  ];

  @override
  Widget build(BuildContext context) {
    final map = data is Map
        ? Map<String, dynamic>.from(data as Map)
        : <String, dynamic>{};
    final rows = ((map['rows'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    final totals = Map<String, dynamic>.from(
      (map['totals'] as Map?) ?? const {},
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: reportingCategory,
          decoration: const InputDecoration(
            labelText: 'Reporting category',
            prefixIcon: Icon(Icons.account_tree_outlined),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: '', child: Text('All visible employees')),
            DropdownMenuItem(
              value: 'FIELD_EXECUTIVE',
              child: Text('Field Executive'),
            ),
            DropdownMenuItem(value: 'ASM', child: Text('ASM')),
            DropdownMenuItem(value: 'SM', child: Text('SM')),
            DropdownMenuItem(
              value: 'BRANCH_MANAGER',
              child: Text('Branch Manager'),
            ),
            DropdownMenuItem(value: 'REGIONAL', child: Text('Regional')),
            DropdownMenuItem(
              value: 'SENIOR_MANAGEMENT',
              child: Text('Senior Management'),
            ),
            DropdownMenuItem(
              value: 'SYSTEM_ADMIN',
              child: Text('System Admin'),
            ),
          ],
          onChanged: (value) => onReportingCategoryChanged(value ?? ''),
        ),
        const SizedBox(height: 10),
        Text(
          'Reporting category filters rows only. It never expands employee or branch authority.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: ExcelBrand.muted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final field in fields)
              _MetricCard(
                label: field.$2,
                value: field.$1 == 'points'
                    ? BusinessFormat.quantity(totals[field.$1])
                    : BusinessFormat.money(totals[field.$1]),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No posted distribution data for this scope.'),
              ),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Employee')),
                  DataColumn(label: Text('Reporting')),
                  DataColumn(label: Text('Sale Days'), numeric: true),
                  DataColumn(label: Text('Sale Price'), numeric: true),
                  DataColumn(label: Text('HO Amount'), numeric: true),
                  DataColumn(label: Text('BM Profit'), numeric: true),
                  DataColumn(label: Text('Salary Fund'), numeric: true),
                  DataColumn(label: Text('Expense'), numeric: true),
                  DataColumn(label: Text('Points'), numeric: true),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        DataCell(
                          Text(
                            '${row['full_name'] ?? '—'}\n${row['employee_code'] ?? ''}',
                          ),
                        ),
                        DataCell(
                          Text(BusinessFormat.status(row['reporting_category'])),
                        ),
                        DataCell(Text('${row['sale_days'] ?? 0}')),
                        DataCell(Text(BusinessFormat.money(row['sale_price']))),
                        DataCell(Text(BusinessFormat.money(row['ho_amount']))),
                        DataCell(Text(BusinessFormat.money(row['bm_profit']))),
                        DataCell(Text(BusinessFormat.money(row['salary_fund']))),
                        DataCell(Text(BusinessFormat.money(row['expense']))),
                        DataCell(Text(BusinessFormat.quantity(row['points']))),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
}

class _ReportConfig {
  const _ReportConfig({
    required this.title,
    required this.path,
    required this.recordType,
    required this.subtitle,
    required this.emptyMessage,
  });

  final String title;
  final String path;
  final String recordType;
  final String subtitle;
  final String emptyMessage;
}

class _BranchRequired extends StatelessWidget {
  const _BranchRequired();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: ExcelBrand.primarySoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.store_outlined,
                  color: ExcelBrand.primaryDark,
                  size: 30,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Select an authorised branch',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 5),
              Text(
                'Reports are scoped to the selected authorised branch.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}

class _AccountLedgerPanel extends StatefulWidget {
  const _AccountLedgerPanel({
    required this.api,
    required this.query,
    required this.config,
    required this.scope,
  });

  final dynamic api;
  final Map<String, dynamic> query;
  final _ReportConfig config;
  final String scope;

  @override
  State<_AccountLedgerPanel> createState() => _AccountLedgerPanelState();
}

class _AccountLedgerPanelState extends State<_AccountLedgerPanel> {
  int? _accountId;

  @override
  Widget build(BuildContext context) => AsyncPanel(
        key: const ValueKey('account-ledger-account-list'),
        future: widget.api.get(ApiPaths.financeBootstrap),
        emptyMessage: 'No active ledger accounts are available.',
        builder: (context, data) {
          final payload = data is Map
              ? Map<String, dynamic>.from(data)
              : <String, dynamic>{};
          final accounts = ((payload['accounts'] as List?) ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .where((row) => int.tryParse('${row['id']}') != null)
              .toList(growable: false);
          if (accounts.isEmpty) {
            return const Center(child: Text('No active ledger accounts are available.'));
          }

          final firstId = int.tryParse('${accounts.first['id']}');
          final selectedId = accounts.any(
            (row) => int.tryParse('${row['id']}') == _accountId,
          )
              ? _accountId
              : firstId;
          final selected = accounts.firstWhere(
            (row) => int.tryParse('${row['id']}') == selectedId,
            orElse: () => accounts.first,
          );
          final ledgerQuery = <String, dynamic>{
            ...widget.query,
            if (selectedId != null) 'account_id': selectedId,
          };
          final accountLabel =
              '${selected['code'] ?? ''} — ${selected['name'] ?? 'Account'}';
          final scope = '${widget.scope} · $accountLabel';

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: selectedId,
                  decoration: const InputDecoration(
                    labelText: 'Ledger account',
                    prefixIcon: Icon(Icons.menu_book_outlined),
                    isDense: true,
                  ),
                  items: [
                    for (final account in accounts)
                      DropdownMenuItem<int>(
                        value: int.tryParse('${account['id']}'),
                        child: Text(
                          '${account['code'] ?? ''} — ${account['name'] ?? 'Account'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _accountId = value),
                ),
              ),
              Expanded(
                child: selectedId == null
                    ? const Center(child: Text('Select a ledger account.'))
                    : AsyncPanel(
                        key: ValueKey(
                          'account-ledger-$selectedId-${ledgerQuery['from']}-${ledgerQuery['to']}-${ledgerQuery['branch_id']}',
                        ),
                        future: widget.api.get(
                          ApiPaths.accountLedger,
                          query: ledgerQuery,
                        ),
                        emptyMessage: widget.config.emptyMessage,
                        builder: (context, data) {
                          final rows = ((data as List?) ?? const [])
                              .whereType<Map>()
                              .map((row) => Map<String, dynamic>.from(row))
                              .toList(growable: false);
                          return Column(
                            children: [
                              _ReportExportActions(
                                title: widget.config.title,
                                scope: scope,
                                rows: rows,
                              ),
                              Expanded(
                                child: RecordsList(
                                  recordType: widget.config.recordType,
                                  rows: rows,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      );
}

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class _ReportExportActions extends StatelessWidget {
  const _ReportExportActions({
    required this.title,
    required this.scope,
    required this.rows,
  });

  final String title;
  final String scope;
  final List<Map<String, dynamic>> rows;

  List<String> get _columns {
    final result = <String>[];
    for (final row in rows) {
      for (final key in row.keys) {
        if (!result.contains(key)) result.add(key);
      }
    }
    return result;
  }

  String _safeFilename(String extension) {
    final slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '${slug.isEmpty ? 'report' : slug}.$extension';
  }

  String _cellText(dynamic value) => value == null ? '' : value is Map || value is List
      ? jsonEncode(value)
      : value.toString();

  String _csvCell(dynamic value) {
    var text = _cellText(value);
    if (value is String && RegExp(r'^[\u0000-\u0020]*[=+\-@]').hasMatch(text)) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }

  Future<void> _shareCsv() async {
    final columns = _columns;
    final lines = <String>[
      '"Report",${_csvCell(title)}',
      '"Scope",${_csvCell(scope)}',
      '',
      columns.map(_csvCell).join(','),
      for (final row in rows) columns.map((key) => _csvCell(row[key])).join(','),
    ];
    final bytes = Uint8List.fromList(utf8.encode(lines.join('\r\n')));
    await Share.shareXFiles(
      [XFile.fromData(bytes, name: _safeFilename('csv'), mimeType: 'text/csv')],
      text: '$title report',
    );
  }

  Future<void> _shareExcel() async {
    final workbook = Excel.createExcel();
    final sheet = workbook['Report'];
    sheet.appendRow([TextCellValue(title)]);
    sheet.appendRow([TextCellValue('Scope: $scope')]);
    sheet.appendRow(_columns.map((key) => TextCellValue(key)).toList());
    for (final row in rows) {
      sheet.appendRow(
        _columns.map((key) => TextCellValue(_cellText(row[key]))).toList(),
      );
    }
    final encoded = workbook.encode();
    if (encoded == null) return;
    await Share.shareXFiles([
      XFile.fromData(
        Uint8List.fromList(encoded),
        name: _safeFilename('xlsx'),
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
    ], text: '$title report');
  }

  Future<void> _printPdf() async {
    final columns = _columns;
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(scope, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 12),
          if (columns.isEmpty)
            pw.Text('No report rows')
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
              children: [
                pw.TableRow(
                  repeat: true,
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    for (final column in columns)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(3),
                        child: pw.Text(column, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                      ),
                  ],
                ),
                for (final row in rows)
                  pw.TableRow(
                    children: [
                      for (final column in columns)
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(3),
                          child: pw.Text(_cellText(row[column]), style: const pw.TextStyle(fontSize: 7)),
                        ),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => document.save());
  }

  @override
  Widget build(BuildContext context) {
    if (rows.length > 10000) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Export is disabled above 10,000 rows. Narrow the report date range.'),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          TextButton.icon(
            onPressed: rows.isEmpty ? null : _shareCsv,
            icon: const Icon(Icons.table_view_outlined, size: 18),
            label: const Text('CSV'),
          ),
          TextButton.icon(
            onPressed: rows.isEmpty ? null : _shareExcel,
            icon: const Icon(Icons.grid_on_outlined, size: 18),
            label: const Text('Excel'),
          ),
          TextButton.icon(
            onPressed: rows.isEmpty ? null : _printPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('PDF / Print'),
          ),
          Text('${rows.length} rows', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
