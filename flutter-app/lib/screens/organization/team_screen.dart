import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/daily_order_workflow.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/business_date_field.dart';
import '../../widgets/records_list.dart';
import '../../widgets/module_workspace.dart';
import '../../widgets/gps_route_view.dart';
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
          emptyMessage: 'No attendance records for the selected period.',
          builder: (context, data) => RecordsList(
            recordType: 'attendance',
            rows: (data as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
          ),
        ),
      ));
    }
    if (app.can('workforce.gps.team.view')) {
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
    if (app.can('workforce.leave.manage')) {
      tabs.add(('Holidays', _holidaysTab(app, api)));
    }
    if (app.can('organization.employee.view')) {
      tabs.add((
        'Hierarchy',
        AsyncPanel(
          key: ValueKey('h-${app.currentBranchId}-$refresh'),
          reloadToken: '${app.currentBranchId}-$refresh',
          future: app.currentBranchId == null
              ? Future.value(const <dynamic>[])
              : api.get(
                  ApiPaths.employees,
                  query: {
                    'branch_id': app.currentBranchId,
                    'status': 'active',
                    'limit': 200,
                  },
                ),
          builder: (context, data) => _HierarchyReadinessPanel(
            rows: (data as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(growable: false),
            canManage: app.can('organization.employee.manage'),
            onOpenEmployee: _employeeDesignations,
          ),
        ),
      ));
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
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: ModuleWorkspaceHeader(
                  title: 'Team Operations',
                  subtitle:
                      'Daily work, attendance, holidays, field activity and employee oversight.',
                  icon: Icons.groups_outlined,
                  contextLabel: app.currentBranchName,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: BranchSelector(),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ModuleMessageBanner(message: message!),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 7),
                child: ModuleSectionHeader(
                  title: 'Team Workspace',
                  subtitle:
                      'Use the tabs below for the team functions allowed by your role.',
                ),
              ),
              Expanded(
                child: app.currentBranchId == null
                    ? const Center(
                        child: Text('Select an authorised branch to continue.'),
                      )
                    : TabBarView(children: [for (final tab in tabs) tab.$2]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _holidaysTab(AppState app, dynamic api) {
    final branchId = app.currentBranchId;
    final year = DateTime.now().year;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: branchId == null ? null : () => _createHoliday(app),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Holiday'),
            ),
          ),
        ),
        Expanded(
          child: branchId == null
              ? const Center(child: Text('Select an authorised branch.'))
              : AsyncPanel(
                  key: ValueKey('holidays-$branchId-$refresh'),
                  future: api.get(
                    ApiPaths.holidays,
                    query: {
                      'branch_id': branchId,
                      'from': '$year-01-01',
                      'to': '$year-12-31',
                    },
                  ),
                  emptyMessage: 'No holidays are configured for this branch.',
                  builder: (context, data) {
                    final rows = ((data as List?) ?? const [])
                        .whereType<Map>()
                        .map((e) => Map<String, dynamic>.from(e))
                        .toList();
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final id = int.tryParse('${row['id']}') ?? 0;
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.event_available_outlined),
                            title: Text('${row['name'] ?? 'Holiday'}'),
                            subtitle: Text(
                              BusinessFormat.date(row['holiday_date']),
                            ),
                            trailing: id > 0
                                ? IconButton(
                                    tooltip: 'Deactivate holiday',
                                    onPressed: () => _deactivateHoliday(
                                      id,
                                      '${row['name'] ?? 'Holiday'}',
                                    ),
                                    icon: const Icon(
                                      Icons.remove_circle_outline_rounded,
                                    ),
                                  )
                                : null,
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _createHoliday(AppState app) async {
    final date = TextEditingController(text: app.businessDate);
    final name = TextEditingController();
    String? validation;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('New Holiday'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BusinessDateField(
                  controller: date,
                  label: 'Holiday Date',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Holiday Name'),
                ),
                if (validation != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      validation!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  setLocal(() => validation = 'Holiday name is required.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Create Holiday'),
            ),
          ],
        ),
      ),
    );
    final holidayDate = date.text.trim();
    final holidayName = name.text.trim();
    date.dispose();
    name.dispose();
    if (ok != true || holidayName.isEmpty || app.currentBranchId == null) {
      return;
    }
    try {
      await ref.read(apiClientProvider).post(
        ApiPaths.holidays,
        data: {
          'branch_id': app.currentBranchId,
          'holiday_date': holidayDate,
          'name': holidayName,
        },
      );
      if (mounted) {
        setState(() {
          refresh++;
          message = 'Holiday created.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _deactivateHoliday(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deactivate holiday?'),
        content: Text('$name will be removed from the active holiday calendar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiClientProvider).post(
        ApiPaths.holidayDeactivate(id),
        data: const {},
      );
      if (mounted) {
        setState(() {
          refresh++;
          message = 'Holiday deactivated.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
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
              GpsRouteView(points: points),
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
      final cycle = Map<String, dynamic>.from(data['cycle'] as Map);
      final requests = ((data['requests'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final employee = (app.me['employee'] as Map?) ?? const {};
      final currentEmployeeId = int.tryParse('${employee['id']}');
      var busy = false;
      int? busyRequest;
      String? actionError;
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setLocal) {
            Future<void> perform(Map<String, dynamic> request, bool issue) async {
              if (busy) return;
              setLocal(() {
                busy = true;
                busyRequest = int.parse('${request['id']}');
                actionError = null;
              });
              try {
                if (issue) {
                  await _issue(request);
                } else {
                  await _approve(int.parse('${request['id']}'));
                }
                if (mounted) {
                  setState(() {
                    refresh++;
                    message = issue
                        ? 'Stock issued successfully.'
                        : 'Request approved. Stock issue is pending.';
                  });
                }
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } catch (e) {
                if (sheetContext.mounted) {
                  setLocal(() {
                    busy = false;
                    actionError = UiError.message(e);
                  });
                }
              }
            }

            return PopScope(
              canPop: !busy,
              child: FractionallySizedBox(
                heightFactor: .9,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Daily Order #$id',
                                    style: Theme.of(sheetContext).textTheme.titleLarge),
                                const SizedBox(height: 4),
                                Text(BusinessFormat.date(cycle['business_date']),
                                    style: Theme.of(sheetContext).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: busy ? null : () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(label: Text(_dailyCycleLabel('${cycle['status']}'))),
                              if ('${row['employee_name'] ?? ''}'.trim().isNotEmpty)
                                Chip(
                                  avatar: const Icon(Icons.person_outline, size: 18),
                                  label: Text('${row['employee_name']}'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (requests.isEmpty)
                            const Text('No stock requests found.'),
                          for (final request in requests) ...[
                            _dailyRequestCard(
                              sheetContext,
                              request,
                              app,
                              currentEmployeeId,
                              busy: busy,
                              processing: busy && busyRequest == int.tryParse('${request['id']}'),
                              onAction: (issue) => perform(request, issue),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (actionError != null)
                            ModuleMessageBanner(message: actionError!),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Widget _dailyRequestCard(
    BuildContext context,
    Map<String, dynamic> request,
    AppState app,
    int? currentEmployeeId, {
    required bool busy,
    required bool processing,
    required ValueChanged<bool> onAction,
  }) {
    final lines = ((request['lines'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final requesterId = int.tryParse('${request['requested_by']}');
    final canApprove = DailyOrderWorkflow.canApproveRequest(
      '${request['status']}', app.capabilities,
      requesterId: requesterId, currentEmployeeId: currentEmployeeId,
    );
    final canIssue = DailyOrderWorkflow.canIssueRequest(
      '${request['status']}', app.capabilities,
      requesterId: requesterId, currentEmployeeId: currentEmployeeId,
    );
    final total = lines.fold<num>(0,
        (sum, line) => sum + (num.tryParse('${line['quantity']}') ?? 0));
    final title = switch ('${request['type']}') {
      'initial' => 'Morning Stock Request',
      'additional' => 'Additional Stock Request',
      'replacement' => 'Replacement Stock Request',
      _ => 'Stock Request',
    };
    final status = switch ('${request['status']}') {
      'submitted' => 'Approval Pending',
      'approved' => 'Ready to Issue',
      _ => BusinessFormat.status(request['status']),
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('$status · ${lines.length} products · ${_dailyPcs(total)} PCS',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            const Row(
              children: [
                Expanded(child: Text('Product', style: TextStyle(fontWeight: FontWeight.w700))),
                Text('Qty (PCS)', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const Divider(height: 20),
            for (var i = 0; i < lines.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(BusinessFormat.displayName(
                        '${lines[i]['product_name'] ?? 'Product'}'))),
                    const SizedBox(width: 16),
                    Text(_dailyPcs(lines[i]['quantity']),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              if (i < lines.length - 1) const Divider(height: 1),
            ],
            if (canApprove || canIssue) ...[
              const Divider(height: 24),
              if (canIssue) ...[
                const Text('Stock availability and batches are checked automatically when issuing.'),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : () => onAction(canIssue),
                  icon: processing
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(canIssue ? Icons.inventory_2_outlined : Icons.task_alt_rounded),
                  label: Text(processing ? 'Processing...' : canIssue ? 'Issue Stock' : 'Approve Request'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _dailyPcs(dynamic value) {
    final quantity = num.tryParse('$value') ?? 0;
    return quantity == quantity.truncateToDouble()
        ? quantity.toInt().toString()
        : BusinessFormat.quantity(quantity);
  }

  String _dailyCycleLabel(String status) => switch (status) {
    'approved' => 'Stock Issue Pending',
    'issued' => 'Closing Pending',
    _ => BusinessFormat.status(status),
  };

  Future<void> _approve(int requestId) async {
    await ref.read(apiClientProvider).post(
      ApiPaths.dailyApprove(requestId), data: const {},
    );
  }

  Future<void> _issue(Map<String, dynamic> request) async {
    final requestLines = ((request['lines'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (requestLines.isEmpty) throw Exception('Approved request has no product lines.');
    await ref.read(apiClientProvider).post(
      ApiPaths.dailyIssue(int.parse('${request['id']}')),
      data: {
        'allocations': [
          for (final line in requestLines)
            {
              'request_line_id': int.parse('${line['id']}'),
              'quantity': num.parse('${line['quantity']}'),
            },
        ],
      },
    );
  }

}

class _HierarchyReadinessPanel extends StatelessWidget {
  const _HierarchyReadinessPanel({
    required this.rows,
    required this.canManage,
    required this.onOpenEmployee,
  });

  final List<Map<String, dynamic>> rows;
  final bool canManage;
  final ValueChanged<Map<String, dynamic>> onOpenEmployee;

  static const _managerRequiredCategories = {
    'FIELD_EXECUTIVE',
    'ASM',
    'SM',
  };

  @override
  Widget build(BuildContext context) {
    final relevant = rows.where((row) {
      final category =
          '${row['reporting_category'] ?? ''}'.trim().toUpperCase();
      return _managerRequiredCategories.contains(category);
    }).toList(growable: false);
    final linked = relevant.where(_hasManager).length;
    final missing =
        relevant.where((row) => !_hasManager(row)).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      missing.isEmpty
                          ? Icons.account_tree_rounded
                          : Icons.warning_amber_rounded,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Reporting Hierarchy Readiness',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Checks active Field Executive, ASM and SM reporting links inside the selected authorised branch. Reporting Category is used only to classify readiness; it never creates authority. Additional Designations also do not create authority.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ReadinessMetric(
                      label: 'Hierarchy Roles',
                      value: '${relevant.length}',
                    ),
                    _ReadinessMetric(label: 'Linked', value: '$linked'),
                    _ReadinessMetric(label: 'Missing', value: '${missing.length}'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (relevant.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'No active Field Executive, ASM or SM employees in this branch scope.',
                ),
              ),
            ),
          )
        else if (missing.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline_rounded),
              title: Text('Reporting links complete'),
              subtitle: Text(
                'All active Field Executive, ASM and SM employees in this branch have a reporting manager configured.',
              ),
            ),
          )
        else ...[
          Text(
            'Needs setup',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            canManage
                ? 'Open an employee to assign Reporting Manager with an audit reason. No manager is auto-assigned.'
                : 'These reporting links are incomplete. An authorised employee manager must configure them.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final row in missing)
            Card(
              child: ListTile(
                leading: const Icon(Icons.link_off_rounded),
                title: Text('${row['full_name'] ?? 'Employee'}'),
                subtitle: Text(
                  '${row['employee_code'] ?? ''} · ${BusinessFormat.status(row['reporting_category'])}\nReporting Manager: Not assigned',
                ),
                isThreeLine: true,
                trailing: canManage
                    ? IconButton(
                        tooltip: 'Configure reporting manager',
                        onPressed: () => onOpenEmployee(row),
                        icon: const Icon(Icons.arrow_forward_rounded),
                      )
                    : null,
                onTap: canManage ? () => onOpenEmployee(row) : null,
              ),
            ),
        ],
      ],
    );
  }

  static bool _hasManager(Map<String, dynamic> row) =>
      int.tryParse('${row['reporting_employee_id'] ?? ''}') != null;
}

class _ReadinessMetric extends StatelessWidget {
  const _ReadinessMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 96),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      );
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
