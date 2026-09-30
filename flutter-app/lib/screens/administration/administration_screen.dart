import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';
import '../../widgets/module_workspace.dart';
import 'acting_duty_admin_panel.dart';

class AdministrationScreen extends ConsumerStatefulWidget {
  const AdministrationScreen({super.key});
  @override
  ConsumerState<AdministrationScreen> createState() =>
      _AdministrationScreenState();
}

class _AdministrationScreenState extends ConsumerState<AdministrationScreen> {
  int refresh = 0;
  String? message;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final tabs = <(String, Widget)>[];
    if (app.canAny(const [
      'finance.reversal.create',
      'finance.reversal.approve',
    ])) {
      tabs.add((
        'Reversals',
        AsyncPanel(
          key: ValueKey('reversals-$refresh'),
          future: api.get(ApiPaths.reversals),
          emptyMessage: 'No reversal requests.',
          builder: (context, data) => RecordsList(
            recordType: 'reversal',
            rows: _rows(data),
            onTap: _reversalAction,
          ),
        ),
      ));
    }
    if (app.can('administration.delegation.manage')) {
      tabs.add(('Acting Duty', const ActingDutyAdminPanel()));
    }
    if (app.can('administration.access.manage')) {
      tabs.add(('Access', _accessTab(app.currentBranchId)));
    }
    if (app.can('administration.audit.view')) {
      tabs.add((
        'Audit Log',
        AsyncPanel(
          key: ValueKey('audit-$refresh'),
          future: api.get(ApiPaths.audit),
          builder: (context, data) =>
              RecordsList(recordType: 'audit', rows: _rows(data)),
        ),
      ));
    }
    if (app.canAny(const [
      'administration.audit.view',
      'administration.access.manage',
    ])) {
      tabs.add(('System Health', _systemHealthTab()));
    }
    if (tabs.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No authorised administration functions.')),
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administration'),
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
                  title: 'Administration',
                  subtitle:
                      'Access control, acting duty, audit, reversals and system health.',
                  icon: Icons.admin_panel_settings_outlined,
                  contextLabel: app.currentBranchName,
                ),
              ),
              if (app.canAny(const [
                'administration.access.manage',
                'administration.delegation.manage',
              ]))
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
                  title: 'Control & Audit Workspace',
                  subtitle:
                      'Use only the administration functions authorised for your role.',
                ),
              ),
              Expanded(
                child: TabBarView(children: [for (final tab in tabs) tab.$2]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _systemHealthTab() {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    return AsyncPanel(
      key: ValueKey('system-health-$refresh'),
      future: api.get(ApiPaths.diagnostics),
      builder: (context, data) {
        final d = Map<String, dynamic>.from(data as Map);
        final attendance =
            Map<String, dynamic>.from((d['attendance'] as Map?) ?? const {});
        final daily =
            Map<String, dynamic>.from((d['daily_order'] as Map?) ?? const {});
        final payroll =
            Map<String, dynamic>.from((d['payroll'] as Map?) ?? const {});
        final access =
            Map<String, dynamic>.from((d['access'] as Map?) ?? const {});
        final organization =
            Map<String, dynamic>.from((d['organization'] as Map?) ?? const {});
        final accounting =
            Map<String, dynamic>.from((d['accounting'] as Map?) ?? const {});
        final stock =
            Map<String, dynamic>.from((d['stock'] as Map?) ?? const {});
        final status = '${d['status'] ?? 'unknown'}';
        final attention = status == 'attention';

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                  attention ? Icons.warning_amber_rounded : Icons.verified_outlined,
                ),
                title: Text(
                  attention ? 'Operational attention required' : 'System healthy',
                ),
                subtitle: Text('Checked at ${d['checked_at'] ?? '—'}'),
              ),
            ),
            const SizedBox(height: 10),
            _healthMetric(
              'Historical attendance without checkout',
              attendance['open_past_without_checkout'],
            ),
            _healthMetric(
              'Acknowledged missing checkout records',
              attendance['acknowledged_missing_checkout'],
            ),
            _healthMetric(
              'Stale Daily Order cycles',
              daily['stale_non_completed_cycles'],
            ),
            _healthMetric('Legacy payroll drafts', payroll['legacy_draft_runs']),
            _healthMetric(
              'Duplicate active role names',
              access['duplicate_active_role_names'],
            ),
            _healthMetric(
              'Duplicate active designation names',
              organization['duplicate_active_designation_names'],
            ),
            _healthMetric(
              'Unbalanced journals',
              accounting['unbalanced_journals'],
            ),
            _healthMetric('Negative stock balances', stock['negative_balances']),
            if (app.can('administration.access.manage')) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: attention ? _resolveSafeUatAnomalies : null,
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: const Text('Resolve Safe UAT Anomalies'),
              ),
              const SizedBox(height: 8),
              Text(
                'This does not invent checkout times. Missing historical checkouts '
                'are acknowledged as audited exceptions. Unposted stale Daily Orders '
                'are cancelled only when stock custody can be fully proven and returned.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _healthMetric(String label, dynamic value) => Card(
        child: ListTile(
          dense: true,
          title: Text(label),
          trailing: Text(
            '${value ?? 0}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );

  Future<void> _resolveSafeUatAnomalies() async {
    final reason = TextEditingController(
      text: 'UAT cleanup after verified diagnostics review',
    );
    String? validation;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Resolve safe UAT anomalies?'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'The backend will only resolve anomalies that pass strict safety '
                  'checks. Unsafe records are skipped rather than forced.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Audit reason'),
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
                if (reason.text.trim().length < 10) {
                  setLocal(
                    () => validation =
                        'Audit reason must contain at least 10 characters.',
                  );
                } else {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Resolve Safe Anomalies'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      reason.dispose();
      return;
    }
    try {
      final raw = await ref.read(apiClientProvider).post(
        ApiPaths.maintenanceCleanup,
        data: {
          'operation': 'resolve_uat_anomalies',
          'confirmation': 'RESOLVE_UAT_ANOMALIES',
          'reason': reason.text.trim(),
        },
      );
      final result = Map<String, dynamic>.from(raw as Map);
      if (mounted) {
        setState(() {
          message =
              'UAT cleanup complete · Attendance ${result['attendance_acknowledged'] ?? 0}, '
              'Daily ${result['daily_cycles_cancelled'] ?? 0}, '
              'Payroll ${result['payroll_drafts_discarded'] ?? 0}, '
              'Roles ${result['roles_deactivated'] ?? 0}, '
              'Designations ${result['designations_deactivated'] ?? 0}, '
              'Skipped ${result['daily_cycles_skipped'] ?? 0}.';
          refresh++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    } finally {
      reason.dispose();
    }
  }

  Widget _accessTab(int? branchId) {
    if (branchId == null) {
      return const Center(
        child: Text('Select an authorised branch to manage access.'),
      );
    }
    final api = ref.watch(apiClientProvider);
    return AsyncPanel(
      key: ValueKey('access-$refresh-$branchId'),
      future: Future.wait<dynamic>([
        api.get(ApiPaths.accessMatrix),
        api.get(ApiPaths.employees, query: {'branch_id': branchId}),
      ]),
      builder: (context, data) {
        final list = data as List;
        final matrix = Map<String, dynamic>.from(list[0] as Map);
        final roles = ((matrix['roles'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final caps = ((matrix['capabilities'] as List?) ?? const [])
            .map((e) => '$e')
            .toList();
        final employees = (list[1] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Roles & Permissions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _newRole,
                  icon: const Icon(Icons.add),
                  label: const Text('New Role'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...roles.map(
              (r) => Card(
                child: ListTile(
                  leading: const Icon(Icons.security_outlined),
                  title: Text('${r['name']}'),
                  subtitle: Text(
                    '${r['code']} · ${((r['capabilities'] as List?) ?? const []).length} permissions',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editRoleCapabilities(r, caps),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Employee Role Assignment',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Primary designation defaults apply automatically. Assigned roles add access and remain subject to branch authority.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ...employees.map(
              (e) => Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text('${e['full_name']}'),
                  subtitle: Text(
                    '${e['employee_code']} · ${e['designation_code']}',
                  ),
                  trailing: const Icon(Icons.manage_accounts_outlined),
                  onTap: () => _assignEmployeeAccess(e, roles, caps),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _rows(dynamic data) =>
      (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  void _reversalAction(Map<String, dynamic> row) {
    final app = ref.read(appStateProvider);
    final id = int.parse('${row['id']}');
    final status = '${row['status']}';
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text(
                '${row['source_type']} #${row['source_id']} · $status',
              ),
              subtitle: Text('${row['reason']}'),
            ),
            if (status == 'pending' && app.can('finance.reversal.approve')) ...[
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Approve Reversal'),
                onTap: () =>
                    _post(ApiPaths.reversalDecision(id), {'approve': true}),
              ),
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Reject Reversal'),
                onTap: () =>
                    _post(ApiPaths.reversalDecision(id), {'approve': false}),
              ),
            ],
            if (status == 'approved' && app.can('finance.reversal.approve'))
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Execute Reversal'),
                subtitle: const Text(
                  'Reverses the approved stock, outstanding, journal and audit-linked transaction chain.',
                ),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Execute approved reversal?'),
                      content: const Text(
                        'This will execute the approved stock, outstanding, journal and audit-linked reversal. Continue only for the reviewed and approved request.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Execute Reversal'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await _post(ApiPaths.reversalExecute(id), const {});
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _newRole() async {
    final code = TextEditingController();
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Role'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: const InputDecoration(labelText: 'Role Code'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Role Name'),
            ),
          ],
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
      await _post(
        ApiPaths.adminRoles,
        {
          'code': code.text.trim(),
          'name': name.text.trim(),
        },
        closeSheet: false,
      );
    }
    code.dispose();
    name.dispose();
  }

  Future<void> _editRoleCapabilities(
    Map<String, dynamic> role,
    List<String> allCaps,
  ) async {
    final selected = <String>{
      ...((role['capabilities'] as List?) ?? const []).map((e) => '$e'),
    };
    final reason = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Permissions · ${role['name']}'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: allCaps
                        .map(
                          (cap) => CheckboxListTile(
                            dense: true,
                            value: selected.contains(cap),
                            title: Text(cap),
                            onChanged: (v) => setLocal(
                              () => v == true
                                  ? selected.add(cap)
                                  : selected.remove(cap),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'Change Reason'),
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await _post(
        ApiPaths.roleCapabilities(int.parse('${role['id']}')),
        {
          'capabilities': selected.toList()..sort(),
          'reason': reason.text.trim(),
        },
        closeSheet: false,
      );
    }
    reason.dispose();
  }

  Future<void> _assignEmployeeAccess(
    Map<String, dynamic> employee,
    List<Map<String, dynamic>> roles,
    List<String> allCaps,
  ) async {
    final id = int.parse('${employee['id']}');
    try {
      final detail = Map<String, dynamic>.from(
        await ref.read(apiClientProvider).get(ApiPaths.employeeAccess(id))
            as Map,
      );
      final selectedRoles = <int>{
        ...((detail['roles'] as List?) ?? const []).map(
          (e) => int.parse('${(e as Map)['id']}'),
        ),
      };
      final originalRoles = {...selectedRoles};
      final defaults = <String>{
        ...((detail['designation_defaults'] as List?) ?? const []).map(
          (e) => '$e',
        ),
      };
      final effective = <String>{
        ...((detail['effective_capabilities'] as List?) ?? const []).map(
          (e) => '$e',
        ),
      };
      final overrides = ((detail['overrides'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final grants = <String>{
        ...overrides
            .where((e) => '${e['effect']}' == 'grant')
            .map((e) => '${e['capability']}'),
      };
      final denies = <String>{
        ...overrides
            .where((e) => '${e['effect']}' == 'deny')
            .map((e) => '${e['capability']}'),
      };
      final originalGrants = {...grants};
      final originalDenies = {...denies};
      final overrideSupported = detail.containsKey('designation_defaults');
      final reason = TextEditingController();
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text('Access · ${employee['full_name']}'),
            content: SizedBox(
              width: 680,
              height: MediaQuery.sizeOf(context).height * .68,
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Roles'),
                        Tab(text: 'Overrides'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          ListView(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                                child: Text(
                                  'Primary designation: ${employee['designation_code']} · default permissions apply automatically.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              ...roles.map((r) {
                                final rid = int.parse('${r['id']}');
                                return CheckboxListTile(
                                  value: selectedRoles.contains(rid),
                                  title: Text('${r['name']}'),
                                  subtitle: Text('${r['code']}'),
                                  onChanged: (v) => setLocal(
                                    () => v == true
                                        ? selectedRoles.add(rid)
                                        : selectedRoles.remove(rid),
                                  ),
                                );
                              }),
                            ],
                          ),
                          if (!overrideSupported)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Text(
                                  'Individual Grant/Deny overrides are unavailable for this employee access record.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          else
                            ListView.builder(
                              itemCount: allCaps.length,
                              itemBuilder: (context, index) {
                                final cap = allCaps[index];
                                final value = grants.contains(cap)
                                    ? 'grant'
                                    : denies.contains(cap)
                                        ? 'deny'
                                        : 'inherit';
                                return ListTile(
                                  dense: true,
                                  title: Text(_capLabel(cap)),
                                  subtitle: Text(
                                    '$cap · Default ${defaults.contains(cap) ? 'Yes' : 'No'} · Effective ${effective.contains(cap) ? 'Yes' : 'No'}',
                                  ),
                                  trailing: DropdownButton<String>(
                                    value: value,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'inherit',
                                        child: Text('Inherit'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'grant',
                                        child: Text('Grant'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'deny',
                                        child: Text('Deny'),
                                      ),
                                    ],
                                    onChanged: (v) => setLocal(() {
                                      grants.remove(cap);
                                      denies.remove(cap);
                                      if (v == 'grant') grants.add(cap);
                                      if (v == 'deny') denies.add(cap);
                                    }),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        controller: reason,
                        decoration: const InputDecoration(
                          labelText: 'Change Reason',
                          hintText: 'Required when access changes',
                        ),
                      ),
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
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save Access'),
              ),
            ],
          ),
        ),
      );
      if (saved == true) {
        final rolesChanged = !_sameInts(originalRoles, selectedRoles);
        final overridesChanged = overrideSupported &&
            (!_sameStrings(originalGrants, grants) ||
                !_sameStrings(originalDenies, denies));
        if ((rolesChanged || overridesChanged) &&
            reason.text.trim().length < 5) {
          if (mounted) {
            setState(
              () => message =
                  'Access change reason must contain at least 5 characters.',
            );
          }
        } else {
          if (rolesChanged) {
            await ref.read(apiClientProvider).post(
              ApiPaths.employeeRoles(id),
              data: {
                'role_ids': selectedRoles.toList()..sort(),
                'reason': reason.text.trim(),
              },
            );
          }
          if (overridesChanged) {
            await ref.read(apiClientProvider).post(
              ApiPaths.employeeOverrides(id),
              data: {
                'grants': grants.toList()..sort(),
                'denies': denies.toList()..sort(),
                'reason': reason.text.trim(),
              },
            );
          }
          if (mounted) {
            setState(() {
              message = rolesChanged || overridesChanged
                  ? 'Employee access updated.'
                  : 'No access changes.';
              if (rolesChanged || overridesChanged) refresh++;
            });
          }
        }
      }
      reason.dispose();
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  bool _sameInts(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  bool _sameStrings(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  String _capLabel(String cap) {
    final parts = cap.replaceAll('.', ' ').replaceAll('_', ' ').split(' ');
    return parts
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
        .join(' ');
  }

  Future<void> _post(
    String path,
    Map<String, dynamic> data, {
    bool closeSheet = true,
  }) async {
    if (closeSheet && Navigator.canPop(context)) Navigator.pop(context);
    try {
      await ref.read(apiClientProvider).post(path, data: data);
      if (mounted) {
        setState(() {
          message = 'Saved successfully.';
          refresh++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }
}