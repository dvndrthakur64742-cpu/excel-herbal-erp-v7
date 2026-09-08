import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/records_list.dart';

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
          emptyMessage: 'Koi reversal request nahi hai.',
          builder: (context, data) => RecordsList(
            recordType: 'reversal',
            rows: _rows(data),
            onTap: _reversalAction,
          ),
        ),
      ));
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
        body: Column(
          children: [
            if (message != null)
              Padding(padding: const EdgeInsets.all(8), child: Text(message!)),
            Expanded(
              child: TabBarView(children: [for (final tab in tabs) tab.$2]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accessTab(int? branchId) {
    if (branchId == null)
      return const Center(child: Text('Authorised branch select karein.'));
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
              'Designation recommended permissions are automatic; roles are additional access.',
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
                  'Stock, outstanding, journal aur audit chain backend se reverse honge.',
                ),
                onTap: () => _post(ApiPaths.reversalExecute(id), const {}),
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
    if (ok == true)
      await _post(ApiPaths.adminRoles, {
        'code': code.text.trim(),
        'name': name.text.trim(),
      }, closeSheet: false);
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
    if (saved == true)
      await _post(ApiPaths.roleCapabilities(int.parse('${role['id']}')), {
        'capabilities': selected.toList()..sort(),
        'reason': reason.text.trim(),
      }, closeSheet: false);
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
                                  'Designation: ${employee['designation_code']} · recommended permissions apply automatically.',
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
                                  'Individual Grant/Deny overrides will become available after backend v7.1.7 alignment.',
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
        final overridesChanged =
            overrideSupported &&
            (!_sameStrings(originalGrants, grants) ||
                !_sameStrings(originalDenies, denies));
        if ((rolesChanged || overridesChanged) &&
            reason.text.trim().length < 5) {
          if (mounted)
            setState(
              () => message =
                  'Access change reason minimum 5 characters hona chahiye.',
            );
        } else {
          if (rolesChanged) {
            await ref
                .read(apiClientProvider)
                .post(
                  ApiPaths.employeeRoles(id),
                  data: {
                    'role_ids': selectedRoles.toList()..sort(),
                    'reason': reason.text.trim(),
                  },
                );
          }
          if (overridesChanged) {
            await ref
                .read(apiClientProvider)
                .post(
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
      final r = await ref.read(apiClientProvider).post(path, data: data);
      if (mounted)
        setState(() {
          message = 'Done: $r';
          refresh++;
        });
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }
}
