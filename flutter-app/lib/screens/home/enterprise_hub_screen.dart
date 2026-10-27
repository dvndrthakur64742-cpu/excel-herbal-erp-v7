import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../theme/excel_brand.dart';
import '../../core/business_format.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../common/record_detail_screen.dart';
import '../finance/finance_screen.dart';
import '../inventory/inventory_screen.dart';
import '../organization/team_screen.dart';
import '../performance/performance_screen.dart';

class EnterpriseHubScreen extends ConsumerStatefulWidget {
  const EnterpriseHubScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<EnterpriseHubScreen> createState() =>
      _EnterpriseHubScreenState();
}

class _EnterpriseHubScreenState extends ConsumerState<EnterpriseHubScreen> {
  int refresh = 0;
  String searchText = '';
  Future<_SearchResult>? searchFuture;
  String? message;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final approvalVisible = _approvalVisible(app);
    final tabs = <(String, Widget)>[];
    if (approvalVisible) {
      tabs.add(('Approvals', _approvalTab(app)));
    }
    tabs.add(('Global Search', _searchTab(app)));
    final requested = widget.initialTab.clamp(0, 1);
    final initial = approvalVisible ? requested.clamp(0, tabs.length - 1) : 0;

    return DefaultTabController(
      length: tabs.length,
      initialIndex: initial,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 70,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ACTION CENTER',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: ExcelBrand.primaryDark,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                )),
              const SizedBox(height: 3),
              Text('Approvals & search',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: ExcelBrand.ink, fontWeight: FontWeight.w900)),
            ],
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 19),
            tabs: [for (final tab in tabs) Tab(text: tab.$1)],
          ),
        ),
        body: Column(
          children: [
            if (message != null)
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.info_outline),
                  title: Text(message!),
                  trailing: IconButton(
                    onPressed: () => setState(() => message = null),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(children: [for (final tab in tabs) tab.$2]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _approvalTab(AppState app) {
    if (app.currentBranchId == null) {
      return const Center(child: Text('Branch select karein.'));
    }
    return FutureBuilder<_ApprovalResult>(
      key: ValueKey('approval-${app.currentBranchId}-$refresh'),
      future: _loadApprovals(app),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState(
            message: UiError.message(snapshot.error!),
            onRetry: _refresh,
          );
        }
        final result = snapshot.data ?? const _ApprovalResult([], []);
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: _ApprovalHeader(
                    count: result.items.length,
                    warnings: result.errors.length,
                  ),
                ),
              ),
              if (result.errors.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Some optional approval sources could not be loaded (${result.errors.length}). Other authorised approvals are still shown.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                ),
              if (result.items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('No pending approvals.')),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: result.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, index) => _ApprovalCard(
                      item: result.items[index],
                      onAction: _approvalAction,
                      onOpen: _openApprovalSource,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _searchTab(AppState app) {
    final controller = TextEditingController(text: searchText);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 850;
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                desktop ? 24 : 16,
                18,
                desktop ? 24 : 16,
                12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Global ERP Search',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Search only across records allowed by your designation, permissions and current branch authority.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Employee, product, supplier, bill, order, amount...',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (value) => _runSearch(value, app),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () => _runSearch(controller.text, app),
                        icon: const Icon(Icons.search),
                        label: Text(desktop ? 'Search ERP' : 'Search'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: searchFuture == null
                  ? const _SearchHelp()
                  : FutureBuilder<_SearchResult>(
                      future: searchFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return _ErrorState(
                            message: UiError.message(snapshot.error!),
                            onRetry: () => _runSearch(searchText, app),
                          );
                        }
                        final result =
                            snapshot.data ?? const _SearchResult([], []);
                        if (result.hits.isEmpty) {
                          return const Center(
                            child: Text(
                              'No matching authorised records found.',
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            desktop ? 24 : 16,
                            4,
                            desktop ? 24 : 16,
                            24,
                          ),
                          itemCount: result.hits.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _SearchHitCard(
                            hit: result.hits[i],
                            onTap: () => _openSearchHit(result.hits[i]),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<_ApprovalResult> _loadApprovals(AppState app) async {
    final api = ref.read(apiClientProvider);
    final branch = app.currentBranchId!;
    final items = <_ApprovalItem>[];
    final errors = <String>[];

    Future<List<Map<String, dynamic>>> list(
      String path, {
      Map<String, dynamic>? query,
    }) async {
      try {
        final raw = await api.get(path, query: query);
        return ((raw as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (e) {
        errors.add('$path: $e');
        return const [];
      }
    }

    if (app.canAny(const [
      'daily_order.approve',
      'daily_order.issue',
      'daily_order.review',
      'daily_order.others',
    ])) {
      final rows = await list(
        ApiPaths.dailyCycles,
        query: {'branch_id': branch},
      );
      for (final row in rows) {
        final requestStatus = '${row['initial_request_status'] ?? ''}'
            .toLowerCase();
        if (requestStatus == 'submitted' && app.can('daily_order.approve')) {
          items.add(
            _ApprovalItem(
              kind: 'daily',
              title: 'Daily Order Approval',
              subtitle:
                  '${row['employee_name'] ?? 'Employee'} · ${BusinessFormat.date(row['business_date'])}',
              status: 'Approval Pending',
              row: row,
              primaryAction: 'Approve',
              actionId: int.tryParse('${row['initial_request_id']}'),
              sortKey: '${row['business_date'] ?? ''}',
            ),
          );
        } else if (requestStatus == 'approved' &&
            app.can('daily_order.issue')) {
          items.add(
            _ApprovalItem(
              kind: 'daily_issue',
              title: 'Daily Order Stock Issue',
              subtitle:
                  '${row['employee_name'] ?? 'Employee'} · ${BusinessFormat.date(row['business_date'])}',
              status: 'Approved · Issue Pending',
              row: row,
              primaryAction: 'Open Team',
              sortKey: '${row['business_date'] ?? ''}',
            ),
          );
        }
      }
    }

    if (app.can('finance.expense.approve')) {
      final rows = await list(ApiPaths.expenses, query: {'branch_id': branch});
      for (final row in rows.where(
        (r) => '${r['status']}'.toLowerCase() == 'pending',
      )) {
        items.add(
          _ApprovalItem(
            kind: 'expense',
            title: 'Expense Approval',
            subtitle:
                '${row['expense_head'] ?? 'Expense'} · ${BusinessFormat.money(num.tryParse('${row['amount'] ?? 0}') ?? 0)}',
            status: 'Pending',
            row: row,
            primaryAction: 'Approve',
            secondaryAction: 'Reject',
            actionId: int.tryParse('${row['id']}'),
            sortKey: '${row['created_at'] ?? row['expense_date'] ?? ''}',
          ),
        );
      }
    }

    if (app.can('inventory.adjustment.approve') && app.can('inventory.view')) {
      final rows = await list(
        ApiPaths.adjustments,
        query: {'branch_id': branch},
      );
      for (final row in rows.where(
        (r) => '${r['status']}'.toLowerCase() == 'pending',
      )) {
        items.add(
          _ApprovalItem(
            kind: 'adjustment',
            title: 'Stock Adjustment Approval',
            subtitle: '${row['reason'] ?? 'Stock adjustment'}',
            status: 'Pending',
            row: row,
            primaryAction: 'Approve',
            secondaryAction: 'Reject',
            actionId: int.tryParse('${row['id']}'),
            sortKey: '${row['created_at'] ?? ''}',
          ),
        );
      }
    }

    if (app.can('workforce.leave.manage')) {
      final rows = await list(
        ApiPaths.leavePending,
        query: {'branch_id': branch},
      );
      for (final row in rows) {
        items.add(
          _ApprovalItem(
            kind: 'leave',
            title: 'Leave Approval',
            subtitle:
                '${row['full_name'] ?? 'Employee'} · ${BusinessFormat.date(row['date_from'])} → ${BusinessFormat.date(row['date_to'])}',
            status: 'Submitted',
            row: row,
            primaryAction: 'Approve',
            secondaryAction: 'Reject',
            actionId: int.tryParse('${row['id']}'),
            sortKey: '${row['requested_at'] ?? row['date_from'] ?? ''}',
          ),
        );
      }
    }

    if (app.can('performance.manage')) {
      final rows = await list(
        ApiPaths.performanceTargets,
        query: {'branch_id': branch},
      );
      for (final row in rows.where(
        (r) => '${r['status']}'.toLowerCase() == 'draft',
      )) {
        items.add(
          _ApprovalItem(
            kind: 'target',
            title: 'Performance Target Approval',
            subtitle:
                '${row['employee_name'] ?? 'Employee'} · ${BusinessFormat.quantity(num.tryParse('${row['target_points'] ?? 0}') ?? 0)} points',
            status: 'Draft · Approval Pending',
            row: row,
            primaryAction: 'Approve',
            actionId: int.tryParse('${row['id']}'),
            sortKey: '${row['created_at'] ?? row['period_end'] ?? ''}',
          ),
        );
      }
    }

    if (app.can('payroll.approve')) {
      final rows = await list(
        ApiPaths.payrollRuns,
        query: {'branch_id': branch},
      );
      for (final row in rows.where(
        (r) => '${r['status']}'.toLowerCase() == 'draft',
      )) {
        items.add(
          _ApprovalItem(
            kind: 'payroll',
            title: 'Payroll Approval',
            subtitle:
                '${BusinessFormat.date(row['period_start'])} → ${BusinessFormat.date(row['period_end'])} · ${BusinessFormat.money(num.tryParse('${row['net_total'] ?? 0}') ?? 0)}',
            status: 'Draft · Approval Pending',
            row: row,
            primaryAction: 'Approve',
            actionId: int.tryParse('${row['id']}'),
            sortKey: '${row['period_end'] ?? ''}',
          ),
        );
      }
    }

    if (app.can('finance.reversal.approve')) {
      final rows = await list(ApiPaths.reversals, query: {'branch_id': branch});
      for (final row in rows.where(
        (r) => '${r['status']}'.toLowerCase() == 'pending',
      )) {
        items.add(
          _ApprovalItem(
            kind: 'reversal',
            title: 'Reversal Approval',
            subtitle:
                '${BusinessFormat.value('source_type', row['source_type'])} · ${row['reason'] ?? ''}',
            status: 'Pending',
            row: row,
            primaryAction: 'Approve',
            secondaryAction: 'Reject',
            actionId: int.tryParse('${row['id']}'),
            sortKey: '${row['requested_at'] ?? row['created_at'] ?? ''}',
          ),
        );
      }
    }

    items.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return _ApprovalResult(items, errors);
  }

  Future<void> _approvalAction(_ApprovalItem item, bool approve) async {
    if (item.kind == 'daily_issue') {
      _openApprovalSource(item);
      return;
    }
    final id = item.actionId;
    if (id == null) return;
    final api = ref.read(apiClientProvider);
    try {
      switch (item.kind) {
        case 'daily':
          await api.post(ApiPaths.dailyApprove(id), data: const {});
          break;
        case 'expense':
          await api.post(
            ApiPaths.expenseDecision(id),
            data: {'approve': approve},
          );
          break;
        case 'adjustment':
          await api.post(
            ApiPaths.adjustmentDecision(id),
            data: {'approve': approve},
          );
          break;
        case 'leave':
          await api.post(
            ApiPaths.leaveDecision(id),
            data: {'approve': approve},
          );
          break;
        case 'target':
          await api.post(ApiPaths.targetApprove(id), data: const {});
          break;
        case 'payroll':
          await api.post(ApiPaths.payrollApprove(id), data: const {});
          break;
        case 'reversal':
          await api.post(
            ApiPaths.reversalDecision(id),
            data: {'approve': approve},
          );
          break;
      }
      if (mounted) {
        setState(() {
          message = approve
              ? '${item.title} approved.'
              : '${item.title} rejected.';
          refresh++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  void _openApprovalSource(_ApprovalItem item) {
    Widget screen = switch (item.kind) {
      'daily' || 'daily_issue' => const TeamScreen(),
      'expense' || 'reversal' => const FinanceScreen(),
      'adjustment' => const InventoryScreen(),
      'target' || 'payroll' => const PerformanceScreen(),
      _ => RecordDetailScreen(
        row: item.row,
        title: item.title,
        recordType: item.kind,
      ),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _runSearch(String value, AppState app) {
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        searchText = q;
        searchFuture = null;
        message = 'Search ke liye kam se kam 2 characters enter karein.';
      });
      return;
    }
    setState(() {
      searchText = q;
      message = null;
      searchFuture = _loadSearch(q, app);
    });
  }

  Future<_SearchResult> _loadSearch(String query, AppState app) async {
    final api = ref.read(apiClientProvider);
    final branch = app.currentBranchId;
    final hits = <_SearchHit>[];
    final errors = <String>[];
    final needle = query.toLowerCase();

    Future<void> source({
      required String group,
      required String recordType,
      required String path,
      Map<String, dynamic>? params,
      List<String> titleKeys = const [],
    }) async {
      try {
        final raw = await api.get(path, query: params);
        final rows = ((raw as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        for (final row in rows) {
          if (!_matches(row, needle)) continue;
          hits.add(
            _SearchHit(
              group: group,
              recordType: recordType,
              row: row,
              title: _searchTitle(row, titleKeys, group),
            ),
          );
          if (hits.length >= 120) return;
        }
      } catch (e) {
        errors.add('$group: $e');
      }
    }

    final futures = <Future<void>>[];
    if (branch != null && app.can('organization.employee.view')) {
      futures.add(
        source(
          group: 'Employees',
          recordType: 'employee',
          path: ApiPaths.employees,
          params: {'branch_id': branch},
          titleKeys: const ['full_name', 'employee_code'],
        ),
      );
    }
    if (app.canAny(const [
      'catalog.product.view',
      'catalog.product.manage',
      'inventory.view',
      'purchase.create',
      'sales.create',
    ])) {
      futures.add(
        source(
          group: 'Products',
          recordType: 'product',
          path: ApiPaths.products,
          titleKeys: const ['name', 'sku'],
        ),
      );
    }
    if (app.canAny(const [
      'sales.view',
      'sales.create',
      'sales.receipt.create',
    ])) {
      futures.add(
        source(
          group: 'Customers',
          recordType: 'customer',
          path: ApiPaths.customers,
          titleKeys: const ['name', 'customer_name', 'mobile'],
        ),
      );
      if (branch != null) {
        futures.add(
          source(
            group: 'Sales',
            recordType: 'sales',
            path: ApiPaths.openSales,
            params: {'branch_id': branch},
            titleKeys: const ['sale_no', 'customer_name'],
          ),
        );
      }
    }
    if (app.canAny(const [
      'purchase.view',
      'purchase.create',
      'finance.supplier_payment.create',
    ])) {
      futures.add(
        source(
          group: 'Suppliers',
          recordType: 'supplier',
          path: ApiPaths.suppliers,
          titleKeys: const ['name', 'supplier_name', 'mobile'],
        ),
      );
      if (branch != null) {
        futures.add(
          source(
            group: 'Purchase Bills',
            recordType: 'purchase',
            path: ApiPaths.openBills,
            params: {'branch_id': branch},
            titleKeys: const ['bill_no', 'supplier_name'],
          ),
        );
      }
    }
    if (branch != null &&
        app.canAny(const ['daily_order.self', 'daily_order.others'])) {
      futures.add(
        source(
          group: 'Daily Orders',
          recordType: 'daily_order',
          path: ApiPaths.dailyCycles,
          params: {'branch_id': branch},
          titleKeys: const ['employee_name', 'business_date'],
        ),
      );
    }
    if (branch != null && app.can('inventory.view')) {
      futures.add(
        source(
          group: 'Stock',
          recordType: 'stock',
          path: ApiPaths.inventoryStock,
          params: {'branch_id': branch},
          titleKeys: const ['product_name', 'sku'],
        ),
      );
    }
    if (branch != null &&
        app.canAny(const [
          'finance.view',
          'finance.expense.create',
          'finance.expense.approve',
        ])) {
      futures.add(
        source(
          group: 'Expenses',
          recordType: 'expense',
          path: ApiPaths.expenses,
          params: {'branch_id': branch},
          titleKeys: const ['expense_head', 'description'],
        ),
      );
    }
    if (branch != null &&
        app.canAny(const ['performance.view', 'performance.manage'])) {
      futures.add(
        source(
          group: 'Targets',
          recordType: 'target',
          path: ApiPaths.performanceTargets,
          params: {'branch_id': branch},
          titleKeys: const ['employee_name', 'period_end'],
        ),
      );
    }
    if (branch != null &&
        app.canAny(const [
          'payroll.generate',
          'payroll.approve',
          'payroll.pay',
        ])) {
      futures.add(
        source(
          group: 'Payroll',
          recordType: 'payroll',
          path: ApiPaths.payrollRuns,
          params: {'branch_id': branch},
          titleKeys: const ['period_end', 'period_start'],
        ),
      );
    }

    await Future.wait(futures);
    hits.sort((a, b) {
      final group = a.group.compareTo(b.group);
      return group != 0 ? group : a.title.compareTo(b.title);
    });
    return _SearchResult(hits.take(100).toList(), errors);
  }

  bool _matches(Map<String, dynamic> row, String needle) {
    return row.entries.any((entry) {
      if (BusinessFormat.isTechnicalKey(entry.key) ||
          entry.value is Map ||
          entry.value is List)
        return false;
      final raw = '${entry.value ?? ''}'.toLowerCase();
      final formatted = BusinessFormat.value(
        entry.key,
        entry.value,
      ).toLowerCase();
      return raw.contains(needle) || formatted.contains(needle);
    });
  }

  String _searchTitle(
    Map<String, dynamic> row,
    List<String> keys,
    String fallback,
  ) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty) {
        return BusinessFormat.value(key, value);
      }
    }
    return '$fallback record';
  }

  void _openSearchHit(_SearchHit hit) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordDetailScreen(
          row: hit.row,
          title: hit.title,
          recordType: hit.recordType,
        ),
      ),
    );
  }

  void _refresh() => setState(() => refresh++);

  bool _approvalVisible(AppState app) => app.canAny(const [
    'daily_order.approve',
    'daily_order.issue',
    'finance.expense.approve',
    'inventory.adjustment.approve',
    'workforce.leave.manage',
    'performance.manage',
    'payroll.approve',
    'finance.reversal.approve',
  ]);
}

class _ApprovalItem {
  const _ApprovalItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.row,
    required this.primaryAction,
    required this.sortKey,
    this.secondaryAction,
    this.actionId,
  });

  final String kind;
  final String title;
  final String subtitle;
  final String status;
  final Map<String, dynamic> row;
  final String primaryAction;
  final String? secondaryAction;
  final int? actionId;
  final String sortKey;
}

class _ApprovalResult {
  const _ApprovalResult(this.items, this.errors);
  final List<_ApprovalItem> items;
  final List<String> errors;
}

class _SearchHit {
  const _SearchHit({
    required this.group,
    required this.recordType,
    required this.row,
    required this.title,
  });
  final String group;
  final String recordType;
  final Map<String, dynamic> row;
  final String title;
}

class _SearchResult {
  const _SearchResult(this.hits, this.errors);
  final List<_SearchHit> hits;
  final List<String> errors;
}

/// Branch-scoped approvals are read from the canonical ERP REST API, never
/// from a client-wide count or guessed role.
class _ApprovalHeader extends StatelessWidget {
  const _ApprovalHeader({required this.count, required this.warnings});
  final int count;
  final int warnings;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('v8-approvals-summary'),
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: ExcelBrand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ExcelBrand.border),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final heading = Row(children: [
          Container(
            width: 42, height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ExcelBrand.primarySoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.fact_check_outlined,
                color: ExcelBrand.primaryDark, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your approval queue',
                style: type.titleMedium?.copyWith(
                  color: ExcelBrand.ink, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text('Authorised branch and role only',
                style: type.bodySmall?.copyWith(color: ExcelBrand.muted)),
            ],
          )),
        ]);
        final countPill = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: ExcelBrand.primarySoft,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text('${count} pending',
            style: type.labelMedium?.copyWith(
              color: ExcelBrand.primaryDark, fontWeight: FontWeight.w900)),
        );
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          constraints.maxWidth < 465
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  heading, const SizedBox(height: 12), countPill,
                ])
              : Row(children: [
                  Expanded(child: heading),
                  const SizedBox(width: 12),
                  countPill,
                ]),
          if (warnings > 0) ...[
            const SizedBox(height: 12),
            Text(
              '${warnings} optional approval source warning(s). Other queues remain visible.',
              style: type.bodySmall?.copyWith(color: ExcelBrand.danger),
            ),
          ],
        ]);
      }),
    );
  }
}

