import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/overlay_transition.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';

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
              : api.get(ApiPaths.dailyCycles,
                  query: {'branch_id': app.currentBranchId}),
          builder: (context, data) => RecordsList(
            recordType: 'daily_order',
            rows: (data as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
            onTap: _dailyDetail,
          ),
        )
      ));
    }
    if (app.can('workforce.attendance.manage')) {
      tabs.add((
        'Attendance',
        AsyncPanel(
          key: ValueKey('a-${app.currentBranchId}-$refresh'),
          future: app.currentBranchId == null
              ? Future.value(const <dynamic>[])
              : api.get(ApiPaths.attendanceReport, query: {
                  'branch_id': app.currentBranchId,
                  'from': _monthStart(),
                  'to': _today(),
                }),
          emptyMessage: 'Attendance record nahi hai.',
          builder: (context, data) => RecordsList(
            recordType: 'attendance',
            rows: (data as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
          ),
        )
      ));
    }
    if (app.can('organization.employee.view')) {
      tabs.add((
        'Employees',
        AsyncPanel(
          reloadToken: app.currentBranchId,
          future: app.currentBranchId == null
              ? Future.value(const <dynamic>[])
              : api.get(ApiPaths.employees,
                  query: {'branch_id': app.currentBranchId}),
          builder: (context, data) => RecordsList(
            recordType: 'employee',
            rows: (data as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
          ),
        )
      ));
    }
    if (tabs.isEmpty) {
      return const Scaffold(
          body: Center(child: Text('No authorised team functions.')));
    }
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Team Operations'),
          bottom: TabBar(tabs: [for (final tab in tabs) Tab(text: tab.$1)]),
        ),
        body: Column(children: [
          const Padding(padding: EdgeInsets.all(16), child: BranchSelector()),
          if (message != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(message!)),
          Expanded(
            child: app.currentBranchId == null
                ? const Center(child: Text('Branch select karein.'))
                : TabBarView(children: [for (final tab in tabs) tab.$2]),
          ),
        ]),
      ),
    );
  }

  Future<void> _dailyDetail(Map<String, dynamic> row) async {
    final id = int.parse('${row['id']}');
    try {
      final api = ref.read(apiClientProvider);
      final data = Map<String, dynamic>.from(
          await api.get(ApiPaths.dailyDetail(id)) as Map);
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
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      ...requests.map((r) => Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${r['type']} · ${r['status']}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    ...(r['lines'] as List).map((l) => Text(
                                        '${(l as Map)['product_name']} · Qty ${l['quantity']} · Batch ${l['batch_tracking']}')),
                                    const SizedBox(height: 8),
                                    if ('${r['status']}' == 'submitted')
                                      FilledButton.tonal(
                                          onPressed: () =>
                                              _approve(int.parse('${r['id']}')),
                                          child: const Text('Approve Request')),
                                    if ('${r['status']}' == 'approved')
                                      FilledButton(
                                          onPressed: () => _issue(
                                              r,
                                              int.parse(
                                                  '${(data['cycle'] as Map)['branch_id']}')),
                                          child: const Text('Issue Stock'))
                                  ]))))
                    ]);
              }));
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _approve(int requestId) async {
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
    try {
      final api = ref.read(apiClientProvider);
      final stock = (await api.get(ApiPaths.inventoryStock,
              query: {'branch_id': branchId}) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) =>
              (int.tryParse('${e['custodian_key']}') ?? 0) == 0 &&
              (double.tryParse('${e['quantity']}') ?? 0) > 0)
          .toList();
      final allocations = <Map<String, dynamic>>[];
      for (final raw in (request['lines'] as List)) {
        final l = Map<String, dynamic>.from(raw as Map);
        var remaining = double.tryParse('${l['quantity']}') ?? 0;
        final pid = int.parse('${l['product_id']}');
        final candidates = stock
            .where((s) => int.tryParse('${s['product_id']}') == pid)
            .toList()
          ..sort((x, y) => '${x['expires_on'] ?? '9999-12-31'}'
              .compareTo('${y['expires_on'] ?? '9999-12-31'}'));
        for (final s in candidates) {
          if (remaining <= .0001) break;
          final available = double.tryParse('${s['quantity']}') ?? 0;
          final take = available < remaining ? available : remaining;
          final batchKey = int.tryParse('${s['batch_key']}') ?? 0;
          allocations.add({
            'request_line_id': l['id'],
            'quantity': take,
            if (batchKey > 0) 'batch_id': batchKey
          });
          remaining -= take;
        }
        if (remaining > .0001)
          throw Exception(
              '${l['product_name']} ka authorised branch stock insufficient hai.');
      }
      final closed = await OverlayTransition.closeAndSettle(context);
      if (!closed || !mounted) return;
      await api.post(ApiPaths.dailyIssue(int.parse('${request['id']}')),
          data: {'allocations': allocations});
      if (mounted) setState(() => refresh++);
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _monthStart() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-01';
  }
}
