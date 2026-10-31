import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/date_time_text.dart';
import '../../core/providers.dart';
import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';
import '../../widgets/branch_selector.dart';
import '../my_work/my_work_workspace_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.openMyWork});

  final VoidCallback? openMyWork;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final branch = app.currentBranchId;

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(appStateProvider.notifier).refreshBootstrap();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _IdentityHero(app: app),
          const SizedBox(height: 12),
          const BranchSelector(),
          const SizedBox(height: 12),
          _AuthorityCard(app: app),
          if (app.businessAccessBlocked) ...[
            const SizedBox(height: 16),
            const _InfoNotice(
              icon: Icons.block_outlined,
              text:
                  'No authorised branch is assigned to your account. Business modules are locked until branch access is configured.',
            ),
          ],
          if (app.sectionVisible('my_work')) ...[
            const SizedBox(height: 16),
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
            if (app.can('workforce.attendance.self'))
              _AttendanceCard(api: api),
            if (branch != null && app.can('performance.view')) ...[
              const SizedBox(height: 10),
              _PersonalPerformanceCard(api: api, app: app, branch: branch),
            ],
          ],
          if (branch != null && app.managementDashboardVisible) ...[
            const SizedBox(height: 18),
            const _SectionTitle(
              title: 'Management Overview',
              subtitle:
                  'Projected from your Team workspace, report authority and selected authorised branch.',
            ),
            const SizedBox(height: 8),
            _ManagementOverview(api: api, app: app, branch: branch),
          ],
          if (!app.managementDashboardVisible && app.can('reports.view')) ...[
            const SizedBox(height: 16),
            const _InfoNotice(
              icon: Icons.analytics_outlined,
              text:
                  'Report access is available, but Team management scope is not assigned. Management KPIs are therefore hidden from Home.',
            ),
          ],
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
    final reporting = _human(app.reportingCategory);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: const Icon(Icons.person_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Good ${_dayPart()}, ${app.employeeName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      app.primaryDesignationLabel,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (reporting.isNotEmpty || app.additionalDesignations.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (reporting.isNotEmpty)
                  _ContextChip(
                    icon: Icons.account_tree_outlined,
                    label: 'Reporting: $reporting',
                  ),
                if (app.additionalDesignations.isNotEmpty)
                  _ContextChip(
                    icon: Icons.badge_outlined,
                    label:
                        '${app.additionalDesignations.length} additional designation${app.additionalDesignations.length == 1 ? '' : 's'}',
                  ),
              ],
            ),
          ],
        ],
      ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _AuthorityRow(
              icon: Icons.store_outlined,
              label: 'Working Branch',
              value: app.currentBranchName,
            ),
            const Divider(height: 18),
            _AuthorityRow(
              icon: Icons.security_outlined,
              label: 'Branch Authority',
              value:
                  '${app.branches.length} authorised branch${app.branches.length == 1 ? '' : 'es'}',
            ),
            if (extras > 0) ...[
              const Divider(height: 18),
              _AuthorityRow(
                icon: Icons.add_moderator_outlined,
                label: 'Extra Designations',
                value: '$extras responsibility assignment${extras == 1 ? '' : 's'} · no authority inheritance',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({required this.api});

  final dynamic api;

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
        future: api.get(ApiPaths.attendanceToday),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingCard(label: 'Loading attendance…');
          }
          if (snapshot.hasError) {
            return const _InfoNotice(
              icon: Icons.info_outline,
              text: 'Attendance status is temporarily unavailable.',
            );
          }
          final row = snapshot.data is Map
              ? Map<String, dynamic>.from(snapshot.data as Map)
              : <String, dynamic>{};
          if (row.isEmpty) {
            return const _InfoNotice(
              icon: Icons.schedule_outlined,
              text: 'Attendance is not checked in yet.',
            );
          }
          final gps = BusinessFormat.status(row['gps_status'] ?? 'unknown');
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.how_to_reg_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Today’s Attendance',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Chip(label: Text(BusinessFormat.status(row['status']))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('Check-In: ${DateTimeText.local(row['check_in_at'])}'),
                  Text('Check-Out: ${DateTimeText.local(row['check_out_at'])}'),
                  const SizedBox(height: 5),
                  Text(
                    'Duty GPS: $gps · route lifecycle is automatic',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: ExcelBrand.muted),
                  ),
                ],
              ),
            ),
          );
        },
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
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
        future: api.get(
          ApiPaths.performanceSummary,
          query: {
            'branch_id': branch,
            'from': app.businessMonthStart,
            'to': app.businessDate,
            'employee_id': app.employee['id'],
          },
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingCard(label: 'Loading performance…');
          }
          if (snapshot.hasError || snapshot.data is! List) {
            return const SizedBox.shrink();
          }
          final rows = (snapshot.data as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(growable: false);
          if (rows.isEmpty) return const SizedBox.shrink();
          final row = rows.first;
          return Card(
            child: ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: const Text('My Monthly Performance'),
              subtitle: Text(
                'Sales ${BusinessFormat.quantity(row['sales_count'])} · Points ${BusinessFormat.quantity(row['points'])}',
              ),
            ),
          );
        },
      );
}

