import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';
import '../../widgets/module_workspace.dart';
import 'report_review_queue.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String type = 'sales';
  String reportingCategory = '';
  int _reloadTick = 0;
  bool _reviewBusy = false;
  String? _feedback;

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
    }.contains(activeType);

    const periodReports = {
      'sales',
      'purchase',
      'finance',
      'profit_loss',
      'price_distribution',
    };
    const asOfReports = {'trial', 'balance_sheet'};
    final query = <String, dynamic>{
      if (activeType != 'accounts_review' && app.currentBranchId != null)
        'branch_id': app.currentBranchId,
      if (activeType == 'accounts_review') 'status': 'all',
      if (periodReports.contains(activeType)) 'from': app.businessMonthStart,
      if (periodReports.contains(activeType) || asOfReports.contains(activeType))
        'to': app.businessDate,
      if (activeType == 'price_distribution' && reportingCategory.isNotEmpty)
        'reporting_category': reportingCategory,
    };
    final scopeLabel = activeType == 'accounts_review'
        ? 'Accounts review queue'
        : activeType == 'stock'
        ? 'Live stock'
        : activeType == 'stock_reconciliation'
            ? 'Live stock reconciliation'
            : const {'receivables', 'payables', 'finance_reconciliation'}
                    .contains(activeType)
                ? 'Current position'
                : asOfReports.contains(activeType)
                    ? BusinessFormat.date(app.businessDate)
                    : '${BusinessFormat.date(app.businessMonthStart)} – ${BusinessFormat.date(app.businessDate)}';

    final reportView = needsBranch && app.currentBranchId == null
        ? const _BranchRequired()
        : AsyncPanel(
            key: ValueKey(
              '$activeType-${app.currentBranchId}-${app.businessDate}-$reportingCategory-$_reloadTick',
            ),
            future: api.get(config.path, query: query),
            emptyMessage: config.emptyMessage,
            builder: (context, data) {
              if (activeType == 'accounts_review') {
                return ReportReviewQueue(
                  rows: ((data as List?) ?? const [])
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .toList(),
                  busy: _reviewBusy,
                  onDecision: _decideReview,
                );
              }
              if (activeType == 'price_distribution') {
                return _PriceDistributionPanel(
                  data: data,
                  reportingCategory: reportingCategory,
                  onReportingCategoryChanged: (value) =>
                      setState(() => reportingCategory = value),
                );
              }
              return RecordsList(
                recordType: config.recordType,
                rows: ((data as List?) ?? const [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList(),
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
            if (_canSubmitReview(activeType, app))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    const Text(
                      'Submit a fixed report snapshot for independent Accounts review.',
                    ),
                    FilledButton.icon(
                      onPressed: _reviewBusy ||
                              (activeType == 'stock_reconciliation' &&
                                  app.currentBranchId == null)
                          ? null
                          : () => _submitReview(activeType, app),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Submit for Accounts Review'),
                    ),
                  ],
                ),
              ),
            if (_feedback != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _feedback!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
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

  bool _isReviewable(String value) => const {
        'trial',
        'profit_loss',
        'balance_sheet',
        'stock_reconciliation',
        'finance_reconciliation',
      }.contains(value);

  bool _canSubmitReview(String value, AppState app) {
    if (!_isReviewable(value) || value == 'accounts_review') return false;
    if (value == 'stock_reconciliation') return app.can('reports.view');
    return app.can('finance.accounting.view');
  }

  Future<void> _submitReview(String value, AppState app) async {
    final reportType = value == 'trial' ? 'trial_balance' : value;
    final body = <String, dynamic>{
      'report_type': reportType,
      if (app.currentBranchId != null) 'branch_id': app.currentBranchId,
      if (value == 'profit_loss') ...{
        'from': app.businessMonthStart,
        'to': app.businessDate,
      },
      if (value == 'trial' || value == 'balance_sheet')
        'as_of_date': app.businessDate,
    };
    setState(() {
      _reviewBusy = true;
      _feedback = null;
    });
    try {
      await ref.read(apiClientProvider).post(ApiPaths.reportReviews, data: body);
      if (!mounted) return;
      setState(() {
        _feedback =
            'Report snapshot submitted. It is not approved until a different authorised Accounts reviewer records a decision.';
        _reloadTick++;
        if (ref.read(appStateProvider).can('finance.report.review') &&
            ref.read(appStateProvider).can('finance.accounting.view')) {
          type = 'accounts_review';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _feedback = 'Could not submit review: ${UiError.message(e)}');
    } finally {
      if (mounted) setState(() => _reviewBusy = false);
    }
  }

  Future<void> _decideReview(int id, String decision, String reason) async {
    setState(() {
      _reviewBusy = true;
      _feedback = null;
    });
    try {
      final result = await ref.read(apiClientProvider).post(
        ApiPaths.reportReviewDecision(id),
        data: {'decision': decision, 'reason': reason},
      );
      final status = result is Map ? '${result['status'] ?? ''}' : '';
      if (!mounted) return;
      setState(() {
        _feedback = status == 'stale'
            ? 'Review stopped: report data changed after submission. Submit a fresh snapshot.'
            : status == 'approved'
                ? 'Accounts review approved and audit-recorded.'
                : status == 'rejected'
                    ? 'Accounts review rejected and audit-recorded.'
                    : 'Review status updated: $status';
        _reloadTick++;
      });
    } catch (e) {
      if (mounted) setState(() => _feedback = 'Review decision failed: ${UiError.message(e)}');
    } finally {
      if (mounted) setState(() => _reviewBusy = false);
    }
  }

  List<_ReportOption> _availableReports(AppState app) {
    final out = <_ReportOption>[];
    if (app.can('reports.view')) {
      out.addAll(const [
        _ReportOption('sales', 'Sales Summary', Icons.point_of_sale_outlined),
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
    if (app.can('finance.report.review') &&
        app.can('finance.accounting.view')) {
      out.add(
        const _ReportOption(
          'accounts_review',
          'Accounts Review',
          Icons.fact_check_outlined,
        ),
      );
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
        'accounts_review' => const _ReportConfig(
            title: 'Accounts Review',
            path: ApiPaths.reportReviews,
            recordType: 'report_review',
            subtitle:
                'Independent, auditable review of fixed Trial Balance, Profit & Loss, Balance Sheet and reconciliation snapshots.',
            emptyMessage: 'No Accounts review requests are available.',
          ),
        'trial' => const _ReportConfig(
            title: 'Trial Balance',
            path: ApiPaths.trialBalance,
            recordType: 'trial_balance',
            subtitle:
                'Ledger debit and credit balances as of the business date.',
            emptyMessage: 'No Trial Balance data is available.',
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