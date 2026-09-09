import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_paths.dart';
import '../../core/date_time_text.dart';
import '../../core/business_format.dart';
import '../../core/daily_order_math.dart';
import '../../core/daily_order_workflow.dart';
import '../../core/stock_allocation.dart';
import '../../core/providers.dart';
import '../../core/whole_pcs.dart';
import '../../core/ui_error.dart';
import '../../theme/excel_brand.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';

class MyWorkScreen extends ConsumerStatefulWidget {
  const MyWorkScreen({
    super.key,
    this.initialSection = 'attendance',
    this.initialAction,
  });

  final String initialSection;
  final String? initialAction;

  @override
  ConsumerState<MyWorkScreen> createState() => _MyWorkScreenState();
}

class _MyWorkScreenState extends ConsumerState<MyWorkScreen> {
  int refresh = 0;
  String? message;
  bool _handledInitialAction = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _runInitialAction();
    });
  }

  Future<void> _runInitialAction() async {
    if (_handledInitialAction || !mounted || widget.initialAction == null)
      return;
    _handledInitialAction = true;
    try {
      switch (widget.initialAction) {
        case 'new_order':
          await _newDailyOrder();
          break;
        case 'leave':
          await _applyLeave();
          break;
        case 'field_visit':
          await _startVisit();
          break;
        case 'evening':
          final app = ref.read(appStateProvider);
          final api = ref.read(apiClientProvider);
          final rows = await _dailyRows(app, api);
          final candidates = rows
              .where(
                (row) =>
                    '${row['business_date'] ?? ''}' == app.businessDate &&
                    const {
                      'issued',
                      'evening_draft',
                    }.contains('${row['status']}'),
              )
              .toList()
            ..sort(
              (a, b) => (int.tryParse('${b['id']}') ?? 0).compareTo(
                int.tryParse('${a['id']}') ?? 0,
              ),
            );
          if (candidates.isEmpty) {
            if (mounted) {
              setState(
                () => message =
                    'Aaj Evening Closing ke liye koi issued order available nahi hai.',
              );
            }
            return;
          }
          final row = candidates.first;
          await _dailyAction(
            int.parse('${row['id']}'),
            '${row['status']}' == 'evening_draft' ? 'evening_edit' : 'evening',
          );
          break;
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final tabs = <(String, Widget)>[];
    if (app.can('workforce.attendance.self')) {
      tabs.add(('Attendance & Duty', _attendance()));
    }
    if (app.canAny(const [
      'daily_order.self',
      'daily_order.others',
      'daily_order.approve',
      'daily_order.issue',
      'daily_order.review',
    ])) {
      tabs.add(('Daily Order', _daily()));
    }
    if (app.canAny(const [
      'workforce.leave.self',
      'workforce.leave.manage',
      'workforce.field_visit.self',
    ])) {
      tabs.add(('Leave & Visit', _leaveVisit()));
    }
    if (tabs.isEmpty) {
      return const Center(child: Text('No authorised My Work functions.'));
    }
    final preferredLabel = switch (widget.initialSection) {
      'daily' => 'Daily Order',
      'leave_visit' => 'Leave & Visit',
      _ => 'Attendance & Duty',
    };
    final requestedIndex = tabs.indexWhere((tab) => tab.$1 == preferredLabel);
    final initialIndex = requestedIndex < 0 ? 0 : requestedIndex;
    return DefaultTabController(
      length: tabs.length,
      initialIndex: initialIndex,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: BranchSelector(),
          ),
          TabBar(
            isScrollable: true,
            tabs: [for (final tab in tabs) Tab(text: tab.$1)],
          ),
          Expanded(
            child: TabBarView(children: [for (final tab in tabs) tab.$2]),
          ),
        ],
      ),
    );
  }

  Widget _attendance() {
    final api = ref.watch(apiClientProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        AsyncPanel(
          key: ValueKey('att-$refresh'),
          future: api.get(ApiPaths.attendanceToday),
          emptyMessage: 'Aaj attendance pending hai.',
          builder: (context, data) {
            if (data == null) return const SizedBox.shrink();
            final r = Map<String, dynamic>.from(data as Map);
            return Card(
              child: ListTile(
                title: Text('${r['status'] ?? 'present'}'),
                subtitle: Text(
                  'Check-In: ${DateTimeText.local(r['check_in_at'])}\n'
                  'Check-Out: ${DateTimeText.local(r['check_out_at'])}',
                ),
                isThreeLine: true,
              ),
            );
          },
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          _feedbackBanner(message!),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _attendanceAction(true),
              icon: const Icon(Icons.login),
              label: const Text('Check-In'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _attendanceAction(false),
              icon: const Icon(Icons.logout),
              label: const Text('Check-Out'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _daily() {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Daily Orders',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (app.can('daily_order.self') || app.can('daily_order.others'))
                FilledButton.icon(
                  onPressed:
                      app.currentBranchId == null ? null : _newDailyOrder,
                  icon: const Icon(Icons.add),
                  label: const Text('New Order'),
                ),
            ],
          ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _feedbackBanner(message!),
            ),
          ),
        Expanded(
          child: AsyncPanel(
            key: ValueKey('daily-${app.currentBranchId}-$refresh'),
            future: _dailyRows(app, api),
            emptyMessage: 'Daily Order nahi mila.',
            builder: (context, data) {
              final rows = (data as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
              return LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 820) {
                    return Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: DataTable(
                            showBottomBorder: true,
                            headingRowHeight: 46,
                            dataRowMinHeight: 50,
                            columns: const [
                              DataColumn(label: Text('Order')),
                              DataColumn(label: Text('Employee')),
                              DataColumn(label: Text('Business Date')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Action')),
                            ],
                            rows: [
                              for (final r in rows)
                                DataRow(
                                  onSelectChanged: (_) =>
                                      _showDaily(int.parse('${r['id']}')),
                                  cells: [
                                    DataCell(Text('#${r['id']}')),
                                    DataCell(Text(_dailyEmployeeLabel(r))),
                                    DataCell(
                                      Text('${r['business_date'] ?? '—'}'),
                                    ),
                                    DataCell(
                                      Text(_statusText('${r['status']}')),
                                    ),
                                    DataCell(
                                      PopupMenuButton<String>(
                                        tooltip: 'Order actions',
                                        onSelected: (v) => _dailyAction(
                                          int.parse('${r['id']}'),
                                          v,
                                        ),
                                        itemBuilder: (_) =>
                                            _dailyMenu('${r['status']}', app),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final id = int.parse('${r['id']}');
                      final name =
                          '${r['employee_name'] ?? 'Employee #${r['employee_id']}'}';
                      final code = '${r['employee_code'] ?? ''}'.trim();
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showDaily(id),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Daily Order #$id',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                          _orderStatusChip('${r['status']}'),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        code.isEmpty ? name : '$name · $code',
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${r['branch_name'] ?? 'Authorised Branch'} · ${BusinessFormat.date(r['business_date'])}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'Order actions',
                                  onSelected: (v) => _dailyAction(id, v),
                                  itemBuilder: (_) =>
                                      _dailyMenu('${r['status']}', app),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _dailyRows(
    AppState app,
    dynamic api,
  ) async {
    final rows = (await api.get(
      ApiPaths.dailyCycles,
      query: {
        if (app.currentBranchId != null) 'branch_id': app.currentBranchId,
      },
    ) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final branchNames = <int, String>{
      for (final b in app.branches)
        if (int.tryParse('${b['id']}') != null)
          int.parse('${b['id']}'): '${b['name'] ?? 'Branch'}',
    };
    final employeeNames = <int, Map<String, dynamic>>{};
    try {
      final employees = (await api.get(
        ApiPaths.employees,
        query: {
          if (app.currentBranchId != null) 'branch_id': app.currentBranchId,
        },
      ) as List)
          .map((e) => Map<String, dynamic>.from(e as Map));
      for (final e in employees) {
        final id = int.tryParse('${e['id']}');
        if (id != null) employeeNames[id] = e;
      }
    } catch (_) {
      final me = Map<String, dynamic>.from(
        (app.me['employee'] as Map?) ?? const {},
      );
      final id = int.tryParse('${me['id'] ?? ''}');
      if (id != null) employeeNames[id] = me;
    }

    for (final row in rows) {
      final employeeId = int.tryParse('${row['employee_id'] ?? ''}');
      final branchId = int.tryParse('${row['branch_id'] ?? ''}');
      if (employeeId != null && employeeNames[employeeId] != null) {
        final e = employeeNames[employeeId]!;
        row['employee_name'] ??= e['full_name'] ?? e['name'];
        row['employee_code'] ??= e['employee_code'];
      }
      if (branchId != null) row['branch_name'] ??= branchNames[branchId];
    }
    return rows;
  }

  String _dailyEmployeeLabel(Map<String, dynamic> row) {
    final name = '${row['employee_name'] ?? 'Employee #${row['employee_id']}'}';
    final code = '${row['employee_code'] ?? ''}'.trim();
    return code.isEmpty ? name : '$name · $code';
  }

  String _statusText(String status) {
    const map = {
      'morning_draft': 'Draft',
      'stock_requested': 'Approval Pending',
      'approved': 'Issue Pending',
      'issued': 'Evening Pending',
      'evening_draft': 'Evening Draft',
      'evening_submitted': 'Final Post Pending',
      'completed': 'Completed',
      'cancelled': 'Cancelled',
    };
    return map[status] ?? status;
  }

  Widget _orderStatusChip(String status) {
    Color background;
    Color foreground;
    IconData icon;
    switch (status) {
      case 'completed':
        background = const Color(0xFFDFF3E6);
        foreground = ExcelBrand.primaryDark;
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'approved':
      case 'issued':
      case 'stock_requested':
      case 'evening_submitted':
        background = const Color(0xFFFFF0D8);
        foreground = const Color(0xFF8A5700);
        icon = Icons.schedule_rounded;
        break;
      case 'cancelled':
        background = const Color(0xFFFFE6E6);
        foreground = const Color(0xFF9B3030);
        icon = Icons.cancel_outlined;
        break;
      default:
        background = const Color(0xFFF0F3F1);
        foreground = ExcelBrand.muted;
        icon = Icons.edit_note_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            _statusText(status),
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _dailyMenu(String status, AppState app) {
    final out = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'view', child: Text('View Details')),
    ];
    if (DailyOrderWorkflow.canSubmitDraft(status, app.capabilities)) {
      out.add(
        const PopupMenuItem(value: 'submit', child: Text('Submit Order')),
      );
    }
    if (status == 'stock_requested' && app.can('daily_order.approve')) {
      out.add(const PopupMenuItem(value: 'approve', child: Text('Approve')));
    }
    if (status == 'approved' && app.can('daily_order.issue')) {
      out.add(const PopupMenuItem(value: 'issue', child: Text('Issue Stock')));
    }
    if (status == 'issued' &&
        DailyOrderWorkflow.canOperateOwnOrder(app.capabilities)) {
      out.add(
        const PopupMenuItem(
          value: 'additional',
          child: Text('Additional Requirement'),
        ),
      );
      out.add(
        const PopupMenuItem(
          value: 'evening',
          child: Text('Start Evening Closing'),
        ),
      );
    }
    if (status == 'evening_draft') {
      out.add(
        const PopupMenuItem(
          value: 'evening_edit',
          child: Text('Edit Evening Closing'),
        ),
      );
    }
    if (status == 'evening_submitted' && app.can('daily_order.review')) {
      out.add(
        const PopupMenuItem(value: 'final_post', child: Text('Final Post')),
      );
    }
    return out;
  }

  Widget _leaveVisit() {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (app.can('workforce.leave.self')) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Leave',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              FilledButton.icon(
                onPressed: _applyLeave,
                icon: const Icon(Icons.add),
                label: const Text('Apply Leave'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AsyncPanel(
            key: ValueKey('leave-mine-$refresh'),
            future: api.get(ApiPaths.leaveMine),
            emptyMessage: 'Abhi koi leave request nahi hai.',
            builder: (context, data) {
              final rows = ((data as List?) ?? const [])
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              return Column(
                children: [
                  for (final row in rows.take(8))
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.event_note_outlined),
                        title: Text('${row['leave_type'] ?? 'Leave'}'),
                        subtitle: Text(
                          '${BusinessFormat.date(row['date_from'])} – ${BusinessFormat.date(row['date_to'])}\n${row['reason'] ?? ''}',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          BusinessFormat.status(row['status']),
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        if (app.can('workforce.leave.self') &&
            app.can('workforce.field_visit.self'))
          const Divider(height: 32),
        if (app.can('workforce.field_visit.self')) ...[
          Text('Field Visit', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          AsyncPanel(
            key: ValueKey('visit-current-$refresh'),
            future: api.get(ApiPaths.fieldVisitCurrent),
            emptyMessage: 'Koi active field visit nahi hai.',
            builder: (context, data) {
              final current = data is Map
                  ? Map<String, dynamic>.from(data)
                  : <String, dynamic>{};
              final id = int.tryParse('${current['id'] ?? ''}');
              if (id == null) return const SizedBox.shrink();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.route_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Visit #$id Running',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('${current['purpose'] ?? 'Field Visit'}'),
                      Text(
                        'Started: ${DateTimeText.local(current['started_at'])}',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => _completeVisit(id),
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Complete Visit'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _startVisit,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Start Field Visit'),
          ),
          const SizedBox(height: 8),
          Text(
            'Periodic GPS tracking backend v7.2 se connected hai. Check-In ke baad app foreground mein route points bhejti hai.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (message != null) ...[
          const SizedBox(height: 12),
          _feedbackBanner(message!),
        ],
      ],
    );
  }

  Widget _feedbackBanner(String text) {
    final lower = text.toLowerCase();
    final isError = lower.contains('required') ||
        lower.contains('invalid') ||
        lower.contains('failed') ||
        lower.contains('error') ||
        lower.contains('not found') ||
        lower.contains('could not');
    final bg = isError ? const Color(0xFFFFF2F2) : ExcelBrand.primarySoft;
    final fg = isError ? const Color(0xFF8C2D2D) : ExcelBrand.primaryDark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError
                ? Icons.info_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 20,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<Position> _position() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission required.');
    }
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _attendanceAction(bool checkIn) async {
    final app = ref.read(appStateProvider);
    if (checkIn && app.currentBranchId == null) {
      setState(() => message = 'Authorised Branch select karein.');
      return;
    }
    try {
      final p = await _position();
      await ref.read(apiClientProvider).post(
        checkIn ? ApiPaths.checkIn : ApiPaths.checkOut,
        data: {
          if (checkIn) 'branch_id': app.currentBranchId,
          'lat': p.latitude,
          'lng': p.longitude,
        },
      );
      var gpsStarted = !checkIn;
      if (checkIn) {
        try {
          await ref.read(gpsTrackingProvider).start();
          gpsStarted = true;
        } catch (_) {
          gpsStarted = false;
          // Attendance remains successful even if periodic tracking could not
          // start; the ERP Tools screen exposes the tracking status/retry.
        }
      } else {
        ref.read(gpsTrackingProvider).stop();
      }
      if (mounted) {
        setState(() {
          refresh++;
          message = checkIn
              ? (gpsStarted
                  ? 'Check-In successful. GPS tracking started.'
                  : 'Check-In successful. GPS tracking could not start; ERP Tools se retry karein.')
              : 'Check-Out successful. GPS tracking stopped.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _newDailyOrder() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    try {
      final data = Map<String, dynamic>.from(
        await api.get(ApiPaths.masterData) as Map,
      );
      final products = ((data['products'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (products.isEmpty) throw Exception('Product master empty hai.');

      final employeeMap = Map<String, dynamic>.from(app.me['employee'] as Map);
      var selectedEmployee = int.parse('${employeeMap['id']}');
      var employees = <Map<String, dynamic>>[];
      if (app.can('daily_order.others')) {
        employees = (await api.get(
          ApiPaths.employees,
          query: {'branch_id': app.currentBranchId},
        ) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (employees.any((e) => int.parse('${e['id']}') == selectedEmployee) ==
                false &&
            employees.isNotEmpty) {
          selectedEmployee = int.parse('${employees.first['id']}');
        }
      }

      final qty = <int, TextEditingController>{
        for (final p in products)
          int.parse('${p['id']}'): TextEditingController(),
      };
      String? mode;
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: const Text('Create Daily Order'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (employees.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        initialValue: selectedEmployee,
                        decoration: const InputDecoration(
                          labelText: 'Employee',
                        ),
                        items: employees
                            .map(
                              (e) => DropdownMenuItem<int>(
                                value: int.parse('${e['id']}'),
                                child: Text(
                                  '${e['full_name'] ?? e['name']} · ${e['employee_code'] ?? ''}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null)
                            setLocalState(() => selectedEmployee = v);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    ...products.map((p) {
                      final id = int.parse('${p['id']}');
                      final price = p['sale_price'] == null
                          ? ''
                          : ' · ₹${p['sale_price']}';
                      final points =
                          p['points'] == null ? '' : ' · ${p['points']} pts';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: qty[id],
                          keyboardType: TextInputType.number,
                          inputFormatters: [WholePcs.positiveFormatter],
                          decoration: InputDecoration(
                            labelText: '${p['name']}$price$points',
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton.tonal(
                onPressed: () {
                  mode = 'draft';
                  Navigator.pop(context);
                },
                child: const Text('Save Draft'),
              ),
              FilledButton(
                onPressed: () {
                  mode = 'submit';
                  Navigator.pop(context);
                },
                child: const Text('Create & Submit'),
              ),
            ],
          ),
        ),
      );

      if (mode == null) {
        for (final c in qty.values) c.dispose();
        return;
      }
      final lines = <Map<String, dynamic>>[];
      for (final p in products) {
        final id = int.parse('${p['id']}');
        final q = WholePcs.parseOrZero(qty[id]!.text);
        if (q > 0) lines.add({'product_id': id, 'quantity': q});
      }
      for (final c in qty.values) c.dispose();
      if (lines.isEmpty)
        throw Exception('Kam se kam ek product quantity required hai.');

      final created = Map<String, dynamic>.from(
        await api.post(
          ApiPaths.dailyCycles,
          data: {
            'branch_id': app.currentBranchId,
            'employee_id': selectedEmployee,
            'business_date': app.businessDate,
            'lines': lines,
          },
        ) as Map,
      );
      if (mode == 'submit') {
        await api.post(
          ApiPaths.dailySubmit(int.parse('${created['id']}')),
          data: const {},
        );
      }
      if (mounted) {
        setState(() {
          refresh++;
          message = mode == 'submit'
              ? 'Daily Order submitted for approval.'
              : 'Daily Order draft saved.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<Map<String, dynamic>> _dailyDetail(int id) async {
    return Map<String, dynamic>.from(
      await ref.read(apiClientProvider).get(ApiPaths.dailyDetail(id)) as Map,
    );
  }

  Map<String, dynamic>? _requestWithStatus(
    Map<String, dynamic> detail,
    String status,
  ) {
    final rows = ((detail['requests'] as List?) ?? const []).map(
      (e) => Map<String, dynamic>.from(e as Map),
    );
    for (final r in rows) {
      if ('${r['status']}' == status) return r;
    }
    return null;
  }

  Future<void> _dailyAction(int id, String action) async {
    try {
      final api = ref.read(apiClientProvider);
      final app = ref.read(appStateProvider);
      if (action == 'view') {
        await _showDaily(id);
        return;
      }
      if (action == 'submit') {
        await api.post(ApiPaths.dailySubmit(id), data: const {});
        message = 'Daily Order submitted for approval.';
      } else if (action == 'approve') {
        final d = await _dailyDetail(id);
        final r = _requestWithStatus(d, 'submitted');
        if (r == null) throw Exception('Submitted request not found.');
        await api.post(
          ApiPaths.dailyApprove(int.parse('${r['id']}')),
          data: const {},
        );
        message = 'Daily Order approved. Stock issue pending.';
      } else if (action == 'issue') {
        await _issueDaily(id);
        return;
      } else if (action == 'additional') {
        await _additionalDaily(id);
        return;
      } else if (action == 'evening') {
        final detail = await _dailyDetail(id);
        final cycle = Map<String, dynamic>.from(
          (detail['cycle'] as Map?) ?? const {},
        );
        final requests = ((detail['requests'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        final blockReason = DailyOrderWorkflow.eveningBlockReason(
          cycleStatus: '${cycle['status']}',
          requests: requests,
          capabilities: app.capabilities,
        );
        if (blockReason != null) throw Exception(blockReason);
        await api.post(ApiPaths.eveningStart(id), data: const {});
        await _editEvening(id);
        return;
      } else if (action == 'evening_edit') {
        await _editEvening(id);
        return;
      } else if (action == 'final_post') {
        await _finalPost(id);
        return;
      }
      if (mounted) setState(() => refresh++);
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _additionalDaily(int id) async {
    final api = ref.read(apiClientProvider);
    final data = Map<String, dynamic>.from(
      await api.get(ApiPaths.masterData) as Map,
    );
    final products = ((data['products'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (products.isEmpty) throw Exception('Product master empty hai.');

    final qty = <int, TextEditingController>{
      for (final product in products)
        int.parse('${product['id']}'): TextEditingController(),
    };
    final ok = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Additional Requirement',
                          style: Theme.of(sheetContext).textTheme.titleLarge,
                        ),
                        Text(
                          'Order #$id · whole PCS only',
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: const Row(
                children: [
                  Expanded(
                    child: Text(
                      'Product',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  SizedBox(
                    width: 82,
                    child: Text(
                      'Extra Qty',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                itemCount: products.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = products[index];
                  final productId = int.parse('${product['id']}');
                  return SizedBox(
                    height: 54,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            BusinessFormat.displayName('${product['name']}'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 82,
                          child: TextField(
                            controller: qty[productId],
                            keyboardType: TextInputType.number,
                            inputFormatters: [WholePcs.positiveFormatter],
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              hintText: '0',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        child: const Text('Submit Additional'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    try {
      if (ok == true) {
        final lines = <Map<String, dynamic>>[];
        for (final product in products) {
          final productId = int.parse('${product['id']}');
          final value = WholePcs.parseOrZero(qty[productId]!.text);
          if (value > 0) {
            lines.add({'product_id': productId, 'quantity': value});
          }
        }
        if (lines.isEmpty) {
          throw Exception('Kam se kam ek additional product required hai.');
        }
        await api.post(ApiPaths.dailyAdditional(id), data: {'lines': lines});
        if (mounted) {
          setState(() {
            refresh++;
            message = 'Additional requirement submitted for approval.';
          });
        }
      }
    } finally {
      for (final controller in qty.values) controller.dispose();
    }
  }

  Future<void> _issueDaily(int id) async {
    final api = ref.read(apiClientProvider);
    final d = await _dailyDetail(id);
    final r = _requestWithStatus(d, 'approved');
    if (r == null) throw Exception('Approved request not found.');
    final lines = ((r['lines'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (lines.isEmpty) throw Exception('Approved request lines missing.');
    final cycle = Map<String, dynamic>.from((d['cycle'] as Map?) ?? const {});
    final branchId = int.tryParse('${cycle['branch_id'] ?? ''}');
    if (branchId == null) throw Exception('Daily Order branch missing.');
    final stock = (await api.get(
      ApiPaths.inventoryStock,
      query: {'branch_id': branchId},
    ) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final allocations = StockAllocation.fefo(requestLines: lines, stock: stock);

    final ok = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .92,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: ExcelBrand.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: ExcelBrand.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Issue Stock',
                          style: Theme.of(sheetContext).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Daily Order #$id · ${lines.length} products',
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(sheetContext, false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                itemCount: lines.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final l = lines[index];
                  final name = BusinessFormat.displayName(
                    '${l['product_name'] ?? 'Product'}',
                  );
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: ExcelBrand.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: ExcelBrand.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: ExcelBrand.primarySoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Requested ${BusinessFormat.quantity(l['quantity'])}',
                                style: const TextStyle(
                                  color: ExcelBrand.primaryDark,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Icons.inventory_outlined,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Full approved quantity will be issued using FEFO batches',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(
                  color: ExcelBrand.surface,
                  border: Border(top: BorderSide(color: ExcelBrand.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Verify & Issue'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      await api.post(
        ApiPaths.dailyIssue(int.parse('${r['id']}')),
        data: {'allocations': allocations},
      );
      if (mounted) {
        setState(() {
          refresh++;
          message = 'Stock issued successfully. Evening Closing is pending.';
        });
      }
    }
  }

  Future<void> _editEvening(int id) async {
    final api = ref.read(apiClientProvider);
    final d = await _dailyDetail(id);
    final evening = Map<String, dynamic>.from(
      (d['evening'] as Map?) ?? const {},
    );
    final lines = ((evening['lines'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (lines.isEmpty) throw Exception('Evening lines not found.');

    final returns = <int, TextEditingController>{};
    final wholesale = <int, TextEditingController>{};
    final wholesaleRate = <int, TextEditingController>{};
    for (final l in lines) {
      final key = int.parse('${l['issue_line_id']}');
      returns[key] = TextEditingController(
        text: '${l['return_quantity'] ?? 0}',
      );
      wholesale[key] = TextEditingController(
        text: '${l['wholesale_quantity'] ?? 0}',
      );
      wholesaleRate[key] = TextEditingController(
        text: '${l['wholesale_rate'] ?? 0}',
      );
    }
    final customer = TextEditingController(
      text: '${evening['wholesale_customer_name'] ?? ''}',
    );
    final note = TextEditingController(text: '${evening['notes'] ?? ''}');
    var wholesaleEnabled = customer.text.trim().isNotEmpty ||
        lines.any(
          (line) =>
              (num.tryParse('${line['wholesale_quantity'] ?? 0}') ?? 0) > 0,
        );
    String? mode;

    try {
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setLocal) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: .92,
            minChildSize: .64,
            maxChildSize: .98,
            builder: (context, scrollController) => Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: ExcelBrand.primarySoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.nightlight_round,
                            color: ExcelBrand.primaryDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Evening Closing',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Daily Order #$id · ${lines.length} products',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Wholesale sale?',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 8),
                              SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment<bool>(
                                    value: false,
                                    icon: Icon(Icons.close_rounded),
                                    label: Text('No'),
                                  ),
                                  ButtonSegment<bool>(
                                    value: true,
                                    icon: Icon(Icons.storefront_outlined),
                                    label: Text('Yes'),
                                  ),
                                ],
                                selected: {wholesaleEnabled},
                                onSelectionChanged: (selection) {
                                  setLocal(
                                    () => wholesaleEnabled = selection.first,
                                  );
                                },
                              ),
                              const SizedBox(height: 6),
                              Text(
                                wholesaleEnabled
                                    ? 'Wholesale Qty aur Wholesale Rate product-wise enter karein.'
                                    : 'Wholesale No: sirf Return Qty enter karein.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: ExcelBrand.primarySoft,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.calculate_outlined,
                                color: ExcelBrand.primaryDark,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  wholesaleEnabled
                                      ? 'Return, Wholesale Qty aur Wholesale Rate enter karein. Retail Sold ERP automatically calculate karega.'
                                      : 'Sirf Return Qty enter karein. Retail Sold ERP automatically calculate karega.',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!wholesaleEnabled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            child: const Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Product',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 48,
                                  child: Text(
                                    'Issue',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 48,
                                  child: Text(
                                    'Sold',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 76,
                                  child: Text(
                                    'Return',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: 570,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                child: const Row(
                                  children: [
                                    SizedBox(
                                      width: 170,
                                      child: Text(
                                        'Product',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 58,
                                      child: Text(
                                        'Issue',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 76,
                                      child: Text(
                                        'Return',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 76,
                                      child: Text(
                                        'W.Qty',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 104,
                                      child: Text(
                                        'W.Rate',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 58,
                                      child: Text(
                                        'Sold',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const Divider(height: 1),
                        ...lines.map((l) {
                          final key = int.parse('${l['issue_line_id']}');
                          final issued =
                              double.tryParse('${l['issued_quantity']}') ?? 0;
                          final retailRate =
                              double.tryParse('${l['retail_rate']}') ?? 0;
                          final ret = WholePcs.parseOrZero(returns[key]!.text);
                          final wh = wholesaleEnabled
                              ? WholePcs.parseOrZero(wholesale[key]!.text)
                              : 0;
                          final sold = DailyOrderMath.retailSold(
                            issued,
                            ret,
                            wh,
                          );
                          final over = ret + wh > issued + .0001;
                          final productName = BusinessFormat.displayName(
                            '${l['product_name'] ?? 'Product'}',
                          );

                          InputDecoration qtyDecoration(String hint) =>
                              InputDecoration(
                                hintText: hint,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 9,
                                ),
                              );

                          Widget returnField(double width) => SizedBox(
                                width: width,
                                child: TextField(
                                  controller: returns[key],
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [WholePcs.positiveFormatter],
                                  textAlign: TextAlign.center,
                                  onChanged: (_) => setLocal(() {}),
                                  decoration: qtyDecoration('0'),
                                ),
                              );

                          if (!wholesaleEnabled) {
                            return Container(
                              constraints: const BoxConstraints(minHeight: 54),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: over
                                    ? Theme.of(context)
                                        .colorScheme
                                        .errorContainer
                                        .withValues(alpha: .45)
                                    : null,
                                border: const Border(
                                  bottom: BorderSide(color: ExcelBrand.border),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      productName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 48,
                                    child: Text(
                                      BusinessFormat.quantity(issued),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 48,
                                    child: Text(
                                      BusinessFormat.quantity(sold),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: over
                                            ? ExcelBrand.danger
                                            : ExcelBrand.primaryDark,
                                      ),
                                    ),
                                  ),
                                  returnField(76),
                                ],
                              ),
                            );
                          }

                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: 570,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 56,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: over
                                      ? Theme.of(context)
                                          .colorScheme
                                          .errorContainer
                                          .withValues(alpha: .45)
                                      : null,
                                  border: const Border(
                                    bottom: BorderSide(
                                      color: ExcelBrand.border,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 170,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            productName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          Text(
                                            'Retail ₹${retailRate.toStringAsFixed(2)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 58,
                                      child: Text(
                                        BusinessFormat.quantity(issued),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    returnField(76),
                                    SizedBox(
                                      width: 76,
                                      child: TextField(
                                        controller: wholesale[key],
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          WholePcs.positiveFormatter,
                                        ],
                                        textAlign: TextAlign.center,
                                        onChanged: (_) => setLocal(() {}),
                                        decoration: qtyDecoration('0'),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 104,
                                      child: TextField(
                                        controller: wholesaleRate[key],
                                        enabled: wh > 0,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(
                                          decimal: true,
                                        ),
                                        textAlign: TextAlign.center,
                                        decoration: qtyDecoration(
                                          wh > 0 ? '₹ rate' : '—',
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 58,
                                      child: Text(
                                        BusinessFormat.quantity(sold),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: over
                                              ? ExcelBrand.danger
                                              : ExcelBrand.primaryDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 2),
                        if (wholesaleEnabled) ...[
                          TextField(
                            controller: customer,
                            decoration: const InputDecoration(
                              labelText: 'Wholesale Customer',
                              hintText: 'Wholesale customer name required',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextField(
                          controller: note,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Note (optional)',
                            prefixIcon: Icon(Icons.notes_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Cancel'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () {
                              mode = 'save';
                              Navigator.pop(sheetContext);
                            },
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save Draft'),
                          ),
                          FilledButton.icon(
                            onPressed: () {
                              mode = 'submit';
                              Navigator.pop(sheetContext);
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Save & Submit'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (mode == null) return;

      final payload = <Map<String, dynamic>>[];
      var anyWholesale = false;
      for (final l in lines) {
        final key = int.parse('${l['issue_line_id']}');
        final ret = WholePcs.parseOrZero(returns[key]!.text);
        final wh =
            wholesaleEnabled ? WholePcs.parseOrZero(wholesale[key]!.text) : 0;
        final issued = double.tryParse('${l['issued_quantity']}') ?? 0;
        final retailRate = double.tryParse('${l['retail_rate']}') ?? 0;
        final whRate = wholesaleEnabled
            ? (double.tryParse(wholesaleRate[key]!.text) ?? 0)
            : 0;

        if (ret + wh > issued + 0.0001) {
          throw Exception(
            '${l['product_name']}: Return + Wholesale issued quantity se zyada nahi ho sakta.',
          );
        }
        if (wh > 0 && (whRate <= 0 || whRate > retailRate + .005)) {
          throw Exception(
            '${l['product_name']}: Wholesale rate 0 se zyada aur retail rate se kam/equal hona chahiye.',
          );
        }
        if (wh > 0) anyWholesale = true;
        payload.add({
          'issue_line_id': key,
          'return_quantity': ret,
          'wholesale_quantity': wh,
          'retail_rate': retailRate,
          'wholesale_rate': whRate,
        });
      }

      if (wholesaleEnabled && !anyWholesale) {
        throw Exception(
          'Wholesale Yes select kiya hai. Kam se kam ek Wholesale Qty enter karein.',
        );
      }
      if (wholesaleEnabled && customer.text.trim().isEmpty) {
        throw Exception('Wholesale customer name required.');
      }

      await api.post(
        ApiPaths.eveningSave(id),
        data: {
          'lines': payload,
          'wholesale_details': {
            'wholesale_customer_name':
                wholesaleEnabled ? customer.text.trim() : '',
          },
          'price_reason': note.text.trim(),
        },
      );
      if (mode == 'submit') {
        await api.post(ApiPaths.eveningSubmit(id), data: const {});
      }
      if (mounted) {
        setState(() {
          refresh++;
          message = mode == 'submit'
              ? 'Evening submitted. Final Post pending.'
              : 'Evening draft saved.';
        });
      }
    } finally {
      for (final c in returns.values) c.dispose();
      for (final c in wholesale.values) c.dispose();
      for (final c in wholesaleRate.values) c.dispose();
      customer.dispose();
      note.dispose();
    }
  }

  Future<void> _finalPost(int id) async {
    final api = ref.read(apiClientProvider);
    final d = await _dailyDetail(id);
    final evening = Map<String, dynamic>.from(
      (d['evening'] as Map?) ?? const {},
    );
    final lines = ((evening['lines'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (lines.isEmpty) throw Exception('Evening closing lines not found.');

    final summaries = <Map<String, dynamic>>[];
    var calculatedExpected = 0.0;
    for (final line in lines) {
      final issued = BusinessFormat.number(line['issued_quantity']) ?? 0;
      final returned = BusinessFormat.number(
            line['return_quantity'] ?? line['return_qty'],
          ) ??
          0;
      final wholesaleQty =
          BusinessFormat.number(line['wholesale_quantity']) ?? 0;
      final soldRaw = BusinessFormat.number(
        line['sold_quantity'] ?? line['sold_qty'],
      );
      final retailSold = soldRaw?.toDouble() ??
          DailyOrderMath.retailSold(issued, returned, wholesaleQty);
      final retailRate = BusinessFormat.number(
            line['retail_rate'] ?? line['sale_price'] ?? line['rate'],
          ) ??
          0;
      final wholesaleRate = BusinessFormat.number(line['wholesale_rate']) ?? 0;
      final retailAmount =
          BusinessFormat.number(line['retail_amount'] ?? line['sold_amount'])
                  ?.toDouble() ??
              retailSold * retailRate.toDouble();
      final wholesaleAmount =
          BusinessFormat.number(line['wholesale_amount'])?.toDouble() ??
              wholesaleQty.toDouble() * wholesaleRate.toDouble();
      final lineTotal =
          BusinessFormat.number(line['total_amount'] ?? line['amount'])
                  ?.toDouble() ??
              retailAmount + wholesaleAmount;
      calculatedExpected += lineTotal;
      summaries.add({
        'name': '${line['product_name'] ?? 'Product'}',
        'issued': issued,
        'returned': returned,
        'retail_sold': retailSold,
        'wholesale_qty': wholesaleQty,
        'retail_rate': retailRate,
        'wholesale_rate': wholesaleRate,
        'retail_amount': retailAmount,
        'wholesale_amount': wholesaleAmount,
        'line_total': lineTotal,
      });
    }

    final backendExpected = BusinessFormat.number(
      evening['expected_amount'] ?? evening['total_amount'],
    )?.toDouble();
    final expected = backendExpected ?? calculatedExpected;
    final reconciliationDifference = backendExpected == null
        ? 0.0
        : (backendExpected - calculatedExpected).abs();
    final reconciliationOk = backendExpected == null ||
        DailyOrderMath.reconciliationMatches(
          backendExpected,
          calculatedExpected,
        );

    final cash = TextEditingController(text: expected.toStringAsFixed(2));
    final upi = TextEditingController(text: '0');
    bool? confirmed;

    try {
      if (!mounted) return;
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocal) {
            final cashValue = BusinessFormat.number(cash.text)?.toDouble() ?? 0;
            final upiValue = BusinessFormat.number(upi.text)?.toDouble() ?? 0;
            final deposit = cashValue + upiValue;
            final matched =
                DailyOrderMath.paymentComponentsValid(cashValue, upiValue) &&
                    reconciliationOk &&
                    DailyOrderMath.depositMatches(deposit, expected);

            Widget paymentField({
              required TextEditingController controller,
              required String label,
              required IconData icon,
            }) =>
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setLocal(() {}),
                  decoration: InputDecoration(
                    labelText: label,
                    prefixIcon: Icon(icon),
                    prefixText: '₹ ',
                  ),
                );

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.fact_check_outlined),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Final Post · Daily Order #$id')),
                ],
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 720,
                  maxHeight: MediaQuery.sizeOf(context).height * .72,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sold Products & Amounts',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      ...summaries.map((item) {
                        final wholesaleQty = item['wholesale_qty'] as num;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        BusinessFormat.displayName(
                                          '${item['name']}',
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                    Text(
                                      BusinessFormat.money(item['line_total']),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Retail ${BusinessFormat.quantity(item['retail_sold'])} × ${BusinessFormat.money(item['retail_rate'])} = ${BusinessFormat.money(item['retail_amount'])}',
                                ),
                                if (wholesaleQty > 0) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    'Wholesale ${BusinessFormat.quantity(wholesaleQty)} × ${BusinessFormat.money(item['wholesale_rate'])} = ${BusinessFormat.money(item['wholesale_amount'])}',
                                  ),
                                ],
                                const SizedBox(height: 3),
                                Text(
                                  'Return ${BusinessFormat.quantity(item['returned'])} · Issued ${BusinessFormat.quantity(item['issued'])}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: ExcelBrand.primarySoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Expected Deposit',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Text(
                                  BusinessFormat.money(expected),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: ExcelBrand.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                            if (reconciliationDifference > .01) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Server total ${BusinessFormat.money(backendExpected)} · Product calculation ${BusinessFormat.money(calculatedExpected)}. Final Post blocked hai jab tak dono totals reconcile nahi hote.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Deposit Breakdown',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 520) {
                            return Column(
                              children: [
                                paymentField(
                                  controller: cash,
                                  label: 'Cash Deposit',
                                  icon: Icons.payments_outlined,
                                ),
                                const SizedBox(height: 10),
                                paymentField(
                                  controller: upi,
                                  label: 'Online / UPI',
                                  icon: Icons.account_balance_outlined,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(
                                child: paymentField(
                                  controller: cash,
                                  label: 'Cash Deposit',
                                  icon: Icons.payments_outlined,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: paymentField(
                                  controller: upi,
                                  label: 'Online / UPI',
                                  icon: Icons.account_balance_outlined,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: matched
                              ? ExcelBrand.primarySoft
                              : const Color(0xFFFFECEC),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              matched
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              color: matched
                                  ? ExcelBrand.primaryDark
                                  : ExcelBrand.danger,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Total Cash Deposit = Cash + Online = ${BusinessFormat.money(deposit)}\nRequired ${BusinessFormat.money(expected)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: matched
                                      ? ExcelBrand.primaryDark
                                      : ExcelBrand.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed:
                      matched ? () => Navigator.pop(dialogContext, true) : null,
                  icon: const Icon(Icons.post_add_outlined),
                  label: const Text('Final Post'),
                ),
              ],
            );
          },
        ),
      );

      if (confirmed == true) {
        final c = BusinessFormat.number(cash.text)?.toDouble() ?? 0;
        final u = BusinessFormat.number(upi.text)?.toDouble() ?? 0;
        if (!DailyOrderMath.finalPostAllowed(
          cash: c,
          online: u,
          expected: expected,
          calculatedExpected: calculatedExpected,
          serverExpected: backendExpected,
        )) {
          throw Exception(
            'Final Post blocked: payment components aur product/server reconciliation verify karein.',
          );
        }
        await api.post(ApiPaths.finalPost(id), data: {'cash': c, 'upi': u});
        if (mounted) {
          setState(() {
            refresh++;
            message = 'Daily Order completed and posted.';
          });
        }
      }
    } finally {
      cash.dispose();
      upi.dispose();
    }
  }

  Future<void> _showDaily(int id) async {
    try {
      final d = await _dailyDetail(id);
      if (!mounted) return;
      final cycle = Map<String, dynamic>.from((d['cycle'] as Map?) ?? const {});
      final requests = ((d['requests'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final evening = d['evening'] is Map
          ? Map<String, dynamic>.from(d['evening'] as Map)
          : null;

      final app = ref.read(appStateProvider);
      final branchId = int.tryParse('${cycle['branch_id'] ?? ''}');
      final employeeId = int.tryParse('${cycle['employee_id'] ?? ''}');
      var branchName = 'Authorised Branch';
      for (final b in app.branches) {
        if (int.tryParse('${b['id']}') == branchId) {
          branchName = '${b['name'] ?? branchName}';
          break;
        }
      }
      var employeeName = '${cycle['employee_name'] ?? ''}'.trim();
      var employeeCode = '${cycle['employee_code'] ?? ''}'.trim();
      if (employeeName.isEmpty && employeeId != null) {
        try {
          final employees = (await ref.read(apiClientProvider).get(
            ApiPaths.employees,
            query: {
              if (branchId != null) 'branch_id': branchId,
            },
          ) as List)
              .map((e) => Map<String, dynamic>.from(e as Map));
          for (final e in employees) {
            if (int.tryParse('${e['id']}') == employeeId) {
              employeeName = '${e['full_name'] ?? e['name'] ?? ''}'.trim();
              employeeCode = '${e['employee_code'] ?? ''}'.trim();
              break;
            }
          }
        } catch (_) {}
      }
      if (employeeName.isEmpty) employeeName = 'Employee';
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .82,
          maxChildSize: .96,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily Order #$id',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          BusinessFormat.date(cycle['business_date']),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  _orderStatusChip('${cycle['status']}'),
                ],
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _dailyInfoRow(
                        context,
                        Icons.person_outline,
                        'Employee',
                        employeeCode.isEmpty
                            ? employeeName
                            : '$employeeName · $employeeCode',
                      ),
                      const Divider(height: 18),
                      _dailyInfoRow(
                        context,
                        Icons.store_outlined,
                        'Branch',
                        branchName,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Order Requests',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...requests.map((r) {
                final lines = ((r['lines'] as List?) ?? const [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _requestTypeText('${r['type']}'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                BusinessFormat.status(r['status']),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          for (var i = 0; i < lines.length; i++) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      BusinessFormat.displayName(
                                        '${lines[i]['product_name'] ?? 'Product'}',
                                      ),
                                      style:
                                          Theme.of(context).textTheme.bodyLarge,
                                    ),
                                  ),
                                  Text(
                                    BusinessFormat.quantity(
                                      num.tryParse(
                                            '${lines[i]['quantity'] ?? 0}',
                                          ) ??
                                          0,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                            if (i != lines.length - 1) const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
              if (evening != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Evening Closing',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          BusinessFormat.status(evening['status']),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        ...(((evening['lines'] as List?) ?? const []).map((e) {
                          final l = Map<String, dynamic>.from(e as Map);
                          final returned = num.tryParse(
                                '${l['return_quantity'] ?? l['return_qty'] ?? 0}',
                              ) ??
                              0;
                          final wholesaleSold =
                              num.tryParse('${l['wholesale_quantity'] ?? 0}') ??
                                  0;
                          final issued =
                              num.tryParse('${l['issued_quantity'] ?? 0}') ?? 0;
                          final soldRaw = l['sold_quantity'] ?? l['sold_qty'];
                          final sold = soldRaw == null
                              ? DailyOrderMath.retailSold(
                                  issued,
                                  returned,
                                  wholesaleSold,
                                )
                              : (num.tryParse('$soldRaw') ??
                                  DailyOrderMath.retailSold(
                                    issued,
                                    returned,
                                    wholesaleSold,
                                  ));
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    BusinessFormat.displayName(
                                      '${l['product_name'] ?? 'Product'}',
                                    ),
                                  ),
                                ),
                                Text(
                                  'Retail ${BusinessFormat.quantity(sold)} · Wholesale ${BusinessFormat.quantity(wholesaleSold)} · Return ${BusinessFormat.quantity(returned)}',
                                ),
                              ],
                            ),
                          );
                        })),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Widget _dailyInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) =>
      Row(
        children: [
          Icon(icon, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      );

  String _requestTypeText(String type) => switch (type) {
        'initial' => 'Morning Order',
        'additional' => 'Additional Order',
        'replacement' => 'Replacement Order',
        _ => BusinessFormat.displayName(type.replaceAll('_', ' ')),
      };

  Future<void> _applyLeave() async {
    final app = ref.read(appStateProvider);
    final type = TextEditingController(text: 'Casual Leave');
    final from = TextEditingController(text: app.businessDate);
    final to = TextEditingController(text: app.businessDate);
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply Leave'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: type,
                decoration: const InputDecoration(labelText: 'Leave Type'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: from,
                decoration: const InputDecoration(labelText: 'From YYYY-MM-DD'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: to,
                decoration: const InputDecoration(labelText: 'To YYYY-MM-DD'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Reason'),
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(apiClientProvider).post(
          ApiPaths.leave,
          data: {
            'leave_type': type.text.trim(),
            'date_from': from.text.trim(),
            'date_to': to.text.trim(),
            'reason': reason.text.trim(),
          },
        );
        if (mounted)
          setState(() {
            refresh++;
            message = 'Leave request submitted.';
          });
      } catch (e) {
        if (mounted) setState(() => message = UiError.message(e));
      }
    }
    type.dispose();
    from.dispose();
    to.dispose();
    reason.dispose();
  }

  Future<void> _completeVisit(int id) async {
    try {
      final p = await _position();
      await ref.read(apiClientProvider).post(
        ApiPaths.visitComplete(id),
        data: {'lat': p.latitude, 'lng': p.longitude},
      );
      if (mounted) {
        setState(() {
          refresh++;
          message = 'Field Visit #$id completed.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _startVisit() async {
    final app = ref.read(appStateProvider);
    if (app.currentBranchId == null) {
      setState(() => message = 'Branch select karein.');
      return;
    }
    final purpose = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start Field Visit'),
        content: TextField(
          controller: purpose,
          decoration: const InputDecoration(labelText: 'Purpose'),
          minLines: 2,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, purpose.text.trim().isNotEmpty),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        final p = await _position();
        final r = Map<String, dynamic>.from(
          await ref.read(apiClientProvider).post(
            ApiPaths.fieldVisitStart,
            data: {
              'branch_id': app.currentBranchId,
              'purpose': purpose.text.trim(),
              'lat': p.latitude,
              'lng': p.longitude,
            },
          ) as Map,
        );
        if (mounted)
          setState(() {
            refresh++;
            message = 'Field Visit #${r['id']} started.';
          });
      } catch (e) {
        if (mounted) setState(() => message = UiError.message(e));
      }
    }
    purpose.dispose();
  }
}
