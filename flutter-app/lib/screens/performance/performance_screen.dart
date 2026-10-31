import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/business_date_field.dart';
import '../../widgets/records_list.dart';
import '../../widgets/module_workspace.dart';

import 'payroll_policy_dialog.dart';

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
    // Salary structures, rewards and promotions remain design-contract work
    // until backend routes, persistence and server capabilities are implemented.
    // Do not expose an interactive UAT workflow that can only fail at runtime.
    if (app.canAny(const [
      'payroll.salary.view',
      'payroll.salary.manage',
      'payroll.salary.approve',
    ])) {
      tabs.add((
        'Salary',
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.history_toggle_off_outlined),
                title: const Text('Salary Revisions'),
                subtitle: const Text(
                  'View authorised salary history and create or review revisions according to your salary permissions.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _salaryRevisionWorkspace,
              ),
            ),
          ],
        ),
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
            if (app.canAny(const [
              'payroll.generate',
              'payroll.approve',
            ]))
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (app.can('payroll.generate'))
                        FilledButton.icon(
                          onPressed: _generate,
                          icon: const Icon(Icons.calculate_outlined),
                          label: const Text('Generate Payroll Draft'),
                        ),
                      if (app.can('payroll.approve'))
                        OutlinedButton.icon(
                          onPressed: _payrollPolicy,
                          icon: const Icon(Icons.policy_outlined),
                          label: const Text('Payroll Policy'),
                        ),
                    ],
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

  Future<void> _payrollPolicy() async {
    final app = ref.read(appStateProvider);
    try {
      final result = await showPayrollPolicyDialog(
        context,
        ref,
        canManage: app.can('administration.access.manage'),
      );
      if (result != null && mounted) {
        setState(() {
          message = result;
          refresh++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _salaryRevisionWorkspace() async {
    final app = ref.read(appStateProvider);
    final branchId = app.currentBranchId;
    if (branchId == null) return;
    try {
      final employees = (await ref.read(apiClientProvider).get(
        ApiPaths.salaryEmployees,
        query: {'branch_id': branchId},
      ) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (employees.isEmpty) {
        throw const FormatException(
          'No active employee is available in this branch.',
        );
      }

      int? employeeId;
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setLocal) => Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Salary Revision History',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select an employee to view the audited salary revision timeline.',
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: employeeId,
                  decoration: const InputDecoration(
                    labelText: 'Employee',
                    prefixIcon: Icon(Icons.person_search_outlined),
                  ),
                  items: employees
                      .map(
                        (employee) => DropdownMenuItem(
                          value: int.parse("${employee['id']}"),
                          child: Text(
                            "${employee['full_name']} · ${employee['employee_code']}",
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setLocal(() => employeeId = value),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: employeeId == null
                            ? null
                            : () => Navigator.pop(
                                  sheetContext,
                                  employees.firstWhere(
                                    (employee) =>
                                        int.parse("${employee['id']}") ==
                                        employeeId,
                                  ),
                                ),
                        child: const Text('Open History'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      await _showSalaryHistory(selected);
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _showSalaryHistory(Map<String, dynamic> employee) async {
    final api = ref.read(apiClientProvider);
    final app = ref.read(appStateProvider);
    final employeeId = int.parse("${employee['id']}");
    final currentActorId = int.tryParse("${app.employee['id']}") ?? 0;

    Future<List<Map<String, dynamic>>> load() async =>
        (await api.get(ApiPaths.salaryRevisions(employeeId)) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    var future = load();
    String? localMessage;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> requestRevision() async {
            if (employeeId == currentActorId) {
              setLocal(
                () => localMessage =
                    'Your own salary revision must be created by another authorised maker.',
              );
              return;
            }

            final salary = TextEditingController(
              text: "${employee['monthly_salary'] ?? ''}",
            );
            final effective = TextEditingController(text: app.businessDate);
            final reason = TextEditingController();
            String? validation;

            final ok = await showDialog<bool>(
              context: dialogContext,
              builder: (context) => StatefulBuilder(
                builder: (context, setForm) => AlertDialog(
                  title: Text(
                    "New Salary Revision · ${employee['full_name'] ?? 'Employee'}",
                  ),
                  content: SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: salary,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Monthly Salary',
                            ),
                          ),
                          const SizedBox(height: 10),
                          BusinessDateField(
                            controller: effective,
                            label: 'Effective From',
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: reason,
                            minLines: 2,
                            maxLines: 4,
                            decoration:
                                const InputDecoration(labelText: 'Reason'),
                          ),
                          if (validation != null) ...[
                            const SizedBox(height: 8),
                            Text(validation!),
                          ],
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final amount = double.tryParse(salary.text.trim());
                        final date = effective.text.trim();
                        final parsedDate = DateTime.tryParse(date);
                        if (amount == null || amount <= 0) {
                          setForm(
                            () => validation =
                                'Monthly salary must be positive.',
                          );
                        } else if (!RegExp(r'^\d{4}-\d{2}-\d{2}$')
                                .hasMatch(date) ||
                            parsedDate == null) {
                          setForm(
                            () => validation =
                                'Effective date must be a valid YYYY-MM-DD date.',
                          );
                        } else if (reason.text.trim().length < 5) {
                          setForm(
                            () => validation =
                                'Reason must contain at least 5 characters.',
                          );
                        } else {
                          Navigator.pop(context, true);
                        }
                      },
                      child: const Text('Submit Revision'),
                    ),
                  ],
                ),
              ),
            );

            final payload = {
              'monthly_salary': double.tryParse(salary.text.trim()),
              'effective_from': effective.text.trim(),
              'reason': reason.text.trim(),
            };
            salary.dispose();
            effective.dispose();
            reason.dispose();
            if (ok != true) return;

            try {
              await api.post(
                ApiPaths.salaryRevisions(employeeId),
                data: payload,
              );
              setLocal(() {
                localMessage =
                    'Salary revision submitted for independent approval.';
                future = load();
              });
            } catch (e) {
              setLocal(() => localMessage = UiError.message(e));
            }
          }

          Future<void> reviewRevision(
            Map<String, dynamic> revision,
            bool approve,
          ) async {
            final revisionId = int.tryParse("${revision['id']}");
            if (revisionId == null) return;
            final action = approve ? 'Approve' : 'Reject';

            final confirmed = await showDialog<bool>(
              context: dialogContext,
              builder: (context) => AlertDialog(
                title: Text('$action Salary Revision?'),
                content: Text(
                  "${employee['full_name'] ?? 'Employee'} · "
                  "${revision['monthly_salary'] ?? ''} from "
                  "${revision['effective_from'] ?? ''}\n\n"
                  'This review is maker-checker protected and cannot be performed by the revision creator or the employee.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(action),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;

            try {
              await api.post(
                ApiPaths.salaryRevisionReview(revisionId),
                data: {'approve': approve},
              );
              setLocal(() {
                localMessage = approve
                    ? 'Salary revision approved.'
                    : 'Salary revision rejected.';
                future = load();
              });
            } catch (e) {
              setLocal(() => localMessage = UiError.message(e));
            }
          }

          return FractionallySizedBox(
            heightFactor: .94,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.currency_rupee_rounded),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Salary History · ${employee['full_name'] ?? 'Employee'}",
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              "${employee['employee_code'] ?? ''} · Current salary ${employee['monthly_salary'] ?? '—'}",
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                if (localMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: ModuleMessageBanner(message: localMessage!),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                  child: FilledButton.icon(
                    onPressed: employeeId == currentActorId ||
                            !app.can('payroll.salary.manage')
                        ? null
                        : requestRevision,
                    icon: const Icon(Icons.add_card_outlined),
                    label: const Text('New Salary Revision'),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(UiError.message(snapshot.error!)),
                        );
                      }
                      final rows = snapshot.data ?? const [];
                      if (rows.isEmpty) {
                        return const Center(
                          child: Text('No salary history is available.'),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          final status =
                              "${row['status'] ?? ''}".toLowerCase();
                          final creatorId =
                              int.tryParse("${row['created_by']}") ?? 0;
                          final canReview = status == 'pending' &&
                              app.can('payroll.salary.approve') &&
                              creatorId != currentActorId &&
                              employeeId != currentActorId;

                          return Card(
                            child: ListTile(
                              leading:
                                  const Icon(Icons.currency_rupee_rounded),
                              title: Text(
                                "${row['monthly_salary'] ?? '—'} · ${row['effective_from'] ?? '—'}",
                              ),
                              subtitle: Text(
                                "${row['reason'] ?? ''} · ${BusinessFormat.status(status)}",
                              ),
                              trailing: canReview
                                  ? Wrap(
                                      spacing: 2,
                                      children: [
                                        IconButton(
                                          tooltip: 'Approve revision',
                                          onPressed: () =>
                                              reviewRevision(row, true),
                                          icon: const Icon(
                                            Icons.check_circle_outline,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Reject revision',
                                          onPressed: () =>
                                              reviewRevision(row, false),
                                          icon:
                                              const Icon(Icons.cancel_outlined),
                                        ),
                                      ],
                                    )
                                  : Chip(
                                      label:
                                          Text(BusinessFormat.status(status)),
                                    ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

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
              Text('Status: ${BusinessFormat.status(run['status'])}'),
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
                  BusinessDateField(
                    controller: paymentDate,
                    label: 'Payment Date',
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
    final branchId = app.currentBranchId;
    if (branchId == null) return;
    final points = TextEditingController();
    try {
      final rawEmployees = await ref.read(apiClientProvider).get(
        ApiPaths.performanceTargetEmployees,
        query: {'branch_id': branchId},
      );
      final employees = (rawEmployees as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      if (employees.isEmpty) {
        setState(() => message = 'No eligible employees in your reporting scope.');
        return;
      }

      int? employeeId;
      double? targetPoints;
      String? validation;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('New Performance Target'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: employeeId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Employee'),
                    items: employees
                        .map(
                          (employee) => DropdownMenuItem<int>(
                            value: int.parse('${employee['id']}'),
                            child: Text(
                              '${employee['full_name']} · '
                              '${employee['employee_code']} · '
                              '${employee['designation_code']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setLocal(() {
                      employeeId = value;
                      validation = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: points,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Target Points'),
                    onChanged: (_) => setLocal(() => validation = null),
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
                  final parsed = double.tryParse(points.text.trim());
                  if (employeeId == null) {
                    setLocal(() => validation = 'Select an employee.');
                  } else if (parsed == null || !parsed.isFinite || parsed < 0) {
                    setLocal(
                      () => validation =
                          'Target points must be a valid non-negative number.',
                    );
                  } else {
                    targetPoints = parsed;
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      );
      if (ok != true || employeeId == null || targetPoints == null) return;

      await ref.read(apiClientProvider).post(
        ApiPaths.performanceTargets,
        data: {
          'branch_id': branchId,
          'employee_id': employeeId,
          'target_points': targetPoints,
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
    } finally {
      points.dispose();
    }
  }

  Future<void> _targetAction(Map<String, dynamic> row) async {
    final app = ref.read(appStateProvider);
    if (!app.can('performance.manage')) return;
    final id = int.parse('${row['id']}');
    final status = '${row['status'] ?? ''}'.trim().toLowerCase();
    if (status != 'draft') {
      if (mounted) {
        setState(() => message = 'Target #$id is already ${BusinessFormat.status(status.isEmpty ? 'processed' : status)}.');
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