import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/date_time_text.dart';
import '../../core/providers.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../my_work/my_work_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final branch = app.currentBranchId;

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final employee = Map<String, dynamic>.from(
          (app.me['employee'] as Map?) ?? const {},
        );

        return RefreshIndicator(
          onRefresh: () =>
              ref.read(appStateProvider.notifier).refreshBootstrap(),
          child: ListView(
            padding: EdgeInsets.all(desktop ? 24 : 16),
            children: [
              if (desktop) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Good ${_dayPart()}, ${employee['full_name'] ?? 'Employee'}',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your authorised ERP workspace and today’s activity.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => ref
                          .read(appStateProvider.notifier)
                          .refreshBootstrap(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const BranchSelector(),
                const SizedBox(height: 18),
                _workspaceCards(context, app, true),
              ] else ...[
                _welcomeHero(context, app, employee),
                const SizedBox(height: 14),
                const BranchSelector(),
              ],
              if (branch != null && app.sectionVisible('my_work')) ...[
                const SizedBox(height: 18),
                _dailyWorkPanel(context, api, app, branch),
              ],
              if (app.can('reports.view') && branch != null) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Management Overview',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      'This month',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _managementPanel(context, api, app, branch, desktop),
              ],
              const SizedBox(height: 24),
              Text(
                'Today',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (desktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _attendanceCard(api)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: branch == null
                          ? const SizedBox.shrink()
                          : _performanceCard(api, app, branch),
                    ),
                  ],
                )
              else ...[
                _attendanceCard(api),
                const SizedBox(height: 12),
                if (branch != null) _performanceCard(api, app, branch),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _welcomeHero(
    BuildContext context,
    AppState app,
    Map<String, dynamic> employee,
  ) {
    final designation = _designation(app);
    final name = '${employee['full_name'] ?? 'Employee'}'.trim();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF08773C), Color(0xFF0B944A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0B8F48),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.16),
                  borderRadius: BorderRadius.circular(15),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.eco_outlined,
                  color: Colors.white,
                  size: 27,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Good ${_dayPart()}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(.78),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  icon: Icons.store_outlined,
                  label: 'Branch',
                  value: _branchName(app),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroMetric(
                  icon: Icons.badge_outlined,
                  label: 'Role',
                  value: designation,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroMetric(
                  icon: Icons.security_outlined,
                  label: 'Access',
                  value: '${app.branches.length} branches',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _workspaceCards(BuildContext context, AppState app, bool desktop) {
    final cards = [
      _InfoCard(
        icon: Icons.store_outlined,
        label: 'Branch',
        value: _branchName(app),
      ),
      _InfoCard(
        icon: Icons.badge_outlined,
        label: 'Designation',
        value: _designation(app),
      ),
      _InfoCard(
        icon: Icons.security_outlined,
        label: 'Authority',
        value:
            '${app.branches.length} branch${app.branches.length == 1 ? '' : 'es'}',
      ),
    ];
    if (desktop) {
      return Row(
        children: [
          Expanded(child: cards[0]),
          const SizedBox(width: 12),
          Expanded(child: cards[1]),
          const SizedBox(width: 12),
          Expanded(child: cards[2]),
        ],
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            _CompactInfoRow(
              icon: Icons.store_outlined,
              label: 'Working branch',
              value: _branchName(app),
            ),
            const Divider(height: 1),
            _CompactInfoRow(
              icon: Icons.badge_outlined,
              label: 'Designation',
              value: _designation(app),
            ),
            const Divider(height: 1),
            _CompactInfoRow(
              icon: Icons.security_outlined,
              label: 'Branch authority',
              value:
                  '${app.branches.length} authorised branch${app.branches.length == 1 ? '' : 'es'}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _dailyWorkPanel(
    BuildContext context,
    dynamic api,
    AppState app,
    int branch,
  ) {
    return AsyncPanel(
      reloadToken: 'daily-work-$branch-${app.employeeName}',
      future: _loadDailyWork(api, app, branch),
      emptyMessage: 'Aaj ka work status available nahi hai.',
      builder: (context, data) {
        final d = Map<String, dynamic>.from(data as Map);
        final attendance = Map<String, dynamic>.from(
          (d['attendance'] as Map?) ?? const {},
        );
        final order = Map<String, dynamic>.from(
          (d['order'] as Map?) ?? const {},
        );
        final tasks = int.tryParse('${d['tasks'] ?? 0}') ?? 0;
        final unread = int.tryParse('${d['unread'] ?? 0}') ?? 0;
        final status = '${order['status'] ?? ''}';
        final next = _nextAction(status, attendance);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Today & Next Action',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const Scaffold(
                            body: SafeArea(child: MyWorkScreen()),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: const Text('Open My Work'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _StatusPill(
                      icon: Icons.how_to_reg_outlined,
                      label: 'Attendance',
                      value: attendance.isEmpty
                          ? 'Pending'
                          : BusinessFormat.status(
                              attendance['status'] ?? 'Present',
                            ),
                    ),
                    _StatusPill(
                      icon: Icons.inventory_2_outlined,
                      label: 'Daily Order',
                      value: status.isEmpty
                          ? 'Not Started'
                          : _homeStatus(status),
                    ),
                    _StatusPill(
                      icon: Icons.task_alt_outlined,
                      label: 'Tasks',
                      value: '$tasks Pending',
                    ),
                    _StatusPill(
                      icon: Icons.notifications_none_rounded,
                      label: 'Unread',
                      value: '$unread',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        next,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadDailyWork(
    dynamic api,
    AppState app,
    int branch,
  ) async {
    final futures = <Future<dynamic>>[
      api.get(ApiPaths.attendanceToday),
      api.get(ApiPaths.dailyCycles, query: {'branch_id': branch}),
      api.get(ApiPaths.communicationSummary),
    ];
    final results = await Future.wait(futures);
    final attendance = results[0] is Map
        ? Map<String, dynamic>.from(results[0] as Map)
        : <String, dynamic>{};
    final rows = ((results[1] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final communication = results[2] is Map
        ? Map<String, dynamic>.from(results[2] as Map)
        : <String, dynamic>{};
    final employee = Map<String, dynamic>.from(
      (app.me['employee'] as Map?) ?? const {},
    );
    final employeeId = int.tryParse('${employee['id'] ?? ''}');
    final today = app.businessDate;
    Map<String, dynamic> order = {};
    for (final row in rows.reversed) {
      final rowEmployee = int.tryParse('${row['employee_id'] ?? ''}');
      if (rowEmployee == employeeId &&
          '${row['business_date'] ?? ''}' == today) {
        order = row;
        break;
      }
    }
    final tasks = ((communication['tasks'] as List?) ?? const []).length;
    final unread = ((communication['notifications'] as List?) ?? const [])
        .whereType<Map>()
        .where((n) => n['read_at'] == null || '${n['read_at']}'.trim().isEmpty)
        .length;
    return {
      'attendance': attendance,
      'order': order,
      'tasks': tasks,
      'unread': unread,
    };
  }

  String _nextAction(String status, Map<String, dynamic> attendance) {
    if (attendance.isEmpty ||
        '${attendance['check_in_at'] ?? ''}'.trim().isEmpty) {
      return 'Next: Attendance Check-In';
    }
    return switch (status) {
      '' => 'Next: Create today’s Daily Order',
      'morning_draft' => 'Next: Submit Daily Order for approval',
      'stock_requested' => 'Next: Approval pending',
      'approved' => 'Next: Stock issue pending',
      'issued' => 'Next: Field work / Additional Requirement / Evening Closing',
      'evening_draft' => 'Next: Submit Evening Closing',
      'evening_submitted' => 'Next: Office Final Post pending',
      'completed' => 'Today’s Daily Order completed',
      _ => 'Open My Work for pending action',
    };
  }

  String _homeStatus(String status) => switch (status) {
    'morning_draft' => 'Draft',
    'stock_requested' => 'Approval Pending',
    'approved' => 'Issue Pending',
    'issued' => 'Evening Pending',
    'evening_draft' => 'Evening Draft',
    'evening_submitted' => 'Final Post Pending',
    'completed' => 'Completed',
    _ => BusinessFormat.status(status),
  };

  Widget _managementPanel(
    BuildContext context,
    dynamic api,
    AppState app,
    int branch,
    bool desktop,
  ) {
    return AsyncPanel(
      reloadToken: '$branch-${app.capabilities.join(',')}',
      future: _loadManagement(api, app, branch),
      emptyMessage: 'Management data is not available for this period.',
      builder: (context, data) {
        final d = Map<String, dynamic>.from(data as Map);
        final sales = (d['sales'] as List<Map<String, dynamic>>?) ?? const [];
        final purchases =
            (d['purchases'] as List<Map<String, dynamic>>?) ?? const [];
        final stock = (d['stock'] as List<Map<String, dynamic>>?) ?? const [];
        final performance =
            (d['performance'] as List<Map<String, dynamic>>?) ?? const [];
        final daily = (d['daily'] as List<Map<String, dynamic>>?) ?? const [];

        final gross = _sum(sales, 'gross_amount');
        final collected = _sum(sales, 'paid_amount');
        final outstanding = _sum(sales, 'outstanding_amount');
        final purchase = _sum(purchases, 'total_amount');
        final stockValue = stock.fold<num>(0, (sum, row) {
          final qty = num.tryParse('${row['quantity'] ?? 0}') ?? 0;
          final cost = num.tryParse('${row['average_unit_cost'] ?? 0}') ?? 0;
          return sum + (qty * cost);
        });
        final pending = daily.where((r) {
          final request = '${r['initial_request_status'] ?? ''}'.toLowerCase();
          final status = '${r['status'] ?? ''}'.toLowerCase();
          return request == 'submitted' ||
              status == 'approved' ||
              status == 'evening_submitted';
        }).length;

        final kpis = [
          _Kpi('Gross Sales', BusinessFormat.money(gross), Icons.trending_up),
          _Kpi(
            'Collected',
            BusinessFormat.money(collected),
            Icons.payments_outlined,
          ),
          _Kpi(
            'Outstanding',
            BusinessFormat.money(outstanding),
            Icons.pending_actions_outlined,
          ),
          _Kpi(
            'Purchases',
            BusinessFormat.money(purchase),
            Icons.shopping_bag_outlined,
          ),
          _Kpi(
            'Stock Value',
            BusinessFormat.money(stockValue),
            Icons.inventory_2_outlined,
          ),
          _Kpi('Pending Work', '$pending', Icons.approval_outlined),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desktop)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.5,
                ),
                itemCount: kpis.length,
                itemBuilder: (_, i) => _KpiCard(kpi: kpis[i]),
              )
            else
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kpis.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) =>
                      SizedBox(width: 176, child: _KpiCard(kpi: kpis[i])),
                ),
              ),
            if (performance.isNotEmpty) ...[
              const SizedBox(height: 12),
              _PerformanceRanking(rows: performance.take(5).toList()),
            ],
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadManagement(
    dynamic api,
    AppState app,
    int branch,
  ) async {
    final period = {
      'branch_id': branch,
      'from': app.businessMonthStart,
      'to': app.businessDate,
    };
    final futures = <Future<dynamic>>[
      api.get(ApiPaths.reportsSales, query: period),
      api.get(ApiPaths.reportsPurchase, query: period),
      api.get(ApiPaths.reportsStock, query: {'branch_id': branch}),
      api.get(ApiPaths.performanceSummary, query: period),
    ];
    final includeDaily = app.can('daily_order.others');
    if (includeDaily) {
      futures.add(api.get(ApiPaths.dailyCycles, query: {'branch_id': branch}));
    }
    final values = await Future.wait(futures);
    List<Map<String, dynamic>> rows(dynamic value) =>
        ((value as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    return {
      'sales': rows(values[0]),
      'purchases': rows(values[1]),
      'stock': rows(values[2]),
      'performance': rows(values[3]),
      'daily': includeDaily ? rows(values[4]) : <Map<String, dynamic>>[],
    };
  }

  num _sum(List<Map<String, dynamic>> rows, String key) => rows.fold<num>(
    0,
    (sum, row) => sum + (num.tryParse('${row[key] ?? 0}') ?? 0),
  );

  Widget _attendanceCard(dynamic api) => AsyncPanel(
    future: api.get(ApiPaths.attendanceToday),
    emptyMessage: 'Aaj attendance start nahi hui.',
    builder: (context, data) {
      if (data == null) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _HomeIcon(icon: Icons.schedule_rounded),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Attendance pending',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 3),
                      Text('Check-In karke duty start karein.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
      final r = Map<String, dynamic>.from(data as Map);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const _HomeIcon(icon: Icons.verified_user_outlined),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      BusinessFormat.status('${r['status'] ?? 'present'}'),
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text('Check-In: ${DateTimeText.local(r['check_in_at'])}'),
                    Text('Check-Out: ${DateTimeText.local(r['check_out_at'])}'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _performanceCard(dynamic api, AppState app, int branch) => AsyncPanel(
    reloadToken: branch,
    future: api.get(
      ApiPaths.performanceSummary,
      query: {
        'branch_id': branch,
        'from': app.businessMonthStart,
        'to': app.businessDate,
        'employee_id': (app.me['employee'] as Map?)?['id'],
      },
    ),
    emptyMessage: 'Is month performance posting nahi hai.',
    builder: (context, data) {
      final rows = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (rows.isEmpty) return const SizedBox.shrink();
      final r = rows.first;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const _HomeIcon(icon: Icons.insights_outlined),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly Performance',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text('Points: ${BusinessFormat.quantity(r['points'])}'),
                    Text(
                      'Salary Fund: ${BusinessFormat.money(r['salary_fund'])}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  String _designation(AppState app) {
    final e = Map<String, dynamic>.from(
      (app.me['employee'] as Map?) ?? const {},
    );
    final name = '${e['designation_name'] ?? ''}'.trim();
    final code = '${e['designation_code'] ?? ''}'.trim();
    if (name.isNotEmpty && code.isNotEmpty) return '$name ($code)';
    if (name.isNotEmpty) return name;
    return code.isNotEmpty ? code : '-';
  }

  String _branchName(AppState app) {
    for (final b in app.branches) {
      if (int.tryParse('${b['id']}') == app.currentBranchId)
        return '${b['name']}';
    }
    return '-';
  }

  static String _dayPart() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 88),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(.13),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withOpacity(.12)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: Colors.white),
        const SizedBox(height: 10),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Colors.white.withOpacity(.7)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 7),
        Text('$label: ', style: Theme.of(context).textTheme.labelMedium),
        Text(
          value,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _CompactInfoRow extends StatelessWidget {
  const _CompactInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(.09),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeIcon extends StatelessWidget {
  const _HomeIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: scheme.primary.withOpacity(.10),
        borderRadius: BorderRadius.circular(15),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 25, color: scheme.primary),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Kpi {
  const _Kpi(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.kpi});
  final _Kpi kpi;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            child: Icon(kpi.icon, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kpi.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  kpi.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PerformanceRanking extends StatelessWidget {
  const _PerformanceRanking({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final maxPoints = rows.fold<double>(0, (max, row) {
      final p = double.tryParse('${row['points'] ?? 0}') ?? 0;
      return p > max ? p : max;
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.leaderboard_outlined, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Top Performance',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < rows.length; i++) ...[
              Row(
                children: [
                  SizedBox(width: 24, child: Text('${i + 1}.')),
                  Expanded(
                    child: Text(
                      '${rows[i]['full_name'] ?? 'Employee'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    BusinessFormat.quantity(
                      num.tryParse('${rows[i]['points'] ?? 0}') ?? 0,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              LinearProgressIndicator(
                value: maxPoints <= 0
                    ? 0
                    : ((double.tryParse('${rows[i]['points'] ?? 0}') ?? 0) /
                              maxPoints)
                          .clamp(0, 1)
                          .toDouble(),
                minHeight: 6,
                borderRadius: BorderRadius.circular(10),
              ),
              if (i != rows.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