class _ManagementOverview extends StatelessWidget {
  const _ManagementOverview({
    required this.api,
    required this.app,
    required this.branch,
  });

  final dynamic api;
  final AppState app;
  final int branch;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingCard(label: 'Loading management summary…');
          }
          if (snapshot.hasError) {
            return const _InfoNotice(
              icon: Icons.info_outline,
              text: 'Management summary is temporarily unavailable.',
            );
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          final cards = <_Metric>[];
          final sales = (data['sales'] as List<Map<String, dynamic>>?) ?? const [];
          if (sales.isNotEmpty) {
            cards.add(
              _Metric(
                'Gross Sales',
                BusinessFormat.money(_sum(sales, 'gross_amount')),
                Icons.trending_up_rounded,
              ),
            );
            cards.add(
              _Metric(
                'Outstanding',
                BusinessFormat.money(_sum(sales, 'outstanding_amount')),
                Icons.pending_actions_outlined,
              ),
            );
          }
          final daily = (data['daily'] as List<Map<String, dynamic>>?) ?? const [];
          if (daily.isNotEmpty || app.can('daily_order.others')) {
            final pending = daily.where((row) {
              final status = '${row['status'] ?? ''}'.toLowerCase();
              return status != 'completed' && status != 'cancelled';
            }).length;
            cards.add(_Metric('Pending Daily Work', '$pending', Icons.approval_outlined));
          }
          final performance =
              (data['performance'] as List<Map<String, dynamic>>?) ?? const [];
          if (performance.isNotEmpty) {
            cards.add(
              _Metric(
                'Team Points',
                BusinessFormat.quantity(_sum(performance, 'points')),
                Icons.leaderboard_outlined,
              ),
            );
          }
          if (cards.isEmpty) {
            return const _InfoNotice(
              icon: Icons.dashboard_outlined,
              text: 'No management KPI is available for your current authority.',
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 800
                  ? (constraints.maxWidth - 24) / 3
                  : constraints.maxWidth >= 500
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final metric in cards)
                    SizedBox(width: width, child: _MetricCard(metric: metric)),
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
        ? _safeRows(api.get(ApiPaths.dailyCycles, query: {'branch_id': branch}))
        : Future.value(<Map<String, dynamic>>[]);
    final performanceFuture = app.can('performance.view')
        ? _safeRows(api.get(ApiPaths.performanceSummary, query: period))
        : Future.value(<Map<String, dynamic>>[]);

    final rows = await Future.wait([
      salesFuture,
      dailyFuture,
      performanceFuture,
    ]);
    return {
      'sales': rows[0],
      'daily': rows[1],
      'performance': rows[2],
    };
  }

  Future<List<Map<String, dynamic>>> _safeRows(Future<dynamic> request) async {
    try {
      return _rows(await request);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static List<Map<String, dynamic>> _rows(dynamic value) =>
      ((value as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);

  static num _sum(List<Map<String, dynamic>> rows, String key) => rows.fold<num>(
        0,
        (sum, row) => sum + (BusinessFormat.number(row[key]) ?? 0),
      );
}

class _Metric {
  const _Metric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                child: Icon(metric.icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(metric.label, style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 3),
                    Text(
                      metric.value,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ],
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

class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .76),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
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
              Text(label),
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
