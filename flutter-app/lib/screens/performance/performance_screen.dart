import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';

import 'compensation_workspace.dart';

class PerformanceScreen extends ConsumerStatefulWidget {
  const PerformanceScreen({super.key});

  @override
  ConsumerState<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends ConsumerState<PerformanceScreen> {
  int refresh = 0;
  String? message;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final tabs = <(String, Widget)>[];
    if (app.can('performance.view')) {
      tabs.add((
        'Performance',
        AsyncPanel(
          key: ValueKey('p-${app.currentBranchId}-$refresh'),
          future: app.currentBranchId == null
              ? Future.value(const <dynamic>[])
              : api.get(
                  ApiPaths.performanceSummary,
                  query: {
                    'branch_id': app.currentBranchId,
                    'from': app.businessMonthStart,
                    'to': app.businessDate,
                  },
                ),
          emptyMessage: 'Performance posting nahi hai.',
          builder: (context, data) =>
              RecordsList(recordType: 'performance', rows: _rows(data)),
        ),
      ));
    }
    if (app.canAny(const ['performance.view', 'performance.manage'])) {
      tabs.add((
        'Targets',
        Column(
          children: [
            if (app.can('performance.manage'))
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _createTarget,
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('New Target'),
                  ),
                ),
              ),
            Expanded(
              child: AsyncPanel(
                key: ValueKey('targets-${app.currentBranchId}-$refresh'),
                future: app.currentBranchId == null
                    ? Future.value(const <dynamic>[])
                    : api.get(
                        ApiPaths.performanceTargets,
                        query: {'branch_id': app.currentBranchId},
                      ),
                emptyMessage: 'Koi performance target nahi hai.',
                builder: (context, data) => RecordsList(
                  recordType: 'target',
                  rows: _rows(data),
                  onTap: _targetAction,
                ),
              ),
            ),
          ],
        ),
      ));
    }
    if (app.canAny(const [
      'salary.view',
      'salary.manage',
      'salary.approve',
      'rewards.view',
      'rewards.manage',
      'rewards.approve',
      'rewards.pay',
      'promotion.view',
      'promotion.request',
      'promotion.approve',
    ])) {
      tabs.add((
        'Compensation',
        const CompensationWorkspace(),
      ));
    }
    if (app.canAny(const [
      'payroll.generate',
      'payroll.approve',
      'payroll.pay',
    ])) {
      tabs.add((
        'Payroll',
        Column(
          children: [
            if (app.can('payroll.generate'))
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _generate,
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('Generate Payroll Draft'),
                  ),
                ),
              ),
            Expanded(
              child: AsyncPanel(
                key: ValueKey('payroll-${app.currentBranchId}-$refresh'),
                future: app.currentBranchId == null
                    ? Future.value(const <dynamic>[])
                    : api.get(
                        ApiPaths.payrollRuns,
                        query: {'branch_id': app.currentBranchId},
                      ),
                emptyMessage: 'Payroll run nahi hai.',
                builder: (context, data) => RecordsList(
                  recordType: 'payroll',
                  rows: _rows(data),
                  onTap: _showPayroll,
                ),
              ),
            ),
          ],
        ),
      ));
    }
    if (tabs.isEmpty)
      return const Scaffold(
        body: Center(
          child: Text('No authorised payroll/performance functions.'),
        ),
      );
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Payroll & Performance'),
          bottom: TabBar(
            isScrollable: true,
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

  List<Map<String, dynamic>> _rows(dynamic data) =>
      (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _generate() async {
    final app = ref.read(appStateProvider);
    try {
      final result = await ref
          .read(apiClientProvider)
          .post(
            ApiPaths.payrollRuns,
            data: {
              'branch_id': app.currentBranchId,
              'period_start': app.businessMonthStart,
              'period_end': app.businessDate,
            },
          );
      if (mounted) {
        setState(() {
          message = 'Payroll draft #${(result as Map)['id']} generated.';
          refresh++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _showPayroll(Map<String, dynamic> row) async {
    final id = int.parse('${row['id']}');
    final app = ref.read(appStateProvider);
    try {
      final raw = await ref
          .read(apiClientProvider)
          .get(ApiPaths.payrollDetail(id));
      final data = Map<String, dynamic>.from(raw as Map);
      final run = Map<String, dynamic>.from(data['run'] as Map);
      final items = (data['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * .82,
            child: Column(
              children: [
                ListTile(
                  title: Text('Payroll #$id · ${run['status']}'),
                  subtitle: Text(
                    '${run['period_start']} → ${run['period_end']} · Net ₹${run['net_total']}',
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      return Card(
                        child: ListTile(
                          title: Text('${item['full_name']}'),
                          subtitle: Text(
                            'Paid ${item['paid_days']}/${item['working_days']} · Attendance ₹${item['attendance_salary']} · Fund ₹${item['salary_fund_earning']}\n'
                            'Bonus ₹${item['bonus']} · Allowance ₹${item['allowances']} · Deduction ₹${item['deductions']} · Net ₹${item['net_salary']}',
                          ),
                          trailing:
                              run['status'] == 'draft' &&
                                  app.can('payroll.generate')
                              ? const Icon(Icons.edit_outlined)
                              : null,
                          onTap:
                              run['status'] == 'draft' &&
                                  app.can('payroll.generate')
                              ? () async {
                                  Navigator.pop(sheetContext);
                                  await _editPayrollItem(id, item);
                                  if (mounted) await _showPayroll(row);
                                }
                              : null,
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (run['status'] == 'draft' &&
                          app.can('payroll.approve'))
                        FilledButton.icon(
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            await _postAction(ApiPaths.payrollApprove(id));
                          },
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Approve Payroll'),
                        ),
                      if (run['status'] == 'approved' && app.can('payroll.pay'))
                        FilledButton.icon(
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            await _payPayroll(id);
                          },
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Pay Payroll'),
                        ),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _editPayrollItem(int runId, Map<String, dynamic> item) async {
    final bonus = TextEditingController(text: '${item['bonus'] ?? 0}');
    final allowance = TextEditingController(text: '${item['allowances'] ?? 0}');
    final deduction = TextEditingController(text: '${item['deductions'] ?? 0}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Review · ${item['full_name']}'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bonus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Bonus'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: allowance,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Allowances'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: deduction,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Deductions'),
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
            child: const Text('Save Review'),
          ),
        ],
      ),
    );
    try {
      if (ok == true) {
        await ref
            .read(apiClientProvider)
            .post(
              ApiPaths.payrollItemUpdate(runId, int.parse('${item['id']}')),
              data: {
                'bonus': double.tryParse(bonus.text.trim()) ?? 0,
                'allowances': double.tryParse(allowance.text.trim()) ?? 0,
                'deductions': double.tryParse(deduction.text.trim()) ?? 0,
              },
            );
        if (mounted) {
          setState(() {
            message = 'Payroll item reviewed.';
            refresh++;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    } finally {
      bonus.dispose();
      allowance.dispose();
      deduction.dispose();
    }
  }

  Future<void> _payPayroll(int id) async {
    final app = ref.read(appStateProvider);
    try {
      final raw = await ref
          .read(apiClientProvider)
          .get(ApiPaths.financeBootstrap);
      final data = Map<String, dynamic>.from(raw as Map);
      final accounts = (data['accounts'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where(
            (e) =>
                '${e['type']}' == 'asset' &&
                const {
                  'cash',
                  'bank',
                  'upi',
                }.contains('${e['subtype']}'.toLowerCase()),
          )
          .toList();
      if (!mounted) return;
      int? accountId;
      final date = TextEditingController(text: app.businessDate);
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text('Pay Payroll #$id'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: accountId,
                    decoration: const InputDecoration(
                      labelText: 'Cash / Bank / UPI Account',
                    ),
                    items: accounts
                        .map(
                          (e) => DropdownMenuItem<int>(
                            value: int.parse('${e['id']}'),
                            child: Text('${e['code']} · ${e['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setLocal(() => accountId = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: date,
                    decoration: const InputDecoration(
                      labelText: 'Payment Date YYYY-MM-DD',
                    ),
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
                onPressed: () => Navigator.pop(context, accountId != null),
                child: const Text('Post Payment'),
              ),
            ],
          ),
        ),
      );
      if (ok == true && accountId != null) {
        final result = await ref
            .read(apiClientProvider)
            .post(
              ApiPaths.payrollPay(id),
              data: {
                'payment_account_id': accountId,
                'payment_date': date.text.trim(),
              },
            );
        if (mounted) {
          setState(() {
            message = 'Payroll paid: $result';
            refresh++;
          });
        }
      }
      date.dispose();
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _createTarget() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    try {
      final employees = (await api.get(
        ApiPaths.employees,
        query: {'branch_id': app.currentBranchId},
      ) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      int? employeeId;
      final points = TextEditingController();
      final from = TextEditingController(text: app.businessMonthStart);
      final to = TextEditingController(text: app.businessDate);
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Performance Target'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: employeeId,
                    decoration: const InputDecoration(labelText: 'Employee'),
                    items: employees
                        .map(
                          (e) => DropdownMenuItem<int>(
                            value: int.parse('${e['id']}'),
                            child: Text(
                              '${e['full_name']} · ${e['designation_code']}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setLocal(() => employeeId = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: from,
                    decoration: const InputDecoration(
                      labelText: 'Period Start YYYY-MM-DD',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: to,
                    decoration: const InputDecoration(
                      labelText: 'Period End YYYY-MM-DD',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: points,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Target Points',
                    ),
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
                onPressed: () => Navigator.pop(context, employeeId != null),
                child: const Text('Create Draft'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        await api.post(
          ApiPaths.performanceTargets,
          data: {
            'branch_id': app.currentBranchId,
            'employee_id': employeeId,
            'period_start': from.text.trim(),
            'period_end': to.text.trim(),
            'target_points': double.tryParse(points.text) ?? 0,
          },
        );
        if (mounted) {
          setState(() {
            message = 'Performance target draft created.';
            refresh++;
          });
        }
      }
      points.dispose();
      from.dispose();
      to.dispose();
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  void _targetAction(Map<String, dynamic> row) {
    final app = ref.read(appStateProvider);
    if ('${row['status']}' != 'draft' || !app.can('performance.manage')) return;
    final id = int.parse('${row['id']}');
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text(
                '${row['employee_name']} · Target ${row['target_points']} points',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Approve Target'),
              onTap: () {
                Navigator.pop(context);
                _postAction(ApiPaths.targetApprove(id));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _postAction(String path) async {
    try {
      final result = await ref
          .read(apiClientProvider)
          .post(path, data: const {});
      if (mounted) {
        setState(() {
          message = 'Done: $result';
          refresh++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }
}
