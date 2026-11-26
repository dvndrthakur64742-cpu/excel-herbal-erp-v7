import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/sales_report_totals.dart';
import '../../core/dashboard_data.dart';
import '../../core/date_time_text.dart';
import '../../core/providers.dart';
import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/workspace_banner.dart';
import '../../widgets/home_start_tasks.dart';
import '../../widgets/home_query.dart';
import '../my_work/my_work_workspace_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    this.openMyWork,
    this.openConnectedAction,
  });

  final VoidCallback? openMyWork;
  final ValueChanged<String>? openConnectedAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final branch = app.currentBranchId;
    final showAttendanceShortcut = app.sectionVisible('my_work') && app.can('workforce.attendance.self') &&
        !app.businessAccessBlocked && openConnectedAction != null;
    final startTasks = HomeStartTaskPlanner.recommend(
      can: app.can,
      sectionVisible: app.sectionVisible,
      businessAccessBlocked: app.businessAccessBlocked,
      alreadyVisible: showAttendanceShortcut ? const {'attendance'} : const {},
    );

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(appStateProvider.notifier).refreshBootstrap();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width >= 960 ? 28 : 16,
          16,
          MediaQuery.sizeOf(context).width >= 960 ? 28 : 16,
          24,
        ),
        children: [
          _IdentityHero(app: app),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('Business date: ${app.businessDate} · ${app.businessTimezone}'),
              TextButton.icon(
                onPressed: () async {
                  await ref.read(appStateProvider.notifier).refreshBootstrap();
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh dashboard'),
              ),
              if (showAttendanceShortcut)
                FilledButton.icon(
                  onPressed: () => openConnectedAction!('attendance'),
                  icon: const Icon(Icons.fingerprint, size: 18),
                  label: const Text('Attendance & Duty'),
                ),
            ],
          ),
          if (app.branchSelectorVisible) ...[
            const SizedBox(height: 12),
            const BranchSelector(),
          ],
          if (startTasks.isNotEmpty && openConnectedAction != null) ...[
            const SizedBox(height: 24),
            HomeStartTasks(
              tasks: startTasks,
              onOpen: (task) => openConnectedAction!(task.id),
            ),
          ],
          if (branch != null && app.managementDashboardVisible) ...[
            const SizedBox(height: 20),
            _SectionTitle(
              title: 'Management Overview',
              subtitle: '${app.currentBranchName} · ${app.businessMonthStart} to ${app.businessDate}',
            ),
            const SizedBox(height: 8),
            _ManagementOverview(
              key: ValueKey('management-$branch-${app.businessDate}'),
              api: api, app: app, branch: branch, onOpen: openConnectedAction),
          ],
          if (app.businessAccessBlocked) ...[
            const SizedBox(height: 16),
            const _InfoNotice(
              icon: Icons.block_outlined,
              text:
                  'No authorised branch is assigned to your account. Business modules are locked until branch access is configured.',
            ),
          ],
          if (app.sectionVisible('my_work')) ...[
            const SizedBox(height: 30),
            _SectionTitle(
              title: 'My Work',
              subtitle: 'Only your authorised self-service work is shown here.',
              action: TextButton.icon(
                onPressed: openMyWork ??
                    () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const Scaffold(
                              body: SafeArea(child: MyWorkWorkspaceScreen()),
                            ),
                          ),
                        ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Open'),
              ),
            ),
            const SizedBox(height: 8),
            if (app.can('workforce.attendance.self') ||
                (branch != null && app.can('performance.view')))
              LayoutBuilder(
                builder: (context, constraints) {
                  final attendance = app.can('workforce.attendance.self');
                  final performance =
                      branch != null && app.can('performance.view');
                  if (constraints.maxWidth >= 850 &&
                      attendance && performance) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _AttendanceCard(api: api, app: app)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _PersonalPerformanceCard(
                            api: api,
                            app: app,
                            branch: branch,
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      if (attendance) _AttendanceCard(api: api, app: app),
                      if (performance) ...[
                        if (attendance) const SizedBox(height: 12),
                        _PersonalPerformanceCard(
                          api: api,
                          app: app,
                          branch: branch,
                        ),
                      ],
                    ],
                  );
                },
              ),
          ],
          if (!app.managementDashboardVisible && app.can('reports.view')) ...[
            const SizedBox(height: 16),
            const _InfoNotice(
              icon: Icons.analytics_outlined,
              text:
                  'Report access is available, but Team management scope is not assigned. Management KPIs are therefore hidden from Home.',
            ),
          ],
          const SizedBox(height: 16),
          ExpansionTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Your access'),
            subtitle: const Text('View role and access details'),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [_AuthorityCard(app: app)],
          ),
        ],
      ),
    );
  }
}

