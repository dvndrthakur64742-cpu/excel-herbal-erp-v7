part of 'organization_screen.dart';

extension _OrganizationHrFeature on _OrganizationScreenState {
  Widget _hrLifecycleTab(AppState app, dynamic api) {
    if (app.currentBranchId == null) {
      return const Center(child: Text('Select a branch to open HR Lifecycle.'));
    }
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Material(
            color: Colors.transparent,
            child: TabBar(
              tabs: [
                Tab(text: 'Candidates'),
                Tab(text: 'Separations'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _candidatePanel(app, api),
                _separationPanel(app, api),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _candidatePanel(AppState app, dynamic api) {
    return Column(
      children: [
        if (app.can('organization.hr.manage'))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _createCandidate,
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('New Candidate'),
              ),
            ),
          ),
        Expanded(
          child: AsyncPanel(
            key: ValueKey('hr-candidates-${app.currentBranchId}-$refresh'),
            future: api.get(
              ApiPaths.hrCandidates,
              query: {
                'branch_id': app.currentBranchId,
                'status': 'all',
              },
            ),
            emptyMessage: 'No candidate records are available for this branch.',
            builder: (context, data) => RecordsList(
              recordType: 'candidate',
              rows: (data as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
              onTap: _candidateActions,
            ),
          ),
        ),
      ],
    );
  }

  Widget _separationPanel(AppState app, dynamic api) {
    return Column(
      children: [
        if (app.can('organization.hr.manage'))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _initiateSeparation,
                icon: const Icon(Icons.person_off_outlined),
                label: const Text('Initiate Separation'),
              ),
            ),
          ),
        Expanded(
          child: AsyncPanel(
            key: ValueKey('hr-separations-${app.currentBranchId}-$refresh'),
            future: api.get(
              ApiPaths.hrSeparations,
              query: {
                'branch_id': app.currentBranchId,
                'status': 'all',
              },
            ),
            emptyMessage: 'No separation records are available for this branch.',
            builder: (context, data) => RecordsList(
              recordType: 'separation',
              rows: (data as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
              onTap: _separationActions,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createCandidate() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    if (app.currentBranchId == null) return;
    try {
      final designations = (await api.get(ApiPaths.designations) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      String? designation;
      final name = TextEditingController();
      final mobile = TextEditingController();
      final email = TextEditingController();
      final salary = TextEditingController(text: '0');
      final source = TextEditingController();
      final notes = TextEditingController();
      final controllers = [name, mobile, email, salary, source, notes];
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('New Candidate'),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Full Name'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: designation,
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
                      onChanged: (value) =>
                          setLocal(() => designation = value),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: mobile,
                      keyboardType: TextInputType.phone,
                      decoration:
                          const InputDecoration(labelText: 'Mobile'),
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
                      decoration:
                          const InputDecoration(labelText: 'Notes (optional)'),
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
                  name.text.trim().isNotEmpty &&
                      designation != null &&
                      (mobile.text.trim().isNotEmpty ||
                          email.text.trim().isNotEmpty),
                ),
                child: const Text('Create Candidate'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        await api.post(
          ApiPaths.hrCandidates,
          data: {
            'branch_id': app.currentBranchId,
            'full_name': name.text.trim(),
            'mobile': mobile.text.trim(),
            'email': email.text.trim(),
            'proposed_designation_code': designation,
            'offered_monthly_salary':
                double.tryParse(salary.text.trim()) ?? 0,
            'source': source.text.trim(),
            'notes': notes.text.trim(),
          },
        );
        _refreshHr('Candidate registered for HR review.');
      }
      for (final controller in controllers) {
        controller.dispose();
      }
    } catch (e) {
      _hrError(e);
    }
  }

  void _candidateActions(Map<String, dynamic> candidate) {
    final app = ref.read(appStateProvider);
    final status = '${candidate['status'] ?? ''}';
    final id = int.parse('${candidate['id']}');
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text('${candidate['full_name'] ?? 'Candidate'}'),
              subtitle: Text(
                '${candidate['candidate_code'] ?? ''} · ${candidate['proposed_designation_code'] ?? ''}',
              ),
            ),
            if (status == 'registered' &&
                app.can('organization.hr.review'))
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Review Candidate'),
                onTap: () => _reviewCandidate(id, candidate),
              ),
            if (status == 'selected' &&
                app.can('organization.hr.review'))
              ListTile(
                leading: const Icon(Icons.how_to_reg_outlined),
                title: const Text('Confirm Joining'),
                onTap: () => _confirmCandidateJoining(id, candidate),
              ),
            if (status == 'selected' &&
                app.can('organization.hr.manage'))
              ListTile(
                leading: const Icon(Icons.event_busy_outlined),
                title: const Text('Mark No-Show'),
                onTap: () => _markCandidateNoShow(id),
              ),
            if (status == 'joined' &&
                app.can('organization.hr.review') &&
                '${candidate['credentials_issued_at'] ?? ''}'.isEmpty)
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: const Text('Issue Login Credentials'),
                onTap: () => _issueCandidateCredentials(id),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _reviewCandidate(
    int candidateId,
    Map<String, dynamic> candidate,
  ) async {
    if (!await OverlayTransition.closeAndSettle(context) || !mounted) return;
    final app = ref.read(appStateProvider);
    var decision = 'selected';
    final reason = TextEditingController();
    final employeeCode = TextEditingController(
      text: '${candidate['proposed_employee_code'] ?? ''}',
    );
    final expected = TextEditingController(
      text: '${candidate['expected_joining_date'] ?? app.businessDate}',
    );
    final salary = TextEditingController(
      text: '${candidate['offered_monthly_salary'] ?? 0}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Review Candidate'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: decision,
                    decoration:
                        const InputDecoration(labelText: 'Decision'),
                    items: const [
                      DropdownMenuItem(
                        value: 'selected',
                        child: Text('Select Candidate'),
                      ),
                      DropdownMenuItem(
                        value: 'rejected',
                        child: Text('Reject Candidate'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setLocal(() => decision = value);
                    },
                  ),
                  if (decision == 'selected') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: employeeCode,
                      decoration:
                          const InputDecoration(labelText: 'Employee Code'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: expected,
                      decoration: const InputDecoration(
                        labelText: 'Expected Joining Date YYYY-MM-DD',
                      ),
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
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: reason,
                    minLines: 2,
                    maxLines: 4,
                    decoration:
                        const InputDecoration(labelText: 'Review Reason'),
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
                reason.text.trim().length >= 5 &&
                    (decision == 'rejected' ||
                        (employeeCode.text.trim().isNotEmpty &&
                            expected.text.trim().isNotEmpty)),
              ),
              child: const Text('Save Review'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await ref.read(apiClientProvider).post(
          ApiPaths.candidateReview(candidateId),
          data: {
            'decision': decision,
            'reason': reason.text.trim(),
            if (decision == 'selected')
              'employee_code': employeeCode.text.trim(),
            if (decision == 'selected')
              'expected_joining_date': expected.text.trim(),
            if (decision == 'selected')
              'offered_monthly_salary':
                  double.tryParse(salary.text.trim()) ?? 0,
          },
        );
        _refreshHr(
          decision == 'selected'
              ? 'Candidate selected and joining details reserved.'
              : 'Candidate review completed as rejected.',
        );
      } catch (e) {
        _hrError(e);
      }
    }
    reason.dispose();
    employeeCode.dispose();
    expected.dispose();
    salary.dispose();
  }

  Future<void> _confirmCandidateJoining(
    int candidateId,
    Map<String, dynamic> candidate,
  ) async {
    if (!await OverlayTransition.closeAndSettle(context) || !mounted) return;
    final app = ref.read(appStateProvider);
    final joining = TextEditingController(text: app.businessDate);
    final employeeCode = TextEditingController(
      text: '${candidate['proposed_employee_code'] ?? ''}',
    );
    final salary = TextEditingController(
      text: '${candidate['offered_monthly_salary'] ?? 0}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Candidate Joining'),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: employeeCode,
                decoration:
                    const InputDecoration(labelText: 'Employee Code'),
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
                decoration:
                    const InputDecoration(labelText: 'Monthly Salary'),
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
              employeeCode.text.trim().isNotEmpty &&
                  joining.text.trim().isNotEmpty,
            ),
            child: const Text('Confirm Joining'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(apiClientProvider).post(
          ApiPaths.candidateJoining(candidateId),
          data: {
            'joining_date': joining.text.trim(),
            'employee_code': employeeCode.text.trim(),
            'designation_code':
                '${candidate['proposed_designation_code'] ?? ''}',
            'monthly_salary': double.tryParse(salary.text.trim()) ?? 0,
          },
        );
        _refreshHr(
          'Candidate joined as employee. Login credentials are still pending.',
        );
      } catch (e) {
        _hrError(e);
      }
    }
    joining.dispose();
    employeeCode.dispose();
    salary.dispose();
  }

  Future<void> _markCandidateNoShow(int candidateId) async {
    if (!await OverlayTransition.closeAndSettle(context) || !mounted) return;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Candidate No-Show'),
        content: TextField(
          controller: reason,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'No-Show Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, reason.text.trim().length >= 5),
            child: const Text('Mark No-Show'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(apiClientProvider).post(
          ApiPaths.candidateNoShow(candidateId),
          data: {'reason': reason.text.trim()},
        );
        _refreshHr('Candidate marked as no-show.');
      } catch (e) {
        _hrError(e);
      }
    }
    reason.dispose();
  }

  Future<void> _issueCandidateCredentials(int candidateId) async {
    if (!await OverlayTransition.closeAndSettle(context) || !mounted) return;
    final password = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Issue Login Credentials'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Temporary Password',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
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
            onPressed: () => Navigator.pop(
              context,
              password.text.length >= 10 &&
                  password.text == confirm.text,
            ),
            child: const Text('Issue Credentials'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(apiClientProvider).post(
          ApiPaths.candidateCredentials(candidateId),
          data: {'password': password.text},
        );
        _refreshHr('Candidate login credentials issued and old sessions revoked.');
      } catch (e) {
        _hrError(e);
      }
    }
    password.dispose();
    confirm.dispose();
  }

  Future<void> _initiateSeparation() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    if (app.currentBranchId == null) return;
    try {
      final employees = (await api.get(
        ApiPaths.employees,
        query: {'branch_id': app.currentBranchId},
      ) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (employees.isEmpty) {
        throw Exception('No active employee is available for separation.');
      }
      int? employeeId;
      final date = TextEditingController(text: app.businessDate);
      final reason = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Initiate Separation'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: employeeId,
                    decoration:
                        const InputDecoration(labelText: 'Employee'),
                    items: employees
                        .map(
                          (employee) => DropdownMenuItem(
                            value: int.parse('${employee['id']}'),
                            child: Text(
                              '${employee['full_name']} · ${employee['employee_code']}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setLocal(() => employeeId = value),
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
                    decoration:
                        const InputDecoration(labelText: 'Separation Reason'),
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
                child: const Text('Submit Separation'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        final result = await api.post(
          ApiPaths.employeeSeparation(employeeId!),
          data: {
            'separation_date': date.text.trim(),
            'reason': reason.text.trim(),
          },
        );
        final blockers = result is Map && result['current_blockers'] is List
            ? (result['current_blockers'] as List).length
            : 0;
        _refreshHr(
          blockers == 0
              ? 'Separation submitted for independent review.'
              : 'Separation submitted with $blockers current offboarding blocker(s).',
        );
      }
      date.dispose();
      reason.dispose();
    } catch (e) {
      _hrError(e);
    }
  }

  void _separationActions(Map<String, dynamic> separation) {
    final app = ref.read(appStateProvider);
    final status = '${separation['status'] ?? ''}';
    final id = int.parse('${separation['id']}');
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text('${separation['full_name'] ?? 'Employee'}'),
              subtitle: Text(
                '${separation['employee_code'] ?? ''} · ${separation['separation_date'] ?? ''}',
              ),
            ),
            if (status == 'submitted' &&
                app.can('organization.hr.review'))
              ListTile(
                leading: const Icon(Icons.rule_folder_outlined),
                title: const Text('Review Separation'),
                onTap: () => _reviewSeparation(id),
              ),
            if (status == 'approved' &&
                app.can('organization.hr.review'))
              ListTile(
                leading: const Icon(Icons.task_alt_outlined),
                title: const Text('Complete Separation'),
                onTap: () => _completeSeparation(id),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _reviewSeparation(int separationId) async {
    if (!await OverlayTransition.closeAndSettle(context) || !mounted) return;
    var approve = true;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Review Separation'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: approve,
                  title: Text(
                    approve ? 'Approve separation' : 'Reject separation',
                  ),
                  onChanged: (value) => setLocal(() => approve = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reason,
                  minLines: 2,
                  maxLines: 4,
                  decoration:
                      const InputDecoration(labelText: 'Review Reason'),
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
              onPressed: () =>
                  Navigator.pop(context, reason.text.trim().length >= 5),
              child: const Text('Save Decision'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        final result = await ref.read(apiClientProvider).post(
          ApiPaths.separationReview(separationId),
          data: {
            'approve': approve,
            'reason': reason.text.trim(),
          },
        );
        final blockers = result is Map && result['current_blockers'] is List
            ? (result['current_blockers'] as List).length
            : 0;
        _refreshHr(
          approve
              ? blockers == 0
                  ? 'Separation approved.'
                  : 'Separation approved with $blockers blocker(s) to resolve before completion.'
              : 'Separation rejected.',
        );
      } catch (e) {
        _hrError(e);
      }
    }
    reason.dispose();
  }

  Future<void> _completeSeparation(int separationId) async {
    if (!await OverlayTransition.closeAndSettle(context) || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Separation'),
        content: const Text(
          'This will complete the approved separation and offboard the employee after all blockers are cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiClientProvider).post(
        ApiPaths.separationComplete(separationId),
        data: const {},
      );
      _refreshHr('Separation completed and employee offboarded.');
    } catch (e) {
      _hrError(e);
    }
  }

  void _refreshHr(String text) {
    if (!mounted) return;
    _setOrganizationState(() {
      refresh++;
      message = text;
    });
  }

  void _hrError(Object error) {
    if (!mounted) return;
    _setOrganizationState(() => message = UiError.message(error));
  }
}
