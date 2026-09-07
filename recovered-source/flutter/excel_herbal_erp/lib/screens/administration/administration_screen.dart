import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/records_list.dart';

class AdministrationScreen extends ConsumerStatefulWidget {
  const AdministrationScreen({super.key});
  @override
  ConsumerState<AdministrationScreen> createState() => _AdministrationScreenState();
}

class _AdministrationScreenState extends ConsumerState<AdministrationScreen> {
  int refresh = 0;
  String? message;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administration'),
          bottom: const TabBar(tabs: [Tab(text: 'Reversals'), Tab(text: 'Access'), Tab(text: 'Audit Log')]),
        ),
        body: Column(children: [
          if (message != null) Padding(padding: const EdgeInsets.all(8), child: Text(message!)),
          Expanded(
            child: TabBarView(children: [
              app.can('finance.reversal.create') || app.can('finance.reversal.approve')
                  ? AsyncPanel(
                      key: ValueKey('reversals-$refresh'),
                      future: api.get(ApiPaths.reversals),
                      emptyMessage: 'Koi reversal request nahi hai.',
                      builder: (context, data) => RecordsList(rows: _rows(data), onTap: _reversalAction),
                    )
                  : const Center(child: Text('Reversal access authorised nahi hai.')),
              app.can('administration.access.manage') ? _accessTab(app.currentBranchId) : const Center(child: Text('Access Management authorised nahi hai.')),
              app.can('administration.audit.view')
                  ? AsyncPanel(
                      key: ValueKey('audit-$refresh'),
                      future: api.get(ApiPaths.audit),
                      builder: (context, data) => RecordsList(rows: _rows(data)),
                    )
                  : const Center(child: Text('Audit Log access authorised nahi hai.')),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _accessTab(int? branchId) {
    if (branchId == null) return const Center(child: Text('Authorised branch select karein.'));
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
        final roles = ((matrix['roles'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final caps = ((matrix['capabilities'] as List?) ?? const []).map((e) => '$e').toList();
        final employees = (list[1] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(children: [Expanded(child: Text('Roles & Permissions', style: Theme.of(context).textTheme.titleLarge)), FilledButton.icon(onPressed: _newRole, icon: const Icon(Icons.add), label: const Text('New Role'))]),
            const SizedBox(height: 8),
            ...roles.map((r) => Card(child: ListTile(
              leading: const Icon(Icons.security_outlined),
              title: Text('${r['name']}'),
              subtitle: Text('${r['code']} · ${((r['capabilities'] as List?) ?? const []).length} permissions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editRoleCapabilities(r, caps),
            ))),
            const SizedBox(height: 18),
            Text('Employee Role Assignment', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...employees.map((e) => Card(child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text('${e['full_name']}'),
              subtitle: Text('${e['employee_code']} · ${e['designation_code']}'),
              trailing: const Icon(Icons.manage_accounts_outlined),
              onTap: () => _assignEmployeeRoles(e, roles),
            ))),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _rows(dynamic data) => (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  void _reversalAction(Map<String, dynamic> row) {
    final app = ref.read(appStateProvider);
    final id = int.parse('${row['id']}');
    final status = '${row['status']}';
    showModalBottomSheet<void>(context: context, builder: (context) => SafeArea(child: Wrap(children: [
      ListTile(title: Text('${row['source_type']} #${row['source_id']} · $status'), subtitle: Text('${row['reason']}')),
      if (status == 'pending' && app.can('finance.reversal.approve')) ...[
        ListTile(leading: const Icon(Icons.check_circle_outline), title: const Text('Approve Reversal'), onTap: () => _post(ApiPaths.reversalDecision(id), {'approve': true})),
        ListTile(leading: const Icon(Icons.cancel_outlined), title: const Text('Reject Reversal'), onTap: () => _post(ApiPaths.reversalDecision(id), {'approve': false})),
      ],
      if (status == 'approved' && app.can('finance.reversal.approve'))
        ListTile(leading: const Icon(Icons.undo), title: const Text('Execute Reversal'), subtitle: const Text('Stock, outstanding, journal aur audit chain backend se reverse honge.'), onTap: () => _post(ApiPaths.reversalExecute(id), const {})),
    ])));
  }

  Future<void> _newRole() async {
    final code = TextEditingController();
    final name = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('New Role'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: code, decoration: const InputDecoration(labelText: 'Role Code')), const SizedBox(height: 12), TextField(controller: name, decoration: const InputDecoration(labelText: 'Role Name'))]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create'))],
    ));
    if (ok == true) await _post(ApiPaths.adminRoles, {'code': code.text.trim(), 'name': name.text.trim()}, closeSheet: false);
    code.dispose(); name.dispose();
  }

  Future<void> _editRoleCapabilities(Map<String, dynamic> role, List<String> allCaps) async {
    final selected = <String>{...((role['capabilities'] as List?) ?? const []).map((e) => '$e')};
    final reason = TextEditingController();
    final saved = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
      title: Text('Permissions · ${role['name']}'),
      content: SizedBox(width: 560, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: ListView(shrinkWrap: true, children: allCaps.map((cap) => CheckboxListTile(dense: true, value: selected.contains(cap), title: Text(cap), onChanged: (v) => setLocal(() => v == true ? selected.add(cap) : selected.remove(cap)))).toList())),
        const SizedBox(height: 8), TextField(controller: reason, decoration: const InputDecoration(labelText: 'Change Reason')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))],
    )));
    if (saved == true) await _post(ApiPaths.roleCapabilities(int.parse('${role['id']}')), {'capabilities': selected.toList()..sort(), 'reason': reason.text.trim()}, closeSheet: false);
    reason.dispose();
  }

  Future<void> _assignEmployeeRoles(Map<String, dynamic> employee, List<Map<String, dynamic>> roles) async {
    final id = int.parse('${employee['id']}');
    try {
      final detail = Map<String, dynamic>.from(await ref.read(apiClientProvider).get(ApiPaths.employeeAccess(id)) as Map);
      final selected = <int>{...((detail['roles'] as List?) ?? const []).map((e) => int.parse('${(e as Map)['id']}'))};
      final reason = TextEditingController();
      if (!mounted) return;
      final saved = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
        title: Text('Roles · ${employee['full_name']}'),
        content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
          ...roles.map((r) { final rid = int.parse('${r['id']}'); return CheckboxListTile(value: selected.contains(rid), title: Text('${r['name']}'), subtitle: Text('${r['code']}'), onChanged: (v) => setLocal(() => v == true ? selected.add(rid) : selected.remove(rid))); }),
          const SizedBox(height: 8), TextField(controller: reason, decoration: const InputDecoration(labelText: 'Change Reason')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))],
      )));
      if (saved == true) await _post(ApiPaths.employeeRoles(id), {'role_ids': selected.toList()..sort(), 'reason': reason.text.trim()}, closeSheet: false);
      reason.dispose();
    } catch (e) { if (mounted) setState(() => message = e.toString()); }
  }

  Future<void> _post(String path, Map<String, dynamic> data, {bool closeSheet = true}) async {
    if (closeSheet && Navigator.canPop(context)) Navigator.pop(context);
    try {
      final r = await ref.read(apiClientProvider).post(path, data: data);
      if (mounted) setState(() { message = 'Done: $r'; refresh++; });
    } catch (e) { if (mounted) setState(() => message = e.toString()); }
  }
}