class _IdentityHero extends StatelessWidget {
  const _IdentityHero({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return WorkspaceBanner(
      eyebrow: 'Excel Herbal / Workspace overview',
      title: 'Good ${_dayPart()}, ${app.employeeName}',
      subtitle: '${app.primaryDesignationLabel}  •  ${app.currentBranchName}',
      icon: Icons.dashboard_customize_outlined,
    );
  }

  static String _human(String value) {
    if (value.trim().isEmpty) return '';
    return value
        .split('_')
        .where((e) => e.isNotEmpty)
        .map((e) => '${e[0]}${e.substring(1).toLowerCase()}')
        .join(' ');
  }

  static String _dayPart() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }
}

class _AuthorityCard extends StatelessWidget {
  const _AuthorityCard({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final extras = app.additionalDesignations.length;
    final reporting = _IdentityHero._human(app.reportingCategory);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 530;
            final branch = _AuthorityRow(
              icon: Icons.storefront_outlined,
              label: 'Current branch',
              value: app.currentBranchName,
            );
            final access = _AuthorityRow(
              icon: Icons.shield_outlined,
              label: 'Access scope',
              value:
                  '${app.branches.length} authorised branch${app.branches.length == 1 ? '' : 'es'}',
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR ACCESS',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: ExcelBrand.primaryDark,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                ),
                const SizedBox(height: 13),
                if (compact) ...[
                  branch,
                  const SizedBox(height: 14),
                  access,
                ] else
                  Row(
                    children: [
                      Expanded(child: branch),
                      const SizedBox(width: 12),
                      Expanded(child: access),
                    ],
                  ),
                if (reporting.isNotEmpty) ...[
                  const Divider(height: 24),
                  _AuthorityRow(
                    icon: Icons.account_tree_outlined,
                    label: 'Reporting group',
                    value: reporting,
                  ),
                ],
                if (extras > 0) ...[
                  const Divider(height: 24),
                  _AuthorityRow(
                    icon: Icons.badge_outlined,
                    label: 'Additional responsibilities',
                    value:
                        '$extras assignment${extras == 1 ? '' : 's'}; permissions remain role-scoped',
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({required this.api, required this.app});

  final dynamic api;
  final AppState app;
  String get businessTimezone => app.businessTimezone;

  @override
  Widget build(BuildContext context) => HomeQuery<dynamic>(
        scope: (api, app),
        loader: () => api.get(ApiPaths.attendanceToday),
        builder: (context, snapshot, retry) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingCard(label: 'Loading attendance...');
          }
          if (snapshot.hasError) {
            return _RetryNotice(message: 'Attendance status is temporarily unavailable.', onRetry: retry);
          }
          if (snapshot.data is! Map) {
            return _RetryNotice(message: 'Attendance response is unavailable.', onRetry: retry);
          }
          final row = Map<String, dynamic>.from(snapshot.data as Map);
          if (row.isEmpty) {
            return const _InfoNotice(
              icon: Icons.schedule_outlined,
              text: 'Attendance is not checked in yet.',
            );
          }
          final status = BusinessFormat.status(row['status']);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(21),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: ExcelBrand.primarySoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.fingerprint_rounded,
                          color: ExcelBrand.primaryDark,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Today\'s Attendance',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Your live duty status',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Chip(label: Text(status)),
                    ],
                  ),
                  const Divider(height: 27),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 420;
                      final checkIn = _AttendanceFact(
                        title: 'CHECK-IN',
                        value: DateTimeText.business(row['check_in_at'], businessTimezone),
                        icon: Icons.login_rounded,
                      );
                      final checkOut = _AttendanceFact(
                        title: 'CHECK-OUT',
                        value: DateTimeText.business(row['check_out_at'], businessTimezone),
                        icon: Icons.logout_rounded,
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            checkIn,
                            const SizedBox(height: 14),
                            checkOut,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: checkIn),
                          const SizedBox(width: 12),
                          Expanded(child: checkOut),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      const Icon(Icons.route_outlined,
                          size: 16, color: ExcelBrand.muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final tracker = ref.watch(gpsTrackingProvider);
                            final lastSync = tracker.lastSentAt;
                            return Text(
                              [
                                'Duty GPS: ${BusinessFormat.status(tracker.dutyStatus)}',
                                if (lastSync != null)
                                  'Last sync ${DateTimeText.business(lastSync.toUtc().toIso8601String(), businessTimezone)}',
                                if (tracker.lastError != null) tracker.lastError!,
                              ].join(' · '),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: ExcelBrand.muted),
                            );
                          },
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

class _AttendanceFact extends StatelessWidget {
  const _AttendanceFact({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18, color: ExcelBrand.primaryDark),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: ExcelBrand.muted,
                        letterSpacing: .8,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _PersonalPerformanceCard extends StatelessWidget {
  const _PersonalPerformanceCard({
    required this.api,
    required this.app,
    required this.branch,
  });

  final dynamic api;
  final AppState app;
  final int branch;

  @override
  Widget build(BuildContext context) => HomeQuery<dynamic>(
        scope: (api, app, branch),
        loader: () => api.get(
          ApiPaths.performanceSummary,
          query: {
            'branch_id': branch,
            'from': app.businessMonthStart,
            'to': app.businessDate,
            'employee_id': app.employee['id'],
          },
        ),
        builder: (context, snapshot, retry) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingCard(label: 'Loading performance...');
          }
          if (snapshot.hasError || snapshot.data is! List) {
            return _RetryNotice(message: 'Personal performance is temporarily unavailable.', onRetry: retry);
          }
          final rows = (snapshot.data as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(growable: false);
          if (rows.isEmpty) return const _InfoNotice(icon: Icons.insights_outlined, text: 'No personal performance records for this period.');
          final row = rows.first;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(21),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF1FC),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.insights_rounded,
                          color: Color(0xFF355F9B),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'My Monthly Performance',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 27),
                  Row(
                    children: [
                      Expanded(
                        child: _PerformanceFact(
                          label: 'SALES',
                          value: BusinessFormat.quantity(row['sales_count']),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _PerformanceFact(
                          label: 'POINTS',
                          value: BusinessFormat.quantity(row['points']),
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

class _PerformanceFact extends StatelessWidget {
  const _PerformanceFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: ExcelBrand.muted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: ExcelBrand.ink,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      );
}

class _ManagementOverview extends StatelessWidget {
  const _ManagementOverview({
    super.key,
    required this.api,
    required this.app,
    required this.branch,
    this.onOpen,
  });

  final dynamic api;
  final AppState app;
  final int branch;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) => HomeQuery<Map<String, dynamic>>(
        scope: (api, app, branch),
        loader: _load,
        builder: (context, snapshot, retry) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingCard(label: 'Loading management summary…');
          }
          if (snapshot.hasError) {
            return _RetryNotice(message: 'Management summary is temporarily unavailable.', onRetry: retry);
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          final cards = <_Metric>[];
          final sales = data['sales'] as SalesReportTotals?;
          if (sales != null) {
            cards.add(
              _Metric(
                'Gross Sales',
                BusinessFormat.money(sales.grossMinor / 100),
                Icons.trending_up_rounded,
                route: app.can('reports.view') && app.sectionVisible('reports') ? 'kpi_sales' : null,
              ),
            );
            cards.add(
              _Metric(
                'Month sales outstanding',
                BusinessFormat.money(sales.outstandingMinor / 100),
                Icons.pending_actions_outlined,
                route: app.can('reports.view') && app.sectionVisible('reports') ? 'kpi_sales' : null,
              ),
            );
          }
          final daily = data['daily'] as int?;
          if (daily != null && app.can('daily_order.others')) {
            cards.add(_Metric('Open daily orders · all dates', '$daily', Icons.approval_outlined,
              route: app.sectionVisible('team') ? 'kpi_daily' : null));
          }
          final performance = data['performance'] as num?;
          if (performance != null && app.can('performance.view')) {
            cards.add(
              _Metric(
                'Team Points',
                BusinessFormat.quantity(performance),
                Icons.leaderboard_outlined,
                route: app.sectionVisible('payroll_performance') ? 'kpi_performance' : null,
              ),
            );
          }
          if (sales == null) {
            cards.add(const _Metric('Sales summary', 'Unavailable', Icons.warning_amber_outlined));
          }
          if (daily == null && app.can('daily_order.others')) {
            cards.add(const _Metric('Daily orders', 'Unavailable', Icons.warning_amber_outlined));
          }
          if (performance == null && app.can('performance.view')) {
            cards.add(const _Metric('Team points', 'Unavailable', Icons.warning_amber_outlined));
          }
          if (cards.isEmpty) {
            return const _InfoNotice(
              icon: Icons.dashboard_outlined,
              text: 'No management KPI is available for your current authority.',
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = managementColumns(
                constraints.maxWidth,
                cards.length,
                textScale: MediaQuery.textScalerOf(context).scale(14) / 14,
              );
              final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sales == null || (daily == null && app.can('daily_order.others')) ||
                      (performance == null && app.can('performance.view')))
                    _RetryNotice(message: 'Some summaries could not load. Other figures remain available.', onRetry: retry),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final metric in cards)
                        SizedBox(width: width, child: _MetricCard(metric: metric,
                          onOpen: metric.route == null || onOpen == null ? null : () => onOpen!(metric.route!))),
                    ],
                  ),
                ],
              );
            },
          );
        },
      );

  Future<Map<String, dynamic>> _load() async {
    final period = {
      'branch_id': branch,
      'from': app.businessMonthStart,
      'to': app.businessDate,
    };

    // These summaries are independent, so start every authorised request
    // together instead of stacking network round-trips on the Home screen.
    final salesFuture = _safeRows(
      api.get(ApiPaths.reportsSales, query: period),
    );
    final dailyFuture = app.can('daily_order.others')
        ? _safeDailyCount()
        : Future<int?>.value(null);
    final performanceFuture = app.can('performance.view')
        ? _safeRows(api.get(ApiPaths.performanceSummary, query: period))
        : Future.value(<Map<String, dynamic>>[]);

    final rows = await Future.wait<Object?>([salesFuture, dailyFuture, performanceFuture]);
    final sales = rows[0] as List<Map<String,dynamic>>?;
    final points = rows[2] as List<Map<String,dynamic>>?;
    return {
      'sales': sales == null ? null : SalesReportTotals.read(sales),
      'daily': rows[1],
      'performance': points == null ? null : DashboardData.points(points),
    };
  }

  Future<int?> _safeDailyCount() async {
    try {
      final raw = await api.get(ApiPaths.dailyHistorySearch, query: {
        'branch_id': branch, 'status': 'open', 'page': 1, 'page_size': 1,
      });
      return DashboardData.openCount(raw);
    } catch (_) { return null; }
  }

  Future<List<Map<String, dynamic>>?> _safeRows(Future<dynamic> request) async {
    try {
      final value = await request;
      if (value is! List || value.any((row) => row is! Map)) return null;
      return _rows(value);
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>> _rows(dynamic value) =>
      ((value as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);


}

// Balance four metrics across desktop or medium-width rows.
int managementColumns(double width, int count, {double textScale = 1}) {
  // Larger text needs more usable width per financial value.
  width /= textScale.clamp(1.0, 3.0);
  if (count <= 1 || width < 500) return 1;
  if (width >= 1000 && count >= 4) return 4;
  if (width >= 800 && count == 3) return 3;
  return 2;
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, {this.route});

  final String label;
  final String value;
  final IconData icon;
  final String? route;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, this.onOpen});

  final _Metric metric;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onOpen,
          child: Container(
          constraints: const BoxConstraints(minHeight: 116),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: ExcelBrand.primarySoft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      metric.icon,
                      size: 22,
                      color: ExcelBrand.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      metric.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: ExcelBrand.muted,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (onOpen != null) const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                metric.value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ExcelBrand.ink,
                    ),
              ),
              if (onOpen != null) const Text('View details', style: TextStyle(fontSize: 12, color: ExcelBrand.primaryDark)),
            ],
          ),
        ),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: ExcelBrand.muted),
                ),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      );
}

class _AuthorityRow extends StatelessWidget {
  const _AuthorityRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      );
}

class _RetryNotice extends StatelessWidget {
  const _RetryNotice({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _InfoNotice(icon: Icons.info_outline, text: message),
      TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
    ],
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      );
}

class _InfoNotice extends StatelessWidget {
  const _InfoNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
