import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../widgets/erp_status_badge.dart';
import '../../widgets/home_query.dart';
import '../../widgets/branch_selector.dart';
import '../../core/operational_health_text.dart';
import '../../core/search_request_scope.dart';
import '../../core/report_period.dart';
import '../../core/bounded_read_queue.dart';
import '../../core/stock_search_preview.dart';
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
  bool _approvalBusy = false;
  String searchText = '';
  Future<_SearchResult>? searchFuture;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchScope = SearchRequestScope<AppState>();
  String? _selectedGroup;
  int _searchRevision = 0;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }
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
          title: const Text('ERP Control Centre'),
          bottom: TabBar(
            isScrollable: true,
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
      return const Column(children: [Padding(padding: EdgeInsets.all(12), child: BranchSelector()), Expanded(child: Center(child: Text('Select an authorised branch.')))]);
    }
    final api = ref.watch(apiClientProvider);
    bool currentScope() => mounted && identical(ref.read(appStateProvider), app) && identical(ref.read(apiClientProvider), api);
    return HomeQuery<_ApprovalResult>(
      scope: (api, app, refresh),
      loader: () => _loadApprovals(app),
      builder: (context, snapshot, retry) {
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
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const BranchSelector(),
                    if (!app.branchSelectorVisible) Text(app.currentBranchName),
                    TextButton.icon(onPressed: retry, icon: const Icon(Icons.refresh), label: const Text('Refresh approvals')),
                    _ApprovalHeader(count: result.items.length, warnings: result.errors.length),
                  ]),
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
                          'Some approval sources could not be loaded (${result.errors.length}). The list is incomplete; refresh to retry.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                ),
              if (result.items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text(OperationalHealthText.approvalEmpty(result.errors.length))),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: result.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, index) => _ApprovalCard(
                      item: result.items[index],
                      busy: _approvalBusy,
                      onAction: (item, approve) async { if (currentScope()) await _approvalAction(item, approve); },
                      onOpen: (item) { if (currentScope() && !_approvalBusy) _openApprovalSource(item); },
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
    final api = ref.watch(apiClientProvider);
    final scopeMatches = _searchScope.matches(app, api);
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
                  const SizedBox(height: 8),
                  const BranchSelector(),
                  Text('Scope: ${app.currentBranchName}'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: CallbackShortcuts(
                          bindings: {const SingleActivator(LogicalKeyboardKey.escape): () { _searchController.clear(); _runSearch('', app); _searchFocus.requestFocus(); }},
                          child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Employee, product, supplier, bill, order, amount...',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (value) => _runSearch(value, app),
                        ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () => _runSearch(_searchController.text, app),
                        icon: const Icon(Icons.search),
                        label: Text(desktop ? 'Search ERP' : 'Search'),
                      ),
                      IconButton(tooltip: 'Clear search', icon: const Icon(Icons.clear), onPressed: () {
                        _searchController.clear(); _runSearch('', app); _searchFocus.requestFocus();
                      }),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: searchFuture != null && !scopeMatches
                  ? Center(child: FilledButton.tonal(onPressed: () => _runSearch(_searchController.text, app), child: const Text('Scope changed — search again')))
                  : searchFuture == null
                  ? const _SearchHelp()
                  : FutureBuilder<_SearchResult>(
                      key: ValueKey(_searchRevision),
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
                          return Center(child: Text(result.errors.isNotEmpty
                            ? 'Search incomplete. Some sources could not be loaded. Retry search.'
                            : 'No matches in loaded authorised records.'));
                        }
                        final groups = result.hits.map((h) => h.group).toSet().toList()..sort();
                        final selected = groups.contains(_selectedGroup) ? _selectedGroup : null;
                        final visible = result.hits.where((h) => selected == null || h.group == selected).toList();
                        return Column(children: [
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${visible.length} displayed · ${result.hits.length} loaded matches${result.limited ? ' (display limit reached)' : ''}'),
                            if (result.errors.isNotEmpty) Text('Incomplete search: ${result.errors.length} source warnings. Retry to refresh.'),
                            Wrap(spacing: 6, children: [
                              ChoiceChip(label: const Text('All'), selected: selected == null, onSelected: (_) => setState(() => _selectedGroup = null)),
                              for (final group in groups) ChoiceChip(label: Text(group), selected: selected == group, onSelected: (_) => setState(() => _selectedGroup = group)),
                            ]),
                          ])),
                          Expanded(child: ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            desktop ? 24 : 16,
                            4,
                            desktop ? 24 : 16,
                            24,
                          ),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _SearchHitCard(
                            hit: visible[i],
                            onTap: () { if (_searchScope.matches(ref.read(appStateProvider), ref.read(apiClientProvider))) _openSearchHit(visible[i]); },
                          ),
                        )),]);
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
    final jobs = <Future<void> Function()>[];
    final revision = refresh;
    bool current() => mounted && refresh == revision && identical(ref.read(appStateProvider),app) && identical(ref.read(apiClientProvider),api);

    Future<List<Map<String, dynamic>>> list(
      String path, {
      Map<String, dynamic>? query,
    }) async {
      try {
        final raw = await api.get(path, query: query);
        if (raw is! List || raw.any((row) => row is! Map)) {
          throw const FormatException('Invalid approval source');
        }
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (e) {
        errors.add('$path: $e');
        return const [];
      }
    }

    if (app.sectionVisible('team') && app.canAny(const [
      'daily_order.approve', 'daily_order.issue', 'daily_order.review', 'daily_order.others',
    ]) && app.canAny(const ['daily_order.self','daily_order.others'])) {
      final today = ReportPeriod.businessDay(app.businessDate);
      final seen = <int>{};
      Future<void> dailyStage(String stage, String title, {String? before}) async {
        try {
          if (!current()) return;
          final data = await api.get(ApiPaths.dailyHistorySearch, query: {
            'branch_id': branch, 'status': stage, 'page': 1, 'page_size': 50,
            if (before != null) 'date_to': before,
          });
          if (data is! Map || data['items'] is! List || data['total'] is! int ||
              data['page'] != 1 || data['page_size'] != 50 || data['has_more'] is! bool) {
            throw const FormatException('Invalid daily approval source');
          }
          if (data['has_more'] == true) errors.add('$title: more records in Team Operations');
          for (final raw in data['items'] as List) {
            if (raw is! Map) throw const FormatException('Invalid daily record');
            final row = Map<String,dynamic>.from(raw);
            final id = int.tryParse('${row['id']}');
            final date = ReportPeriod.businessDay('${row['business_date'] ?? ''}');
            if (id == null || id <= 0 || date == null) {
              errors.add('$title: record requires review');
              continue;
            }
            if (!seen.add(id)) continue;
            final prior = today != null && date.isBefore(today);
            items.add(_ApprovalItem(
              kind: 'daily_review', title: title,
              subtitle: '${row['employee_name'] ?? 'Employee'} · ${BusinessFormat.date(row['business_date'])} · Order #$id',
              status: prior ? 'Earlier business date · ${BusinessFormat.status(row['status'])}' : BusinessFormat.status(row['status']),
              row: row, primaryAction: 'Open Team', sortKey: '${row['business_date']}',
            ));
          }
        } catch (e) {
          errors.add('$title: $e');
        }
      }
      // Keep daily stages in priority order for deterministic deduplication.
      jobs.add(() async {
      if (!current()) return;
      await dailyStage('evening_submitted', 'Evening Closing Review');
      if (today != null) {
        final yesterday = DateTime(today.year,today.month,today.day-1).toIso8601String().substring(0,10);
        await dailyStage('evening_draft', 'Earlier Evening Closing Draft', before: yesterday);
        await dailyStage('issued', 'Earlier Closing Not Started', before: yesterday);
      } else {
        errors.add('Closing date unavailable');
      }
      if (app.canAny(const ['daily_order.approve','daily_order.review','daily_order.others'])) {
        await dailyStage('stock_requested', 'Daily Order Request Review');
      }
      if (app.can('daily_order.issue')) await dailyStage('approved', 'Daily Order Stock Issue');
      });
    }

    if (app.can('finance.expense.approve')) {
      jobs.add(() async {
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
      });
    }

    if (app.can('inventory.adjustment.approve') && app.can('inventory.view')) {
      jobs.add(() async {
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
      });
    }

    if (app.can('workforce.leave.manage')) {
      jobs.add(() async {
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
      });
    }

    if (app.can('performance.manage')) {
      jobs.add(() async {
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
      });
    }

    if (app.can('payroll.approve')) {
      jobs.add(() async {
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
      });
    }

    if (app.can('finance.reversal.approve')) {
      jobs.add(() async {
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
      });
    }

    await BoundedReadQueue.run(jobs, isCurrent: current);
    items.sort((a,b) {
      final date=b.sortKey.compareTo(a.sortKey);
      if(date!=0)return date;
      final kind=a.kind.compareTo(b.kind);
      return kind!=0?kind:'${a.row['id']}'.compareTo('${b.row['id']}');
    });
    return _ApprovalResult(items, errors);
  }

  Future<void> _approvalAction(_ApprovalItem item, bool approve) async {
    if (_approvalBusy || !mounted) return;
    if (item.kind == 'daily_review') {
      _openApprovalSource(item);
      return;
    }
    final id = item.actionId;
    if (id == null || id <= 0 || (!approve && item.secondaryAction == null)) return;
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    final cap = switch (item.kind) {
      'expense' => 'finance.expense.approve',
      'adjustment' => 'inventory.adjustment.approve',
      'leave' => 'workforce.leave.manage',
      'target' => 'performance.manage',
      'payroll' => 'payroll.approve',
      'reversal' => 'finance.reversal.approve',
      _ => null,
    };
    if (cap == null || !app.can(cap) || app.currentBranchId == null || app.businessAccessBlocked) return;
    setState(() => _approvalBusy = true);
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Confirm approval' : 'Confirm rejection'),
        content: Text('${item.title}\n${item.subtitle}\nBranch: ${app.currentBranchName}\nReference #$id'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext,false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext,true), child: Text(approve ? 'Approve' : 'Reject'))],
      ));
      if (!mounted || confirmed != true || !identical(ref.read(appStateProvider),app) || !identical(ref.read(apiClientProvider),api)) return;
      switch (item.kind) {
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
    } finally {
      if (mounted) setState(() => _approvalBusy = false);
    }
  }

  void _openApprovalSource(_ApprovalItem item) {
    Widget screen = switch (item.kind) {
      'daily_review' => const TeamScreen(),
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
        _searchRevision++;
        _selectedGroup = null;
        _searchScope.clear();
        message = q.isEmpty ? null : 'Enter at least 2 characters to search.';
      });
      return;
    }
    setState(() {
      searchText = q;
      message = null;
      _selectedGroup = null;
      _searchRevision++;
      _searchScope.capture(app, ref.read(apiClientProvider));
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
        if (raw is! List || raw.any((row) => row is! Map)) throw const FormatException('Invalid search source');
        final rows = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        var sourceCount = 0;
        for (final row in rows) {
          if (!_matches(row, needle)) continue;
          hits.add(
            _SearchHit(
              group: group,
              recordType: recordType,
              row: row,
              title: _searchTitle(row, titleKeys, group),
              previewFields: recordType == 'stock'
                  ? StockSearchPreview.fields(
                      row,
                      selectedBranchName: app.currentBranchName,
                    )
                  : null,
            ),
          );
          if (++sourceCount >= 101) return;
        }
      } catch (e) {
        errors.add('$group: $e');
      }
    }

    final jobs = <Future<void> Function()>[];
    final revision = _searchRevision;
    bool current() => mounted && revision == _searchRevision && _searchScope.matches(ref.read(appStateProvider),ref.read(apiClientProvider));
    if (branch != null && app.can('organization.employee.view')) {
      jobs.add(
        () => source(
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
      jobs.add(
        () => source(
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
      jobs.add(
        () => source(
          group: 'Customers',
          recordType: 'customer',
          path: ApiPaths.customers,
          titleKeys: const ['name', 'customer_name', 'mobile'],
        ),
      );
      if (branch != null) {
        jobs.add(
          () => source(
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
      jobs.add(
        () => source(
          group: 'Suppliers',
          recordType: 'supplier',
          path: ApiPaths.suppliers,
          titleKeys: const ['name', 'supplier_name', 'mobile'],
        ),
      );
      if (branch != null) {
        jobs.add(
          () => source(
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
      jobs.add(
        () => source(
          group: 'Daily Orders',
          recordType: 'daily_order',
          path: ApiPaths.dailyCycles,
          params: {'branch_id': branch},
          titleKeys: const ['employee_name', 'business_date'],
        ),
      );
    }
    if (branch != null && app.can('inventory.view')) {
      jobs.add(
        () => source(
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
      jobs.add(
        () => source(
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
      jobs.add(
        () => source(
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
      jobs.add(
        () => source(
          group: 'Payroll',
          recordType: 'payroll',
          path: ApiPaths.payrollRuns,
          params: {'branch_id': branch},
          titleKeys: const ['period_end', 'period_start'],
        ),
      );
    }

    await BoundedReadQueue.run(jobs, isCurrent: current);
    hits.sort((a, b) {
      final group = a.group.compareTo(b.group);
      if(group!=0)return group;
      final title=a.title.compareTo(b.title);
      return title!=0?title:'${a.row['id']}'.compareTo('${b.row['id']}');
    });
    return _SearchResult(hits.take(100).toList(), errors, limited: hits.length > 100);
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
    this.previewFields,
  });
  final String group;
  final String recordType;
  final Map<String, dynamic> row;
  final String title;
  final List<MapEntry<String, dynamic>>? previewFields;
}

class _SearchResult {
  const _SearchResult(this.hits, this.errors, {this.limited = false});
  final List<_SearchHit> hits;
  final List<String> errors;
  final bool limited;
}

class _ApprovalHeader extends StatelessWidget {
  const _ApprovalHeader({required this.count, required this.warnings});
  final int count;
  final int warnings;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.approval_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unified Approval Inbox',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  OperationalHealthText.approvalCount(count, warnings),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.item,
    required this.onAction,
    required this.onOpen,
    required this.busy,
  });
  final bool busy;
  final _ApprovalItem item;
  final Future<void> Function(_ApprovalItem, bool) onAction;
  final void Function(_ApprovalItem) onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ErpStatusBadge(status: item.status),
            ],
          ),
          const SizedBox(height: 7),
          Text(item.subtitle),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => onOpen(item),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(item.kind == 'daily_review' ? 'Open Team' : 'Review'),
              ),
              if (item.secondaryAction != null)
                OutlinedButton(
                  onPressed: busy ? null : () => onAction(item, false),
                  child: Text(item.secondaryAction!),
                ),
              if (item.kind != 'daily_review') FilledButton(
                onPressed: busy || item.actionId == null ? null : () => onAction(item, true),
                child: Text(item.primaryAction),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SearchHitCard extends StatelessWidget {
  const _SearchHitCard({required this.hit, required this.onTap});
  final _SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visible = hit.previewFields ?? hit.row.entries
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
