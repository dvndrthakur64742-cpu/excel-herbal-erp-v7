import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/open_document.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';

class HrLifecycleScreen extends ConsumerStatefulWidget {
  const HrLifecycleScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<HrLifecycleScreen> createState() => _HrLifecycleScreenState();
}

class _HrLifecycleScreenState extends ConsumerState<HrLifecycleScreen> {
  int _refresh = 0;
  String? _message;

  bool _manage(AppState app) => app.can('organization.hr.manage');
  bool _review(AppState app) => app.can('organization.hr.review');

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final allowed = app.canAny(const [
      'organization.hr.view',
      'organization.hr.manage',
      'organization.hr.review',
    ]);
    if (!allowed) {
      const denied = Center(
        child: Text('HR Lifecycle access is not authorised.'),
      );
      return widget.embedded ? denied : const Scaffold(body: denied);
    }

    const lifecycleTabs = TabBar(
      tabs: [
        Tab(icon: Icon(Icons.person_search_outlined), text: 'Candidates'),
        Tab(icon: Icon(Icons.person_off_outlined), text: 'Separations'),
      ],
    );

    final body = Column(
      children: [
        if (!widget.embedded)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: BranchSelector(allowAllAuthorised: true),
          ),
        if (widget.embedded) lifecycleTabs,
        if (_message != null)
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.info_outline),
              title: Text(_message!),
              trailing: IconButton(
                onPressed: () => setState(() => _message = null),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        Expanded(
          child: TabBarView(
            children: [
              _candidatesTab(app),
              _separationsTab(app),
            ],
          ),
        ),
      ],
    );

    return DefaultTabController(
      length: 2,
      child: widget.embedded
          ? body
          : Scaffold(
              appBar: AppBar(
                title: const Text('HR Lifecycle'),
                bottom: lifecycleTabs,
              ),
              body: body,
            ),
    );
  }

  Widget _candidatesTab(AppState app) {
    final query = <String, dynamic>{'status': 'open'};
    if (app.currentBranchId != null) query['branch_id'] = app.currentBranchId;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  app.currentBranchId == null
                      ? 'Open candidates · All Authorised Branches'
                      : 'Open candidates · ${app.currentBranchName}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_manage(app))
                FilledButton.icon(
                  onPressed: app.currentBranchId == null ? null : _createCandidate,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Register'),
                ),
            ],
          ),
        ),
        if (_manage(app) && app.currentBranchId == null)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Candidate registration ke liye ek branch select karein.'),
            ),
          ),
        Expanded(
          child: AsyncPanel(
            key: ValueKey('hr-candidates-${app.currentBranchId}'),
            reloadToken: '${app.currentBranchId}-$_refresh',
            future: ref.read(apiClientProvider).get(
                  ApiPaths.hrCandidates,
                  query: query,
                ),
            emptyMessage: 'Koi open candidate nahi hai.',
            builder: (context, data) {
              final rows = _rows(data);
              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _candidateCard(app, rows[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _candidateCard(AppState app, Map<String, dynamic> row) {
    final name = '${row['full_name'] ?? ''}'.trim();
    final code = '${row['candidate_code'] ?? ''}'.trim();
    final status = '${row['status'] ?? ''}'.trim();
    final designation =
        '${row['designation_name'] ?? row['proposed_designation_code'] ?? ''}'
            .trim();
    final branch = '${row['branch_name'] ?? row['branch_code'] ?? ''}'.trim();
    final expected = '${row['expected_joining_date'] ?? ''}'.trim();
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase()),
        ),
        title: Text(code.isEmpty ? name : '$name · $code'),
        subtitle: Text(
          [designation, branch, if (expected.isNotEmpty) 'Joining $expected']
              .where((e) => e.isNotEmpty)
              .join(' · '),
        ),
        trailing: _statusChip(status),
        onTap: () => _candidateActions(app, row),
      ),
    );
  }

  Widget _separationsTab(AppState app) {
    final query = <String, dynamic>{'status': 'open'};
    if (app.currentBranchId != null) query['branch_id'] = app.currentBranchId;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  app.currentBranchId == null
                      ? 'Open separations · All Authorised Branches'
                      : 'Open separations · ${app.currentBranchName}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_manage(app))
                FilledButton.icon(
                  onPressed: app.currentBranchId == null ? null : _initiateSeparation,
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const Text('New Separation'),
                ),
            ],
          ),
        ),
        if (_manage(app) && app.currentBranchId == null)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Separation initiate karne ke liye ek branch select karein.'),
            ),
          ),
        Expanded(
          child: AsyncPanel(
            key: ValueKey('hr-separations-${app.currentBranchId}'),
            reloadToken: '${app.currentBranchId}-$_refresh',
            future: ref.read(apiClientProvider).get(
                  ApiPaths.hrSeparations,
                  query: query,
                ),
            emptyMessage: 'Koi open separation request nahi hai.',
            builder: (context, data) {
              final rows = _rows(data);
              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _separationCard(app, rows[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _separationCard(AppState app, Map<String, dynamic> row) {
    final name = '${row['full_name'] ?? ''}'.trim();
    final code = '${row['employee_code'] ?? ''}'.trim();
    final designation = '${row['designation_code'] ?? ''}'.trim();
    final date = '${row['separation_date'] ?? ''}'.trim();
    final status = '${row['status'] ?? ''}'.trim();
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_off_outlined)),
        title: Text('$name · $code'),
        subtitle: Text(
          [designation, if (date.isNotEmpty) 'Effective $date']
              .where((e) => e.isNotEmpty)
              .join(' · '),
        ),
        trailing: _statusChip(status),
        onTap: () => _separationActions(app, row),
      ),
    );
  }

  Widget _statusChip(String status) {
    final words = status
        .replaceAll('_', ' ')
        .split(' ')
        .where((e) => e.isNotEmpty)
        .toList();
    final label = words
        .map((e) => '${e[0].toUpperCase()}${e.substring(1)}')
        .join(' ');
    return Chip(label: Text(label.isEmpty ? 'Status' : label));
  }

  List<Map<String, dynamic>> _rows(dynamic data) => (data as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  Future<void> _reload() async {
    if (mounted) setState(() => _refresh++);
  }

  Future<List<Map<String, dynamic>>> _designations() async {
    final app = ref.read(appStateProvider);
    final data = await ref.read(apiClientProvider).get(ApiPaths.designations);
    var rows = _rows(data);
    if (!app.can('administration.access.manage')) {
      const protected = {
        'SYSADMIN',
        'SYSTEM_ADMIN',
        'ADMIN',
        'ADMINISTRATOR',
        'ZI',
        'ZONAL_INSPECTOR',
        'CM',
        'CHAIRMAN',
        'CHAIRMAN_MANAGING_DIRECTOR',
        'MD',
        'MANAGING_DIRECTOR',
      };
      rows = rows
          .where((r) => !protected.contains('${r['code']}'.toUpperCase()))
          .toList();
    }
    return rows;
  }

  Future<void> _createCandidate() async {
    final app = ref.read(appStateProvider);
    final branchId = app.currentBranchId;
    if (branchId == null) return;
    try {
      final designations = await _designations();
      if (!mounted) return;
      String? designationCode;
      final name = TextEditingController();
      final mobile = TextEditingController();
      final email = TextEditingController();
      final salary = TextEditingController(text: '0');
      final source = TextEditingController();
      final notes = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setLocal) => AlertDialog(
            title: const Text('Register Candidate'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: designationCode,
                      decoration: const InputDecoration(
                        labelText: 'Proposed Designation',
                      ),
                      items: designations
                          .map(
                            (d) => DropdownMenuItem(
                              value: '${d['code']}',
                              child: Text('${d['name']} · ${d['code']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setLocal(() => designationCode = v),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: mobile,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Mobile'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: salary,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Offered Monthly Salary',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: source,
                      decoration: const InputDecoration(
                        labelText: 'Source (optional)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notes,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
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
              FilledButton(
                onPressed: () {
                  final hasContact =
                      mobile.text.trim().isNotEmpty || email.text.trim().isNotEmpty;
                  Navigator.pop(
                    dialogContext,
                    name.text.trim().isNotEmpty &&
                        designationCode != null &&
                        hasContact,
                  );
                },
                child: const Text('Register'),
              ),
            ],
          ),
        ),
      );
      final payload = <String, dynamic>{
        'branch_id': branchId,
        'full_name': name.text.trim(),
        'proposed_designation_code': designationCode,
        if (mobile.text.trim().isNotEmpty) 'mobile': mobile.text.trim(),
        if (email.text.trim().isNotEmpty) 'email': email.text.trim(),
        'offered_monthly_salary': double.tryParse(salary.text) ?? 0,
        if (source.text.trim().isNotEmpty) 'source': source.text.trim(),
        if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
      };
      name.dispose();
      mobile.dispose();
      email.dispose();
      salary.dispose();
      source.dispose();
      notes.dispose();
      if (ok != true) return;
      final result = await ref
          .read(apiClientProvider)
          .post(ApiPaths.hrCandidates, data: payload);
      _success('Candidate ${result['candidate_code'] ?? ''} registered.');
    } catch (error) {
      _failure(error);
    }
  }

  Future<void> _candidateActions(AppState app, Map<String, dynamic> row) async {
    final id = int.tryParse('${row['id']}');
    if (id == null) return;
    Map<String, dynamic> detail = row;
    try {
      final loaded = await ref.read(apiClientProvider).get(ApiPaths.candidateDetail(id));
      detail = Map<String, dynamic>.from(loaded as Map);
    } catch (_) {
      // Keep list data available when the detail request is temporarily unavailable.
    }
    if (!mounted) return;
    final status = '${detail['status'] ?? ''}';
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
        children: [
          ListTile(
            title: Text('${detail['full_name'] ?? 'Candidate'}'),
            subtitle: Text(
              '${detail['candidate_code'] ?? ''} · ${detail['proposed_designation_code'] ?? ''} · $status',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('View Details'),
            onTap: () {
              Navigator.pop(sheetContext);
              _showCandidateDetail(detail);
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Candidate Documents'),
            onTap: () {
              Navigator.pop(sheetContext);
              _showCandidateDocuments(id);
            },
          ),
          if (status == 'registered' && _review(app))
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Review Candidate'),
              onTap: () {
                Navigator.pop(sheetContext);
                _reviewCandidate(detail);
              },
            ),
          if (status == 'selected' && _review(app))
            ListTile(
              leading: const Icon(Icons.how_to_reg_outlined),
              title: const Text('Confirm Joining'),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmJoining(detail);
              },
            ),
          if (status == 'selected' && _manage(app))
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Mark No-Show'),
              onTap: () {
                Navigator.pop(sheetContext);
                _markNoShow(detail);
              },
            ),
          if (status == 'joined' &&
              _review(app) &&
              '${detail['credentials_issued_at'] ?? ''}'.trim().isEmpty)
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('Issue Login Credentials'),
              onTap: () {
                Navigator.pop(sheetContext);
                _issueCredentials(detail);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showCandidateDetail(Map<String, dynamic> candidate) async {
    final fields = <(String, String)>[
      ('Candidate Code', '${candidate['candidate_code'] ?? '—'}'),
      ('Name', '${candidate['full_name'] ?? '—'}'),
      ('Status', '${candidate['status'] ?? '—'}'),
      ('Designation', '${candidate['proposed_designation_code'] ?? '—'}'),
      ('Mobile', '${candidate['mobile'] ?? '—'}'),
      ('Email', '${candidate['email'] ?? '—'}'),
      ('Employee Code', '${candidate['proposed_employee_code'] ?? '—'}'),
      ('Expected Joining', '${candidate['expected_joining_date'] ?? '—'}'),
      ('Review Reason', '${candidate['review_reason'] ?? '—'}'),
      ('No-show Reason', '${candidate['no_show_reason'] ?? '—'}'),
    ];
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Candidate Details'),
        content: SizedBox(
          width: 620,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final field in fields)
                ListTile(
                  dense: true,
                  title: Text(field.$1),
                  subtitle: Text(field.$2.trim().isEmpty ? '—' : field.$2),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _reviewCandidate(Map<String, dynamic> candidate) async {
    final id = int.parse('${candidate['id']}');
    var selected = true;
    final reason = TextEditingController();
    final employeeCode = TextEditingController(
      text: '${candidate['proposed_employee_code'] ?? ''}',
    );
    final joining = TextEditingController(
      text: ref.read(appStateProvider).businessDate,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Review Candidate'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Select')),
                    ButtonSegment(value: false, label: Text('Reject')),
                  ],
                  selected: {selected},
                  onSelectionChanged: (value) =>
                      setLocal(() => selected = value.first),
                ),
                if (selected) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: employeeCode,
                    decoration: const InputDecoration(labelText: 'Employee Code'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: joining,
                    decoration: const InputDecoration(
                      labelText: 'Expected Joining Date YYYY-MM-DD',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: reason,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Review Reason'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                reason.text.trim().length >= 5 &&
                    (!selected || employeeCode.text.trim().isNotEmpty),
              ),
              child: const Text('Apply Decision'),
            ),
          ],
        ),
      ),
    );
    final payload = <String, dynamic>{
      'decision': selected ? 'selected' : 'rejected',
      'reason': reason.text.trim(),
      if (selected) 'employee_code': employeeCode.text.trim(),
      if (selected) 'expected_joining_date': joining.text.trim(),
    };
    reason.dispose();
    employeeCode.dispose();
    joining.dispose();
    if (ok != true) return;
    try {
      await ref
          .read(apiClientProvider)
          .post(ApiPaths.candidateReview(id), data: payload);
      _success(selected ? 'Candidate selected.' : 'Candidate rejected.');
    } catch (error) {
      _failure(error);
    }
  }

  Future<void> _confirmJoining(Map<String, dynamic> candidate) async {
    final app = ref.read(appStateProvider);
    final id = int.parse('${candidate['id']}');
    final branchId = int.tryParse('${candidate['branch_id']}');
    try {
      final data = branchId == null
          ? <dynamic>[]
          : await ref.read(apiClientProvider).get(
                ApiPaths.employees,
                query: {'branch_id': branchId},
              );
      final selfId = int.tryParse('${app.employee['id']}');
      final employees = _rows(data)
          .where((e) => int.tryParse('${e['id']}') != selfId)
          .toList();
      if (!mounted) return;
      int? reportingId;
      final employeeCode = TextEditingController(
        text: '${candidate['proposed_employee_code'] ?? ''}',
      );
      final joining = TextEditingController(text: app.businessDate);
      final salary = TextEditingController(
        text: '${candidate['offered_monthly_salary'] ?? 0}',
      );
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setLocal) => AlertDialog(
            title: const Text('Confirm Candidate Joining'),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: employeeCode,
                      decoration: const InputDecoration(labelText: 'Employee Code'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: joining,
                      decoration: const InputDecoration(
                        labelText: 'Joining Date YYYY-MM-DD',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: salary,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Monthly Salary'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      initialValue: reportingId,
                      decoration: const InputDecoration(
                        labelText: 'Reporting Manager (optional)',
                      ),
                      items: <DropdownMenuItem<int?>>[
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('No reporting manager'),
                        ),
                        ...employees.map(
                          (e) => DropdownMenuItem<int?>(
                            value: int.tryParse('${e['id']}'),
                            child: Text('${e['full_name']} · ${e['employee_code']}'),
                          ),
                        ),
                      ],
                      onChanged: (v) => setLocal(() => reportingId = v),
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Security roles joining ke waqt assign nahi hote. Role assignment Access Management se alag hoti hai.',
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
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  employeeCode.text.trim().isNotEmpty &&
                      joining.text.trim().isNotEmpty,
                ),
                child: const Text('Confirm Joining'),
              ),
            ],
          ),
        ),
      );
      final employeeCodeValue = employeeCode.text.trim();
      final payload = <String, dynamic>{
        if (branchId != null) 'branch_id': branchId,
        'employee_code': employeeCodeValue,
        'designation_code': '${candidate['proposed_designation_code'] ?? ''}',
        'joining_date': joining.text.trim(),
        'monthly_salary': double.tryParse(salary.text) ?? 0,
        if (reportingId != null) 'reporting_employee_id': reportingId,
      };
      employeeCode.dispose();
      joining.dispose();
      salary.dispose();
      if (ok != true) return;
      await ref
          .read(apiClientProvider)
          .post(ApiPaths.candidateJoining(id), data: payload);
      _success('Joining confirmed for $employeeCodeValue. Credentials are pending.');
    } catch (error) {
      _failure(error);
    }
  }

  Future<void> _issueCredentials(Map<String, dynamic> candidate) async {
    final id = int.parse('${candidate['id']}');
    final password = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Issue Login Credentials'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Temporary Password'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm Password'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              password.text.isNotEmpty && password.text == confirm.text,
            ),
            child: const Text('Issue Credentials'),
          ),
        ],
      ),
    );
    final value = password.text;
    password.dispose();
    confirm.dispose();
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).post(
        ApiPaths.candidateCredentials(id),
        data: {'password': value},
      );
      _success('Login credentials issued.');
    } catch (error) {
      _failure(error);
    }
  }

  Future<void> _markNoShow(Map<String, dynamic> candidate) async {
    final id = int.parse('${candidate['id']}');
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark Candidate No-Show'),
        content: TextField(
          controller: reason,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'No-show Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              reason.text.trim().length >= 5,
            ),
            child: const Text('Mark No-Show'),
          ),
        ],
      ),
    );
    final value = reason.text.trim();
    reason.dispose();
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).post(
        ApiPaths.candidateNoShow(id),
        data: {'reason': value},
      );
      _success('Candidate marked no-show.');
    } catch (error) {
      _failure(error);
    }
  }

  Future<void> _showCandidateDocuments(int candidateId) async {
    try {
      final data = await ref
          .read(apiClientProvider)
          .get(HrApiPaths.candidateDocuments(candidateId));
      final rows = _rows(data);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Candidate Documents'),
          content: SizedBox(
            width: 650,
            height: 390,
            child: rows.isEmpty
                ? const Center(child: Text('No active candidate documents.'))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, index) {
                      final row = rows[index];
                      final url = '${row['url'] ?? ''}'.trim();
                      final docId = int.tryParse('${row['id']}');
                      return ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text('${row['title'] ?? 'Document'}'),
                        subtitle: Text(row['migration_required'] == true
                            ? 'Administrator migration required'
                            : '${row['document_type'] ?? ''}'),
                        onTap: url.isEmpty
                            ? null
                            : () async {
                                try {
                                  await openErpDocument(ref.read(apiClientProvider), row);
                                } catch (error) {
                                  if (mounted) _failure(error);
                                }
                              },
                        trailing: _manage(ref.read(appStateProvider)) && docId != null
                            ? IconButton(
                                tooltip: 'Deactivate document',
                                onPressed: () async {
                                  Navigator.pop(dialogContext);
                                  await _deactivateDocument(candidateId, docId);
                                },
                                icon: const Icon(Icons.remove_circle_outline),
                              )
                            : null,
                      );
                    },
                  ),
          ),
          actions: [
            if (_manage(ref.read(appStateProvider)))
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _uploadCandidateDocument(candidateId);
                },
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Upload'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      _failure(error);
    }
  }

  Future<void> _uploadCandidateDocument(int candidateId) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _failure(const FormatException('Selected file bytes are unavailable.'));
      return;
    }
    if (file.size > 10 * 1024 * 1024) {
      _failure(const FormatException('Document must be 10 MB or smaller.'));
      return;
    }
    final type = TextEditingController(text: 'candidate_document');
    final title = TextEditingController(text: file.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Upload Candidate Document'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: type,
                decoration: const InputDecoration(labelText: 'Document Type'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Document Title'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              type.text.trim().isNotEmpty && title.text.trim().isNotEmpty,
            ),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    final documentType = type.text.trim();
    final documentTitle = title.text.trim();
    type.dispose();
    title.dispose();
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).uploadBytes(
        HrApiPaths.candidateDocumentUpload(candidateId),
        bytes: bytes,
        filename: file.name,
        fields: {
          'document_type': documentType,
          'title': documentTitle,
        },
      );
      _success('Candidate document uploaded.');
    } catch (error) {
      _failure(error);
    }
  }

  Future<void> _deactivateDocument(int candidateId, int documentId) async {
    try {
      await ref.read(apiClientProvider).post(
        HrApiPaths.candidateDocumentDeactivate(candidateId, documentId),
        data: const {},
      );
      _success('Candidate document deactivated.');
    } catch (error) {
      _failure(error);
    }
  }

  Future<void> _initiateSeparation() async {
    final app = ref.read(appStateProvider);
    final branchId = app.currentBranchId;
    if (branchId == null) return;
    try {
      final data = await ref.read(apiClientProvider).get(
        ApiPaths.employees,
        query: {'branch_id': branchId},
      );
      final selfId = int.tryParse('${app.employee['id']}');
      final employees = _rows(data)
          .where((e) => int.tryParse('${e['id']}') != selfId)
          .toList();
      if (!mounted) return;
      if (employees.isEmpty) {
        _failure(const FormatException('No eligible active employee found.'));
        return;
      }
      int? employeeId;
      final date = TextEditingController(text: app.businessDate);
      final reason = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setLocal) => AlertDialog(
            title: const Text('Initiate Employee Separation'),
            content: SizedBox(
              width: 580,
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
                              '${e['full_name']} · ${e['employee_code']} · ${e['designation_code']}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setLocal(() => employeeId = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: date,
                    decoration: const InputDecoration(
                      labelText: 'Separation Date YYYY-MM-DD',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reason,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Reason'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  employeeId != null && reason.text.trim().length >= 5,
                ),
                child: const Text('Submit Separation'),
              ),
            ],
          ),
        ),
      );
      final payload = {
        'separation_date': date.text.trim(),
        'reason': reason.text.trim(),
      };
      date.dispose();
      reason.dispose();
      if (ok != true || employeeId == null) return;
      final result = await ref.read(apiClientProvider).post(
        HrApiPaths.employeeSeparation(employeeId!),
        data: payload,
      );
      final blockers = (result['current_blockers'] as List?) ?? const [];
      _success(
        blockers.isEmpty
            ? 'Separation request submitted.'
            : 'Separation submitted; ${blockers.length} blocker(s) need clearance before completion.',
      );
    } catch (error) {
      _failure(error);
    }
  }

  Future<void> _separationActions(AppState app, Map<String, dynamic> row) async {
    final id = int.tryParse('${row['id']}');
    if (id == null) return;
    final status = '${row['status'] ?? ''}';
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
        children: [
          ListTile(
            title: Text('${row['full_name'] ?? 'Employee'}'),
            subtitle: Text(
              '${row['employee_code'] ?? ''} · ${row['separation_date'] ?? ''} · $status',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Reason'),
            subtitle: Text('${row['reason'] ?? '—'}'),
          ),
          if (status == 'submitted' && _review(app))
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Review Separation'),
              onTap: () {
                Navigator.pop(sheetContext);
                _reviewSeparation(row);
              },
            ),
          if (status == 'approved' && _review(app))
            ListTile(
              leading: const Icon(Icons.task_alt_outlined),
              title: const Text('Complete Separation'),
              subtitle: const Text(
                'Completion effective date aur offboarding blockers enforce karegi.',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _completeSeparation(row);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _reviewSeparation(Map<String, dynamic> row) async {
    final id = int.parse('${row['id']}');
    var approve = true;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Review Separation'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Approve')),
                    ButtonSegment(value: false, label: Text('Reject')),
                  ],
                  selected: {approve},
                  onSelectionChanged: (value) =>
                      setLocal(() => approve = value.first),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reason,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Review Reason'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                reason.text.trim().length >= 5,
              ),
              child: const Text('Apply Decision'),
            ),
          ],
        ),
      ),
    );
    final value = reason.text.trim();
    reason.dispose();
    if (ok != true) return;
    try {
      final result = await ref.read(apiClientProvider).post(
        ApiPaths.separationReview(id),
        data: {'approve': approve, 'reason': value},
      );
      final blockers = (result['current_blockers'] as List?) ?? const [];
      _success(
        approve
            ? blockers.isEmpty
                ? 'Separation approved.'
                : 'Separation approved; ${blockers.length} blocker(s) require clearance.'
            : 'Separation rejected.',
      );
    } catch (error) {
      _failure(error);
    }
  }

  Future<void> _completeSeparation(Map<String, dynamic> row) async {
    final id = int.parse('${row['id']}');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Complete Separation'),
        content: Text(
          'Complete separation for ${row['full_name'] ?? 'this employee'}? ERP approved date aur all offboarding blockers enforce karega.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiClientProvider).post(
        ApiPaths.separationComplete(id),
        data: const {},
      );
      _success('Employee separation completed and employee offboarded.');
    } catch (error) {
      _failure(error);
    }
  }

  void _success(String text) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _refresh++;
    });
  }

  void _failure(Object error) {
    if (!mounted) return;
    setState(() => _message = UiError.message(error));
  }
}

