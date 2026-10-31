import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/compensation_policy.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/records_list.dart';

class CompensationWorkspace extends ConsumerStatefulWidget {
  const CompensationWorkspace({super.key});

  @override
  ConsumerState<CompensationWorkspace> createState() =>
      _CompensationWorkspaceState();
}

class _CompensationWorkspaceState
    extends ConsumerState<CompensationWorkspace> {
  int _refresh = 0;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final tabs = <(String, Widget)>[];

    if (app.canAny(const ['salary.view', 'salary.manage', 'salary.approve'])) {
      tabs.add((
        'Salary Structures',
        Column(
          children: [
            if (app.can('salary.manage'))
              _ActionBar(
                child: FilledButton.icon(
                  onPressed: _createSalaryStructure,
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('New Salary Structure'),
                ),
              ),
            Expanded(
              child: AsyncPanel(
                key: ValueKey('salary-${app.currentBranchId}-$_refresh'),
                future: app.currentBranchId == null
                    ? Future.value(const <dynamic>[])
                    : api.get(
                        ApiPaths.salaryStructures,
                        query: {'branch_id': app.currentBranchId},
                      ),
                emptyMessage: 'No salary structures found for this branch.',
                builder: (context, data) => RecordsList(
                  recordType: 'salary_structure',
                  rows: _rows(data),
                  onTap: app.can('salary.approve')
                      ? _salaryStructureAction
                      : null,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    if (app.canAny(const [
      'rewards.view',
      'rewards.manage',
      'rewards.approve',
      'rewards.pay',
    ])) {
      tabs.add((
        'Rewards / Penalties',
        Column(
          children: [
            if (app.can('rewards.manage'))
              _ActionBar(
                child: FilledButton.icon(
                  onPressed: _createReward,
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('New Reward / Penalty'),
                ),
              ),
            Expanded(
              child: AsyncPanel(
                key: ValueKey('reward-${app.currentBranchId}-$_refresh'),
                future: app.currentBranchId == null
                    ? Future.value(const <dynamic>[])
                    : api.get(
                        ApiPaths.performanceRewards,
                        query: {'branch_id': app.currentBranchId},
                      ),
                emptyMessage: 'No reward or penalty records found for this branch.',
                builder: (context, data) => RecordsList(
                  recordType: 'reward_adjustment',
                  rows: _rows(data),
                  onTap: app.canAny(const ['rewards.approve', 'rewards.pay'])
                      ? _rewardAction
                      : null,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    if (app.canAny(const [
      'promotion.view',
      'promotion.request',
      'promotion.approve',
    ])) {
      tabs.add((
        'Promotions / Increments',
        Column(
          children: [
            if (app.can('promotion.request'))
              _ActionBar(
                child: FilledButton.icon(
                  onPressed: _createPromotionRequest,
                  icon: const Icon(Icons.trending_up_outlined),
                  label: const Text('New Promotion / Increment'),
                ),
              ),
            Expanded(
              child: AsyncPanel(
                key: ValueKey('promotion-${app.currentBranchId}-$_refresh'),
                future: app.currentBranchId == null
                    ? Future.value(const <dynamic>[])
                    : api.get(
                        ApiPaths.performancePromotions,
                        query: {'branch_id': app.currentBranchId},
                      ),
                emptyMessage:
                    'No promotion or increment requests found for this branch.',
                builder: (context, data) => RecordsList(
                  recordType: 'promotion_request',
                  rows: _rows(data),
                  onTap: app.can('promotion.approve')
                      ? _promotionAction
                      : null,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    if (tabs.isEmpty) {
      return const Center(
        child: Text('No authorised compensation functions.'),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          Material(
            child: TabBar(
              isScrollable: true,
              tabs: [for (final tab in tabs) Tab(text: tab.$1)],
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_message!),
              ),
            ),
          Expanded(child: TabBarView(children: [for (final tab in tabs) tab.$2])),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    if (data is Map) {
      for (final key in const ['items', 'rows', 'data']) {
        final value = data[key];
        if (value is List) {
          return value
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
        }
      }
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> _branchEmployees() async {
    final app = ref.read(appStateProvider);
    if (app.currentBranchId == null) return const [];
    final raw = await ref.read(apiClientProvider).get(
      ApiPaths.employees,
      query: {'branch_id': app.currentBranchId},
    );
    return _rows(raw)
        .where(
          (row) =>
              '${row['employee_status']}'.trim().toLowerCase() == 'active',
        )
        .toList();
  }

  Future<void> _createSalaryStructure() async {
    final app = ref.read(appStateProvider);
    try {
      final employees = await _branchEmployees();
      if (!mounted) return;
      int? employeeId;
      final basic = TextEditingController();
      final hra = TextEditingController(text: '0');
      final allowance = TextEditingController(text: '0');
      final other = TextEditingController(text: '0');
      final effectiveFrom = TextEditingController(text: app.businessDate);
      final reason = TextEditingController();
      String? validation;

      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('New Salary Structure'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: employeeId,
                      decoration: const InputDecoration(labelText: 'Employee'),
                      items: employees
                          .map(
                            (e) => DropdownMenuItem<int>(
                              value: int.tryParse('${e['id']}'),
                              child: Text(
                                '${e['employee_code'] ?? ''} · ${e['display_name'] ?? e['full_name'] ?? ''}',
                              ),
                            ),
                          )
                          .where((item) => item.value != null)
                          .toList(),
                      onChanged: (value) => setLocal(() => employeeId = value),
                    ),
                    const SizedBox(height: 10),
                    _moneyField(basic, 'Monthly Basic'),
                    const SizedBox(height: 10),
                    _moneyField(hra, 'HRA'),
                    const SizedBox(height: 10),
                    _moneyField(allowance, 'Fixed Allowance'),
                    const SizedBox(height: 10),
                    _moneyField(other, 'Other Fixed'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: effectiveFrom,
                      decoration: const InputDecoration(
                        labelText: 'Effective From (YYYY-MM-DD)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: reason,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Change Reason',
                      ),
                    ),
                    if (validation != null) ...[
                      const SizedBox(height: 10),
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
                  final draft = SalaryStructureDraft(
                    monthlyBasic: double.tryParse(basic.text.trim()) ?? -1,
                    hra: double.tryParse(hra.text.trim()) ?? -1,
                    fixedAllowance:
                        double.tryParse(allowance.text.trim()) ?? -1,
                    otherFixed: double.tryParse(other.text.trim()) ?? -1,
                  );
                  final error = CompensationPolicy.validateSalaryStructure(draft);
                  if (employeeId == null) {
                    setLocal(() => validation = 'Employee is required.');
                  } else if (!CompensationPolicy.validEffectiveDate(
                    effectiveFrom.text,
                  )) {
                    setLocal(
                      () => validation =
                          'Effective date must be a valid YYYY-MM-DD date.',
                    );
                  } else if (reason.text.trim().isEmpty) {
                    setLocal(() => validation = 'Change reason is required.');
                  } else if (error != null) {
                    setLocal(() => validation = error);
                  } else {
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('Create Draft'),
              ),
            ],
          ),
        ),
      );

      if (ok == true && employeeId != null) {
        await ref.read(apiClientProvider).post(
          ApiPaths.salaryStructures,
          data: {
            'branch_id': app.currentBranchId,
            'employee_id': employeeId,
            'monthly_basic': double.parse(basic.text.trim()),
            'hra': double.parse(hra.text.trim()),
            'fixed_allowance': double.parse(allowance.text.trim()),
            'other_fixed': double.parse(other.text.trim()),
            'effective_from': effectiveFrom.text.trim(),
            'change_reason': reason.text.trim(),
          },
        );
        _success('Salary structure draft created.');
      }

      basic.dispose();
      hra.dispose();
      allowance.dispose();
      other.dispose();
      effectiveFrom.dispose();
      reason.dispose();
    } catch (e) {
      _failure(e);
    }
  }

  Future<void> _salaryStructureAction(Map<String, dynamic> row) async {
    if ('${row['status']}'.toLowerCase() != 'draft') return;
    final id = int.tryParse('${row['id']}');
    if (id == null) return;
    final approved = await _confirm(
      title: 'Approve salary structure?',
      body:
          'Approval creates an effective historical version. Existing payroll history will not be rewritten.',
      confirmText: 'Approve',
    );
    if (approved == true) {
      await _post(ApiPaths.salaryStructureApprove(id), const {});
      _success('Salary structure approved.');
    }
  }

  Future<void> _createReward() async {
    final app = ref.read(appStateProvider);
    try {
      final employees = await _branchEmployees();
      if (!mounted) return;
      int? employeeId;
      RewardAdjustmentKind kind = RewardAdjustmentKind.incentive;
      final amount = TextEditingController(text: '0');
      final points = TextEditingController(text: '0');
      final reason = TextEditingController();
      String? validation;

      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Reward / Penalty'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: employeeId,
                      decoration: const InputDecoration(labelText: 'Employee'),
                      items: employees
                          .map(
                            (e) => DropdownMenuItem<int>(
                              value: int.tryParse('${e['id']}'),
                              child: Text(
                                '${e['employee_code'] ?? ''} · ${e['display_name'] ?? e['full_name'] ?? ''}',
                              ),
                            ),
                          )
                          .where((item) => item.value != null)
                          .toList(),
                      onChanged: (value) => setLocal(() => employeeId = value),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<RewardAdjustmentKind>(
                      initialValue: kind,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: RewardAdjustmentKind.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(_kindLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setLocal(() => kind = value ?? kind),
                    ),
                    const SizedBox(height: 10),
                    _moneyField(amount, 'Amount (positive magnitude)'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: points,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Points'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: reason,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Reason'),
                    ),
                    if (validation != null) ...[
                      const SizedBox(height: 10),
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
                  final error = CompensationPolicy.validateRewardAdjustment(
                    kind: kind,
                    amount: double.tryParse(amount.text.trim()) ?? double.nan,
                    points: double.tryParse(points.text.trim()) ?? double.nan,
                    reason: reason.text,
                  );
                  if (employeeId == null) {
                    setLocal(() => validation = 'Employee is required.');
                  } else if (error != null) {
                    setLocal(() => validation = error);
                  } else {
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      );

      if (ok == true && employeeId != null) {
        await ref.read(apiClientProvider).post(
          ApiPaths.performanceRewards,
          data: {
            'branch_id': app.currentBranchId,
            'employee_id': employeeId,
            'adjustment_type': _kindKey(kind),
            'amount': double.parse(amount.text.trim()).abs(),
            'points': double.parse(points.text.trim()),
            'reason': reason.text.trim(),
          },
        );
        _success('Reward / penalty submitted for approval.');
      }

      amount.dispose();
      points.dispose();
      reason.dispose();
    } catch (e) {
      _failure(e);
    }
  }

  Future<void> _rewardAction(Map<String, dynamic> row) async {
    final app = ref.read(appStateProvider);
    final id = int.tryParse('${row['id']}');
    final status = '${row['status']}'.toLowerCase();
    if (id == null) return;

    if (status == 'pending' && app.can('rewards.approve')) {
      final decision = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reward / Penalty Decision'),
          content: Text(
            '${row['employee_name'] ?? row['employee_id'] ?? ''} · ${row['reason'] ?? ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'rejected'),
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'approved'),
              child: const Text('Approve'),
            ),
          ],
        ),
      );
      if (decision != null) {
        await _post(ApiPaths.rewardDecision(id), {'decision': decision});
        _success('Reward / penalty $decision.');
      }
      return;
    }

    if (status == 'approved' && app.can('rewards.pay')) {
      final pay = await _confirm(
        title: 'Mark reward / penalty settled?',
        body:
            'The backend must keep this settlement idempotent and linked to payroll/accounting.',
        confirmText: 'Settle',
      );
      if (pay == true) {
        await _post(ApiPaths.rewardPay(id), const {});
        _success('Reward / penalty settled.');
      }
    }
  }

  Future<void> _createPromotionRequest() async {
    final app = ref.read(appStateProvider);
    try {
      final employees = await _branchEmployees();
      final rawDesignations =
          await ref.read(apiClientProvider).get(ApiPaths.designations);
      final designations = _rows(rawDesignations);
      if (!mounted) return;
      int? employeeId;
      Map<String, dynamic>? selectedEmployee;
      String? nextDesignation;
      final effectiveFrom = TextEditingController(text: app.businessDate);
      final increment = TextEditingController(text: '0');
      final reason = TextEditingController();
      String? validation;

      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) {
            final currentDesignation = _designationCode(selectedEmployee);
            final availableDesignations = designations
                .where(
                  (e) => '${e['status']}'.trim().toLowerCase() == 'active',
                )
                .where(
                  (e) => !CompensationPolicy.sameDesignation(
                    currentDesignation,
                    '${e['code'] ?? ''}',
                  ),
                )
                .toList();
            return AlertDialog(
              title: const Text('Promotion / Increment Request'),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: employeeId,
                        decoration: const InputDecoration(labelText: 'Employee'),
                        items: employees
                            .map(
                              (e) => DropdownMenuItem<int>(
                                value: int.tryParse('${e['id']}'),
                                child: Text(
                                  '${e['employee_code'] ?? ''} · ${e['display_name'] ?? e['full_name'] ?? ''}',
                                ),
                              ),
                            )
                            .where((item) => item.value != null)
                            .toList(),
                        onChanged: (value) => setLocal(() {
                          employeeId = value;
                          selectedEmployee = _employeeById(employees, value);
                          if (nextDesignation != null &&
                              CompensationPolicy.sameDesignation(
                                _designationCode(selectedEmployee),
                                nextDesignation!,
                              )) {
                            nextDesignation = null;
                          }
                        }),
                      ),
                      if (currentDesignation.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Current designation: $currentDesignation',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: nextDesignation,
                        decoration: const InputDecoration(
                          labelText: 'Next Designation',
                        ),
                        items: availableDesignations
                            .map(
                              (e) => DropdownMenuItem<String>(
                                value: '${e['code']}',
                                child: Text('${e['code']} · ${e['name']}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setLocal(() => nextDesignation = value),
                      ),
                      const SizedBox(height: 10),
                      _moneyField(increment, 'Monthly Increment Amount'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: effectiveFrom,
                        decoration: const InputDecoration(
                          labelText: 'Effective From (YYYY-MM-DD)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: reason,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Reason'),
                      ),
                      const SizedBox(height: 10),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Eligibility is a server-side preflight. This request never grants Reporting Manager, Branch Authority, Role, or capability access automatically.',
                        ),
                      ),
                      if (validation != null) ...[
                        const SizedBox(height: 10),
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
                    final incrementValue =
                        double.tryParse(increment.text.trim()) ?? double.nan;
                    final error = CompensationPolicy.validatePromotionRequest(
                      currentDesignation: currentDesignation,
                      nextDesignation: nextDesignation ?? '',
                      incrementAmount: incrementValue,
                      effectiveFrom: effectiveFrom.text,
                      reason: reason.text,
                    );
                    if (employeeId == null) {
                      setLocal(() => validation = 'Employee is required.');
                    } else if (error != null) {
                      setLocal(() => validation = error);
                    } else {
                      Navigator.pop(context, true);
                    }
                  },
                  child: const Text('Request'),
                ),
              ],
            );
          },
        ),
      );

      if (ok == true && employeeId != null && nextDesignation != null) {
        await ref.read(apiClientProvider).post(
          ApiPaths.performancePromotions,
          data: {
            'branch_id': app.currentBranchId,
            'employee_id': employeeId,
            'next_designation_code': nextDesignation,
            'monthly_increment_amount':
                double.parse(increment.text.trim()).abs(),
            'effective_from': effectiveFrom.text.trim(),
            'reason': reason.text.trim(),
          },
        );
        _success('Promotion / increment request submitted.');
      }

      effectiveFrom.dispose();
      increment.dispose();
      reason.dispose();
    } catch (e) {
      _failure(e);
    }
  }

  Future<void> _promotionAction(Map<String, dynamic> row) async {
    if ('${row['status']}'.toLowerCase() != 'pending') return;
    final id = int.tryParse('${row['id']}');
    if (id == null) return;
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Promotion / Increment Decision'),
        content: const Text(
          'Approval may create only the controlled designation and/or effective salary version. Reporting Manager, Branch Authority, Roles, and capabilities remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'rejected'),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'approved'),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (decision != null) {
      await _post(ApiPaths.promotionDecision(id), {'decision': decision});
      _success('Promotion / increment $decision.');
    }
  }

  static Map<String, dynamic>? _employeeById(
    List<Map<String, dynamic>> employees,
    int? employeeId,
  ) {
    if (employeeId == null) return null;
    for (final employee in employees) {
      if (int.tryParse('${employee['id']}') == employeeId) return employee;
    }
    return null;
  }

  static String _designationCode(Map<String, dynamic>? employee) {
    if (employee == null) return '';
    for (final key in const ['designation_code', 'primary_designation_code']) {
      final value = '${employee[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Widget _moneyField(TextEditingController controller, String label) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      );

  Future<void> _post(String path, Map<String, dynamic> data) async {
    try {
      await ref.read(apiClientProvider).post(path, data: data);
    } catch (e) {
      _failure(e);
      rethrow;
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmText,
  }) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmText),
            ),
          ],
        ),
      );

  void _success(String value) {
    if (!mounted) return;
    setState(() {
      _message = value;
      _refresh++;
    });
  }

  void _failure(Object error) {
    if (!mounted) return;
    setState(() => _message = UiError.message(error));
  }

  static String _kindKey(RewardAdjustmentKind kind) => switch (kind) {
        RewardAdjustmentKind.incentive => 'incentive',
        RewardAdjustmentKind.bonus => 'bonus',
        RewardAdjustmentKind.recognition => 'recognition',
        RewardAdjustmentKind.penalty => 'penalty',
        RewardAdjustmentKind.pointsAdjustment => 'points_adjustment',
      };

  static String _kindLabel(RewardAdjustmentKind kind) => switch (kind) {
        RewardAdjustmentKind.incentive => 'Incentive',
        RewardAdjustmentKind.bonus => 'Bonus',
        RewardAdjustmentKind.recognition => 'Recognition',
        RewardAdjustmentKind.penalty => 'Penalty',
        RewardAdjustmentKind.pointsAdjustment => 'Points Adjustment',
      };
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Align(alignment: Alignment.centerLeft, child: child),
      );
}
