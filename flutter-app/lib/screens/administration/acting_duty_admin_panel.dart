import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/business_datetime_field.dart';
import '../../widgets/module_workspace.dart';

class ActingDutyAdminPanel extends ConsumerStatefulWidget {
  const ActingDutyAdminPanel({super.key});

  @override
  ConsumerState<ActingDutyAdminPanel> createState() =>
      _ActingDutyAdminPanelState();
}

class _ActingDutyAdminPanelState extends ConsumerState<ActingDutyAdminPanel> {
  int _refresh = 0;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final branchId = app.currentBranchId;
    if (branchId == null) {
      return const Center(
        child: Text('Select an authorised branch to manage Acting Duty.'),
      );
    }

    return FutureBuilder<List<dynamic>>(
      key: ValueKey('acting-duty-$branchId-$_refresh'),
      future: Future.wait<dynamic>([
        api.get(ApiPaths.actingDelegations, query: {'branch_id': branchId}),
        api.get(ApiPaths.actingUnavailability, query: {'branch_id': branchId}),
        api.get(ApiPaths.actingEmployees, query: {'branch_id': branchId}),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(UiError.message(snapshot.error!)));
        }
        final values = snapshot.data ?? const [];
        final delegationData = values[0] is Map
            ? Map<String, dynamic>.from(values[0] as Map)
            : <String, dynamic>{};
        final actions = ((delegationData['actions'] as List?) ?? const [])
            .map((e) => '$e')
            .toList();
        final delegations =
            ((delegationData['delegations'] as List?) ?? const [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
        final unavailable = (values[1] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final employees = (values[2] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_message != null) ...[
              ModuleMessageBanner(message: _message!),
              const SizedBox(height: 10),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: actions.isEmpty
                      ? null
                      : () => _createDelegation(app, employees, actions),
                  icon: const Icon(Icons.assignment_ind_outlined),
                  label: const Text('New Delegation'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _createUnavailability(app, employees),
                  icon: const Icon(Icons.event_busy_outlined),
                  label: const Text('Mark Unavailable'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Exact-Action Delegations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'A delegation grants only one action in one branch for a limited time. It does not change permanent roles, designations or branch authority.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (delegations.isEmpty)
              const Card(
                child: ListTile(
                  title: Text('No delegation records for this branch.'),
                ),
              )
            else
              for (final row in delegations)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.swap_horiz_rounded),
                    title: Text(_actionLabel('${row['action_code']}')),
                    subtitle: Text(
                      '${row['delegator_name'] ?? 'Delegator'} → ${row['delegate_name'] ?? 'Delegate'}\n'
                      '${row['starts_at']} → ${row['ends_at']} · ${row['reason'] ?? ''}',
                    ),
                    isThreeLine: true,
                    trailing: _canRevokeDelegation(row)
                        ? IconButton(
                            tooltip: 'Revoke delegation',
                            onPressed: () => _revoke(
                              ApiPaths.delegationRevoke(
                                int.parse('${row['id']}'),
                              ),
                              'Revoke Delegation',
                            ),
                            icon: const Icon(Icons.block_outlined),
                          )
                        : Chip(
                            label: Text(
                              '${row['effective_status'] ?? row['status'] ?? ''}',
                            ),
                          ),
                  ),
                ),
            const SizedBox(height: 18),
            Text(
              'Manual Unavailability',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'This marks temporary unavailability for fallback selection; attendance and approved leave remain server-owned signals.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (unavailable.isEmpty)
              const Card(
                child: ListTile(
                  title: Text('No unavailability records for this branch.'),
                ),
              )
            else
              for (final row in unavailable)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_busy_outlined),
                    title: Text('${row['employee_name'] ?? 'Employee'}'),
                    subtitle: Text(
                      '${row['starts_at']} → ${row['ends_at']}\n${row['reason'] ?? ''}',
                    ),
                    isThreeLine: true,
                    trailing: '${row['status']}' == 'active'
                        ? IconButton(
                            tooltip: 'Revoke unavailability',
                            onPressed: () => _revoke(
                              ApiPaths.unavailabilityRevoke(
                                int.parse('${row['id']}'),
                              ),
                              'Revoke Unavailability',
                            ),
                            icon: const Icon(Icons.event_available_outlined),
                          )
                        : Chip(
                            label: Text(
                              '${row['effective_status'] ?? row['status'] ?? ''}',
                            ),
                          ),
                  ),
                ),
          ],
        );
      },
    );
  }

  bool _canRevokeDelegation(Map<String, dynamic> row) =>
      row['can_revoke'] == true && '${row['status']}' == 'active';

  Future<void> _createDelegation(
    AppState app,
    List<Map<String, dynamic>> employees,
    List<String> actions,
  ) async {
    final branchId = app.currentBranchId;
    if (branchId == null) return;
    final selfId = int.tryParse('${app.employee['id']}') ?? 0;
    final canChooseDelegator = app.can('administration.access.manage');
    int? delegatorId = selfId > 0 ? selfId : null;
    int? delegateId;
    String? action = actions.isEmpty ? null : actions.first;
    final start = TextEditingController(text: _localDateTime(DateTime.now()));
    final end = TextEditingController(
      text: _localDateTime(DateTime.now().add(const Duration(days: 1))),
    );
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New Acting Duty Delegation'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canChooseDelegator) ...[
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: delegatorId,
                      decoration:
                          const InputDecoration(labelText: 'Delegator'),
                      items: employees
                          .map(
                            (e) => DropdownMenuItem(
                              value: int.parse('${e['id']}'),
                              child: Text(
                                '${e['full_name']} · ${e['employee_code']}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setLocal(() => delegatorId = value),
                    ),
                    const SizedBox(height: 10),
                  ],
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: delegateId,
                    decoration: const InputDecoration(labelText: 'Delegate'),
                    items: employees
                        .where(
                          (e) => int.tryParse('${e['id']}') != delegatorId,
                        )
                        .map(
                          (e) => DropdownMenuItem(
                            value: int.parse('${e['id']}'),
                            child: Text(
                              '${e['full_name']} · ${e['employee_code']}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setLocal(() => delegateId = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: action,
                    decoration:
                        const InputDecoration(labelText: 'Exact Action'),
                    items: actions
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(_actionLabel(value)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setLocal(() => action = value),
                  ),
                  const SizedBox(height: 10),
                  BusinessDateTimeField(
                    controller: start,
                    label: 'Starts At',
                  ),
                  const SizedBox(height: 10),
                  BusinessDateTimeField(
                    controller: end,
                    label: 'Ends At',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reason,
                    minLines: 2,
                    maxLines: 4,
                    decoration:
                        const InputDecoration(labelText: 'Business Reason'),
                  ),
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
              onPressed: () => Navigator.pop(
                context,
                delegatorId != null &&
                    delegateId != null &&
                    action != null &&
                    reason.text.trim().length >= 5,
              ),
              child: const Text('Create Delegation'),
            ),
          ],
        ),
      ),
    );
    final payload = {
      'branch_id': branchId,
      'delegator_employee_id': delegatorId,
      'delegate_employee_id': delegateId,
      'action_code': action,
      'starts_at': start.text.trim(),
      'ends_at': end.text.trim(),
      'reason': reason.text.trim(),
    };
    start.dispose();
    end.dispose();
    reason.dispose();
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).post(
        ApiPaths.actingDelegations,
        data: payload,
      );
      _reload('Acting Duty delegation created for the exact action and window.');
    } catch (e) {
      _reload(UiError.message(e), increment: false);
    }
  }

  Future<void> _createUnavailability(
    AppState app,
    List<Map<String, dynamic>> employees,
  ) async {
    final branchId = app.currentBranchId;
    if (branchId == null) return;
    final selfId = int.tryParse('${app.employee['id']}') ?? 0;
    final canChooseEmployee = app.can('administration.access.manage');
    int? employeeId = selfId > 0 ? selfId : null;
    final start = TextEditingController(text: _localDateTime(DateTime.now()));
    final end = TextEditingController(
      text: _localDateTime(DateTime.now().add(const Duration(days: 1))),
    );
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Mark Temporary Unavailability'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canChooseEmployee) ...[
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: employeeId,
                    decoration:
                        const InputDecoration(labelText: 'Employee'),
                    items: employees
                        .map(
                          (e) => DropdownMenuItem(
                            value: int.parse('${e['id']}'),
                            child: Text(
                              '${e['full_name']} · ${e['employee_code']}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setLocal(() => employeeId = value),
                  ),
                  const SizedBox(height: 10),
                ],
                BusinessDateTimeField(
                  controller: start,
                  label: 'Starts At',
                ),
                const SizedBox(height: 10),
                BusinessDateTimeField(
                  controller: end,
                  label: 'Ends At',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reason,
                  minLines: 2,
                  maxLines: 4,
                  decoration:
                      const InputDecoration(labelText: 'Reason'),
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
              onPressed: () => Navigator.pop(
                context,
                employeeId != null && reason.text.trim().length >= 5,
              ),
              child: const Text('Mark Unavailable'),
            ),
          ],
        ),
      ),
    );
    final payload = {
      'branch_id': branchId,
      'employee_id': employeeId,
      'starts_at': start.text.trim(),
      'ends_at': end.text.trim(),
      'reason': reason.text.trim(),
    };
    start.dispose();
    end.dispose();
    reason.dispose();
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).post(
        ApiPaths.actingUnavailability,
        data: payload,
      );
      _reload('Temporary unavailability recorded for fallback evaluation.');
    } catch (e) {
      _reload(UiError.message(e), increment: false);
    }
  }

  Future<void> _revoke(String path, String title) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: reason,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Revoke Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, reason.text.trim().length >= 5),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    final value = reason.text.trim();
    reason.dispose();
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).post(path, data: {'reason': value});
      _reload('$title completed.');
    } catch (e) {
      _reload(UiError.message(e), increment: false);
    }
  }

  void _reload(String message, {bool increment = true}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      if (increment) _refresh++;
    });
  }

  String _localDateTime(DateTime value) => BusinessDateTimeField.format(value);

  String _actionLabel(String action) => switch (action) {
        'daily.approve' => 'Approve Daily Order',
        'daily.issue' => 'Issue Daily Stock',
        'daily.final_post' => 'Final Post Daily Order',
        'workforce.leave.decision' => 'Decide Leave Request',
        _ => action,
      };
}
