import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/app_config.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';
import '../../widgets/module_workspace.dart';

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
          emptyMessage: 'No performance records for the selected period.',
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
                emptyMessage: 'No performance targets for this branch.',
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
    // Advanced compensation APIs are contract-stage in 7.3.5. Keep the
    // workspace available for UAT builds only; production must not expose an
    // incomplete workflow even if an external/misconfigured capability string
    // is present in bootstrap data.
    if (AppConfig.isUat &&
        app.canAny(const [
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
                emptyMessage: 'No payroll runs for this branch.',
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
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: ModuleWorkspaceHeader(
                  title: 'Payroll & Performance',
                  subtitle:
                      'Performance, targets, payroll and authorised compensation workflows.',
                  icon: Icons.insights_outlined,
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
                  title: 'People Performance Workspace',
                  subtitle:
                      'Use the tabs below for the payroll and performance functions allowed by your role.',
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
      final calculationVersion = '${run['calculation_version'] ?? ''}'.trim();
      final isLegacyDraft =
          '${run['status']}'.toLowerCase() == 'draft' &&
          calculationVersion.isEmpty;
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .9,
          maxChildSize: .96,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Payroll #$id · ${run['period_start']} to ${run['period_end']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('Status: ${run['status']}'),
              if (calculationVersion.isNotEmpty)
                Text('Calculation version: $calculationVersion'),
              if (isLegacyDraft) ...[
                const SizedBox(height: 8),
                const Text(
                  'Legacy payroll draft: calculation version missing. '
                  'Discard and regenerate before approval.',
                ),
              ],
              const SizedBox(height: 12),
              ...items.map(
                (item) => Card(
                  child: ListTile(
                    title: Text(
                      '${item['full_name'] ?? item['employee_name'] ?? 'Employee #${item['employee_id']}'}',
                    ),
                    subtitle: Text(
                      'Paid days: ${item['paid_days'] ?? '0'} · '
                      'Attendance: ${item['attendance_salary'] ?? '0'} · '
                      'Fund: ${item['salary_fund_earning'] ?? '0'} · '
                      'Net: ${item['net_salary'] ?? '0'}',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if ('${run['status']}' == 'draft' &&
                  app.can('payroll.generate'))
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _discardPayroll(id);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Discard Draft'),
                ),
              if ('${run['status']}' == 'draft' &&
                  !isLegacyDraft &&
                  app.can('payroll.approve')) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _approvePayroll(id);
                  },
                  icon: const Icon(Icons.approval_outlined),
                  label: const Text('Approve Payroll'),
                ),
              ],
              if ('${run['status']}' == 'approved' && app.can('payroll.pay')) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _payPayroll(id);
                  },
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Mark Paid'),
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

  Future<void> _approvePayroll(int id) async {
    try {
      await ref
          .read(apiClientProvider)
          .post(ApiPaths.payrollApprove(id), data: const {});
      if (mounted) {
        setState(() {
          message = 'Payroll #$id approved.';
          refresh++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _discardPayroll(int id) async {
    final reason = TextEditingController(
      text: 'UAT cleanup: legacy or invalid payroll draft',
    );
    String? validation;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Discard Payroll #$id?'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Only an unposted draft can be discarded. '
                  'The backend records a full audit snapshot before deletion.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Reason'),
                ),
                if (validation != null) ...[
                  const SizedBox(height: 8),
                  Text(validation!),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().length < 5) {
                  setLocal(() => validation = 'Reason is required.');
                } else {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Discard Draft'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) {
      reason.dispose();
      return;
    }
    try {
      await ref.read(apiClientProvider).post(
        ApiPaths.payrollDiscard(id),
        data: {'reason': reason.text.trim()},
      );
      if (mounted) {
        setState(() {
          message = 'Payroll #$id discarded.';
          refresh++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    } finally {
      reason.dispose();
    }
  }

  Future<void> _payPayroll(int id) async {
    final app = ref.read(appStateProvider);
    final paymentDate = TextEditingController(text: app.businessDate);
    int? paymentAccountId;
    String? validation;
    try {
      final raw = await ref
          .read(apiClientProvider)
          .get(ApiPaths.financeBootstrap);
      final data = Map<String, dynamic>.from(raw as Map);
      final accounts = ((data['accounts'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((account) {
            final subtype = '${account['subtype'] ?? ''}'.toLowerCase();
            return {'cash', 'bank', 'upi'}.contains(subtype);
          })
          .toList();

      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text('Pay Payroll #$id'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: paymentAccountId,
                    decoration: const InputDecoration(
                      labelText: 'Payment Account',
                    ),
                    items: accounts
                        .map(
                          (account) => DropdownMenuItem<int>(
                            value: int.tryParse('${account['id']}'),
                            child: Text(
                              '${account['code'] ?? ''} · ${account['name'] ?? ''}',
                            ),
                          ),
                        )
                        .where((item) => item.value != null)
                        .toList(),
                    onChanged: (value) =>
                        setLocal(() => paymentAccountId = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: paymentDate,
                    decoration: const InputDecoration(
                      labelText: 'Payment Date (YYYY-MM-DD)',
                    ),
                  ),
                  if (validation != null) ...[
                    const SizedBox(height: 8),
                    Text(validation!),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final date = paymentDate.text.trim();
                  final validDate =
                      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) &&
                      DateTime.tryParse(date) != null;
                  if (paymentAccountId == null) {
                    setLocal(() => validation = 'Payment account is required.');
                  } else if (!validDate) {
                    setLocal(
                      () => validation =
                          'Payment date must be a valid YYYY-MM-DD date.',
                    );
                  } else {
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('Mark Paid'),
              ),
            ],
          ),
        ),
      );
      if (ok != true || paymentAccountId == null) return;

      await ref.read(apiClientProvider).post(
        ApiPaths.payrollPay(id),
        data: {
          'payment_account_id': paymentAccountId,
          'payment_date': paymentDate.text.trim(),
        },
      );
      if (mounted) {
        setState(() {
          message = 'Payroll #$id marked paid.';
          refresh++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    } finally {
      paymentDate.dispose();
    }
  }

  Future<void> _createTarget() async {
    final app = ref.read(appStateProvider);
    if (app.currentBranchId == null) return;
    final employee = TextEditingController();
    final points = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Performance Target'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: employee,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Employee ID'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: points,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Target Points'),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(apiClientProvider).post(
          ApiPaths.performanceTargets,
          data: {
            'branch_id': app.currentBranchId,
            'employee_id': int.parse(employee.text.trim()),
            'target_points': double.parse(points.text.trim()),
            'period_start': app.businessMonthStart,
            'period_end': app.businessDate,
          },
        );
        if (mounted) {
          setState(() {
            message = 'Performance target created.';
            refresh++;
          });
        }
      } catch (e) {
        if (mounted) setState(() => message = UiError.message(e));
      }
    }
    employee.dispose();
    points.dispose();
  }

  Future<void> _targetAction(Map<String, dynamic> row) async {
    final app = ref.read(appStateProvider);
    if (!app.can('performance.manage')) return;
    final id = int.parse('${row['id']}');
    final status = '${row['status'] ?? ''}'.trim().toLowerCase();
    if (status != 'draft') {
      if (mounted) {
        setState(() => message = 'Target #$id is already ${status.isEmpty ? 'processed' : status}.');
      }
      return;
    }

    final employee = '${row['employee_name'] ?? 'Employee #${row['employee_id'] ?? '—'}'}';
    final points = '${row['target_points'] ?? '0'}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Approve Target #$id'),
        content: Text(
          '$employee\nTarget Points: $points\n\nApproval is maker-checker protected. The creator cannot approve the same target.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.approval_outlined),
            label: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref
          .read(apiClientProvider)
          .post(ApiPaths.targetApprove(id), data: const {});
      if (mounted) {
        setState(() {
          message = 'Target #$id approved.';
          refresh++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }
}