/// Actions preserve the canonical reviewer callbacks and require actual
/// server-side scope / maker-checker validation.
class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.item, required this.onAction, required this.onOpen,
  });
  final _ApprovalItem item;
  final Future<void> Function(_ApprovalItem, bool) onAction;
  final void Function(_ApprovalItem) onOpen;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return Card(
      key: ValueKey('v8-approval-item-${item.sortKey}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 17, 18, 15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38, height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ExcelBrand.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.task_alt_rounded,
                  color: ExcelBrand.primaryDark, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: type.titleMedium?.copyWith(
                    color: ExcelBrand.ink, fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(item.subtitle, maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: type.bodySmall?.copyWith(color: ExcelBrand.muted)),
              ],
            )),
          ]),
          const SizedBox(height: 10),
          _StatusChip(item.status),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 9, children: [
            OutlinedButton.icon(
              key: ValueKey('v8-approval-review-${item.sortKey}'),
              onPressed: () => onOpen(item),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Review details'),
            ),
            if (item.secondaryAction != null)
              OutlinedButton(
                onPressed: () => onAction(item, false),
                child: Text(item.secondaryAction!),
              ),
            FilledButton(
              onPressed: () => onAction(item, true),
              child: Text(item.primaryAction),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _SearchHitCard extends StatelessWidget {
  const _SearchHitCard({required this.hit, required this.onTap});
  final _SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visible = hit.row.entries
        .where(
          (e) =>
              !BusinessFormat.isTechnicalKey(e.key) &&
              e.key != 'status' &&
              e.value != null &&
              e.value is! Map &&
              e.value is! List &&
              '${e.value}'.trim().isNotEmpty,
        )
        .take(3)
        .toList();
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            hit.group,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hit.title,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    if (visible.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        visible
                            .map(
                              (e) =>
                                  '${BusinessFormat.label(e.key)}: ${BusinessFormat.value(e.key, e.value)}',
                            )
                            .join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );
}

class _SearchHelp extends StatelessWidget {
  const _SearchHelp();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.manage_search_outlined,
            size: 52,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Search authorised ERP data',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Search is executed on demand so normal ERP navigation stays fast.',
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 42),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
