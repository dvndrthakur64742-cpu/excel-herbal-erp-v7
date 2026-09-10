import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/daily_order_workflow.dart';
import '../../core/stock_allocation.dart';
import '../../core/providers.dart';
import '../../core/overlay_transition.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';
import 'employee_designations_screen.dart';

class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});
  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
  int refresh = 0;
  String? message;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final tabs = <(String, Widget)>[];
    if (app.canAny(const [
      'daily_order.others',
      'daily_order.approve',
      'daily_order.issue',
      'daily_order.review',
    ])) {
      tabs.add((
        'Daily Orders',
        AsyncPanel(
          key: ValueKey('d-${app.currentBranchId}-$refresh'),
          future: app.currentBranchId == null
              ? Future.value(const <dynamic>[])
              : api.get(
                  ApiPaths.dailyCycles,
                  query: {'branch_id': app.currentBranchId},
                ),
          builder: (context, data) => RecordsList(
            recordType: 'daily_order',
            rows: (data as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
            onTap: _dailyDetail,
          ),
        ),
      ));
    }
    if (app.can('workforce.attendance.manage')) {
      tabs.add((
        'Attendance',
        AsyncPanel(
          key: ValueKey('a-${app.currentBranchId}-$refresh'),
          future: app.currentBranchId == null
              ? Future.value(const <dynamic>[])
              : api.get(
                  ApiPaths.attendanceReport,
                  query: {
                    'branch_id': app.currentBranchId,
                    'from': app.businessMonthStart,
                    'to': app.businessDate,
                  },
                ),
          emptyMessage: 'Attendance record nahi hai.',
          builder: (context, data) => RecordsList(
            recordType: 'attendance',
            rows: (data as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
          ),
        ),
      ));
      tabs.add((
        'GPS Team',
        AsyncPanel(
          key: ValueKey('gps-${app.currentBranchId}-$refresh'),
          future: app.currentBranchId == null
              ? Future.value(const <dynamic>[])
              : api.get(
                  ApiPaths.gpsTeam,
                  query: {'branch_id': app.currentBranchId},
                ),
          emptyMessage: 'No employee is visible in this GPS scope.',
          builder: (context, data) => _GpsTeamList(
            rows: (data as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
            onRoute: _gpsRoute,
          ),
        ),
      ));
    }
    if (app.can('organization.employee.view')) {
      tabs.add((
        'Employees',
        AsyncPanel(
          key: ValueKey('e-${app.currentBranchId}-$refresh'),
          reloadToken: '${app.currentBranchId}-$refresh',
          future: app.currentBranchId == null
              ? Future.value(const <dynamic>[])
              : api.get(
                  ApiPaths.employees,
                  query: {'branch_id': app.currentBranchId},
                ),
          builder: (context, data) => RecordsList(
            recordType: 'employee',
            rows: (data as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
            onTap: _employeeDesignations,
          ),
        ),
      ));
    }
    if (tabs.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No authorised team functions.')),
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Team Operations'),
          bottom: TabBar(
            isScrollable: tabs.length > 3,
            tabs: [for (final tab in tabs) Tab(text: tab.$1)],
          ),
        ),
        body: Column(
          children: [
            const Padding(padding: EdgeInsets.all(16), child: BranchSelector()),
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(message!),
              ),
            Expanded(
              child: app.currentBranchId == null
                  ? const Center(child: Text('Branch select karein.'))
                  : TabBarView(children: [for (final tab in tabs) tab.$2]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _employeeDesignations(Map<String, dynamic> row) async {
    final id = int.tryParse('${row['id'] ?? row['employee_id'] ?? ''}') ?? 0;
    if (id <= 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmployeeDesignationsScreen(
          employeeId: id,
          employeeName: '${row['full_name'] ?? row['employee_name'] ?? 'Employee'}',
        ),
      ),
    );
    if (mounted) setState(() => refresh++);
  }

  Future<void> _gpsRoute(Map<String, dynamic> row) async {
    final employeeId = int.tryParse('${row['employee_id'] ?? ''}') ?? 0;
    if (employeeId <= 0) return;
    final app = ref.read(appStateProvider);
    final date = DateTime.tryParse(app.businessDate) ?? DateTime.now();
    final from = DateTime(date.year, date.month, date.day).toUtc();
    final to = DateTime(date.year, date.month, date.day, 23, 59, 59).toUtc();
    try {
      final data = await ref.read(apiClientProvider).get(
        ApiPaths.gpsRoute,
        query: {
          'employee_id': employeeId,
          'from': from.toIso8601String(),
          'to': to.toIso8601String(),
        },
      );
      if (!mounted) return;
      final points = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (sheetContext) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .72,
          maxChildSize: .94,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${row['full_name'] ?? 'Employee'} · Today’s Route',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text(
                'Route visibility follows the same reporting hierarchy and authorised branch scope as the team list.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              if (points.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No GPS route points recorded.')),
                )
              else
                for (final point in points)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(
                      '${point['latitude'] ?? '—'}, ${point['longitude'] ?? '—'}',
                    ),
                    subtitle: Text(
                      '${BusinessFormat.dateTime(point['recorded_at'])} · accuracy ${point['accuracy_m'] ?? '—'} m',
                    ),
                  ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _dailyDetail(Map<String, dynamic> row) async {
    final id = int.parse('${row['id']}');
    try {
      final api = ref.read(apiClientProvider);
      final app = ref.read(appStateProvider);
      final data = Map<String, dynamic>.from(
        await api.get(ApiPaths.dailyDetail(id)) as Map,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .8,
          maxChildSize: .96,
          builder: (_, controller) {
            final requests = (data['requests'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            return ListView(
              controller: controller,
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Daily Order #$id · ${(data['cycle'] as Map)['status']}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                ...requests.map(
                  (r) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${r['type']} · ${r['status']}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          ...(r['lines'] as List).map(
                            (l) => Text(
                              '${(l as Map)['product_name']} · Qty ${l['quantity']} · Batch ${l['batch_tracking']}',
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (DailyOrderWorkflow.canApproveRequest(
                            '${r['status']}',
                            app.capabilities,
                          ))
                            FilledButton.tonal(
                              onPressed: () =>
                                  _approve(int.parse('${r['id']}')),
                              child: const Text('Approve Request'),
                            ),
                          if (DailyOrderWorkflow.canIssueRequest(
                            '${r['status']}',
                            app.capabilities,
                          ))
                            FilledButton(
                              onPressed: () => _issue(
                                r,
                                int.parse(
                                  '${(data['cycle'] as Map)['branch_id']}',
                                ),
                              ),
                              child: const Text('Issue Stock'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _approve(int requestId) async {
    final app = ref.read(appStateProvider);
    if (!app.can('daily_order.approve')) {
      setState(() => message = 'Daily Order approval permission required hai.');
      return;
    }
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    try {
      await ref
          .read(apiClientProvider)
          .post(ApiPaths.dailyApprove(requestId), data: const {});
      if (mounted) setState(() => refresh++);
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _issue(Map<String, dynamic> request, int branchId) async {
    final app = ref.read(appStateProvider);
    if (!app.can('daily_order.issue')) {
      setState(() => message = 'Daily Order stock issue permission required hai.');
      return;
    }
    try {
      final api = ref.read(apiClientProvider);
      final stock = (await api.get(
        ApiPaths.inventoryStock,
        query: {'branch_id': branchId},
      ) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final requestLines = (request['lines'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final allocations = StockAllocation.fefo(
        requestLines: requestLines,
        stock: stock,
      );
      final closed = await OverlayTransition.closeAndSettle(context);
      if (!closed || !mounted) return;
      await api.post(
        ApiPaths.dailyIssue(int.parse('${request['id']}')),
        data: {'allocations': allocations},
      );
      if (mounted) setState(() => refresh++);
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }
}

class _GpsTeamList extends StatelessWidget {
  const _GpsTeamList({required this.rows, required this.onRoute});

  final List<Map<String, dynamic>> rows;
  final ValueChanged<Map<String, dynamic>> onRoute;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('No employee is visible in this GPS scope.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final row = rows[index];
        final status = '${row['gps_status'] ?? row['status'] ?? 'unknown'}';
        final hasPoint = row['latitude'] != null && row['longitude'] != null;
        return Card(
          child: ListTile(
            leading: Icon(
              status == 'active'
                  ? Icons.location_searching_rounded
                  : status == 'scheduled'
                      ? Icons.schedule_outlined
                      : Icons.location_off_outlined,
            ),
            title: Text('${row['full_name'] ?? 'Employee'}'),
            subtitle: Text(
              '${row['employee_code'] ?? ''} · ${BusinessFormat.status(row['reporting_category'])}\n'
              '${BusinessFormat.status(status)}${hasPoint ? ' · ${BusinessFormat.dateTime(row['latest_gps_at'])}' : ' · no point yet'}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: 'View route',
              onPressed: () => onRoute(row),
              icon: const Icon(Icons.route_outlined),
            ),
          ),
        );
      },
    );
  }
}
