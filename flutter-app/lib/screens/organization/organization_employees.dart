part of 'organization_screen.dart';

extension _OrganizationEmployeesFeature on _OrganizationScreenState {
  Widget _employeesTab(AppState app, dynamic api) {
    return Column(
      children: [
        if (app.can('organization.employee.manage'))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: app.currentBranchId == null ? null : _createEmployee,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('New Employee'),
              ),
            ),
          ),
        Expanded(
          child: app.currentBranchId == null
              ? const Center(child: Text('Branch select karein.'))
              : AsyncPanel(
                  key: ValueKey('employees-${app.currentBranchId}-$refresh'),
                  future: api.get(
                    ApiPaths.employees,
                    query: {'branch_id': app.currentBranchId},
                  ),
                  emptyMessage: 'Selected branch me active employee nahi hai.',
                  builder: (context, data) => RecordsList(
                    recordType: 'employee',
                    rows: (data as List)
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList(),
                    onTap: _employeeActions,
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _createEmployee() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    try {
      final canManageAccess = app.can('administration.access.manage');
      final canManageSalary = app.can('payroll.salary.manage');
      final results = await Future.wait([
        api.get(ApiPaths.designations),
        canManageAccess
            ? api.get(ApiPaths.roles)
            : Future<dynamic>.value(const <dynamic>[]),
        api.get(ApiPaths.employees, query: {'branch_id': app.currentBranchId}),
      ]);
      final designations = (results[0] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final roles = (results[1] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final employees = (results[2] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      String? designationCode;
      int? roleId;
      int? reportingId;
      final code = TextEditingController();
      final name = TextEditingController();
      final mobile = TextEditingController();
      final email = TextEditingController();
      final salary = TextEditingController(text: '0');
      final joining = TextEditingController(text: app.businessDate);
      String? formError;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('New Employee'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: code,
                      decoration: const InputDecoration(
                        labelText: 'Employee Code',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: designationCode,
                      decoration: const InputDecoration(
                        labelText: 'Designation',
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
                    if (canManageAccess) ...[
                      DropdownButtonFormField<int?>(
                        initialValue: roleId,
                        decoration: const InputDecoration(
                          labelText: 'Additional Role (optional)',
                        ),
                        items: roles
                            .map(
                              (r) => DropdownMenuItem<int?>(
                                value: int.parse('${r['id']}'),
                                child: Text('${r['name']}'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setLocal(() => roleId = v),
                      ),
                      const SizedBox(height: 10),
                    ],
                    DropdownButtonFormField<int?>(
                      initialValue: reportingId,
                      decoration: const InputDecoration(
                        labelText: 'Reporting Manager (optional)',
                      ),
                      items: <DropdownMenuItem<int?>>[
                        const DropdownMenuItem(
                          value: null,
                          child: Text('No reporting manager'),
                        ),
                        ...employees.map(
                          (e) => DropdownMenuItem(
                            value: int.parse('${e['id']}'),
                            child: Text('${e['full_name']}'),
                          ),
                        ),
                      ],
                      onChanged: (v) => setLocal(() => reportingId = v),
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
                    if (canManageSalary) ...[
                      TextField(
                        controller: salary,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Monthly Salary',
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    BusinessDateField(
                      controller: joining,
                      label: 'Joining Date',
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Login credentials are issued separately after the employee record is created.',
                      ),
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
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
                  final validation = TransactionGuardrails.employeeCreate(
                    employeeCode: code.text.trim(),
                    fullName: name.text.trim(),
                    designationCode: designationCode,
                    mobile: mobile.text.trim(),
                    email: email.text.trim(),
                    joiningDate: joining.text.trim(),
                  );
                  final salaryError = canManageSalary
                      ? TransactionGuardrails.nonNegativeMoneyText(
                          salary.text,
                          label: 'Monthly Salary',
                        )
                      : null;
                  final error = validation ?? salaryError;
                  if (error != null) {
                    setLocal(() => formError = error);
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      );
      if (ok != true) {
        code.dispose();
        name.dispose();
        mobile.dispose();
        email.dispose();
        salary.dispose();
        joining.dispose();
        return;
      }
      final employeeCode = code.text.trim();
      final fullName = name.text.trim();
      final mobileValue = mobile.text.trim();
      final emailValue = email.text.trim();
      final joiningDate = joining.text.trim();
      final salaryValue =
          canManageSalary ? double.parse(salary.text.trim()) : null;
      final payload = {
        'assigned_branch_id': app.currentBranchId,
        'employee_code': employeeCode,
        'full_name': fullName,
        'designation_code': designationCode,
        if (roleId != null) 'role_ids': [roleId],
        if (reportingId != null) 'reporting_employee_id': reportingId,
        if (mobileValue.isNotEmpty) 'mobile': mobileValue,
        if (emailValue.isNotEmpty) 'email': emailValue,
        if (canManageSalary) 'monthly_salary': salaryValue,
        'joining_date': joiningDate,
        'provision_login': false,
      };
      code.dispose();
      name.dispose();
      mobile.dispose();
      email.dispose();
      salary.dispose();
      joining.dispose();
      await api.post(ApiPaths.employees, data: payload);
      if (mounted)
        _setOrganizationState(() {
          refresh++;
          message = 'Employee create ho gaya.';
        });
    } catch (e) {
      if (mounted) _setOrganizationState(() => message = UiError.message(e));
    }
  }

  void _employeeActions(Map<String, dynamic> employee) {
    final app = ref.read(appStateProvider);
    final id = int.parse('${employee['id']}');
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text(
                '${employee['full_name']} · ${employee['employee_code']}',
              ),
              subtitle: Text(BusinessFormat.value('designation_code', employee['designation_code'])),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Branch History'),
              onTap: () => _employeeHistory(id),
            ),
            ListTile(
              leading: const Icon(Icons.folder_shared_outlined),
              title: const Text('Private Documents'),
              onTap: () => _employeeDocuments(
                id,
                '${employee['full_name'] ?? 'Employee'}',
              ),
            ),
            if (app.can('organization.employee.manage'))
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Transfer Assigned Branch'),
                onTap: () => _transferEmployee(
                  id,
                  int.parse('${employee['assigned_branch_id']}'),
                ),
              ),
            if (app.can('organization.employee.manage'))
              ListTile(
                leading: const Icon(Icons.phonelink_lock_outlined),
                title: const Text('App Login & Sessions'),
                subtitle: const Text('Reset login password or revoke active sessions'),
                onTap: () => _employeeLoginDialog(employee),
              ),
            if (app.can('administration.access.manage'))
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('Additional Branch Authority'),
                onTap: () => _branchAuthority(
                  id,
                  int.parse('${employee['assigned_branch_id']}'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _employeeLoginDialog(
    Map<String, dynamic> employee,
  ) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    final id = int.tryParse('${employee['id']}') ?? 0;
    if (id < 1) return;
    try {
      final status = Map<String, dynamic>.from(
        await ref.read(apiClientProvider).get(ApiPaths.employeeLoginStatus(id))
            as Map,
      );
      if (!mounted) return;
      final password = TextEditingController();
      String? validation;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setLocal) => AlertDialog(
            title: Text('${employee['full_name']} · App Login'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      status['login_enabled'] == true
                          ? Icons.verified_user_outlined
                          : Icons.person_off_outlined,
                    ),
                    title: Text(
                      status['login_enabled'] == true
                          ? 'Mobile login enabled'
                          : 'Mobile login not provisioned',
                    ),
                    subtitle: Text(
                      'Active sessions: ${status['active_sessions'] ?? 0}',
                    ),
                  ),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Set / Reset Password',
                      helperText: 'Minimum 10 characters',
                    ),
                  ),
                  if (validation != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        validation!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Text(
                    'Share credentials only through an approved secure channel. Password reset automatically revokes existing mobile sessions.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: dialogContext,
                    builder: (confirmContext) => AlertDialog(
                      title: const Text('Revoke employee sessions?'),
                      content: const Text(
                        'All active mobile sessions for this employee will be signed out.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(confirmContext, true),
                          child: const Text('Revoke Sessions'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  try {
                    await ref.read(apiClientProvider).post(
                      ApiPaths.employeeRevokeSessions(id),
                      data: const {},
                    );
                    if (!mounted || !dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    _setOrganizationState(() {
                      refresh++;
                      message = 'Employee mobile sessions revoked.';
                    });
                  } catch (e) {
                    if (dialogContext.mounted) {
                      setLocal(() => validation = UiError.message(e));
                    }
                  }
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Revoke Sessions'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (password.text.length < 10) {
                    setLocal(
                      () => validation =
                          'Password must contain at least 10 characters.',
                    );
                    return;
                  }
                  try {
                    await ref.read(apiClientProvider).post(
                      ApiPaths.employeeCredentials(id),
                      data: {'password': password.text},
                    );
                    if (!mounted || !dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    _setOrganizationState(() {
                      refresh++;
                      message = 'Employee app login password updated.';
                    });
                  } catch (e) {
                    if (dialogContext.mounted) {
                      setLocal(() => validation = UiError.message(e));
                    }
                  }
                },
                icon: const Icon(Icons.password_rounded),
                label: const Text('Save Password'),
              ),
            ],
          ),
        ),
      );
      password.dispose();
    } catch (e) {
      if (mounted) {
        _setOrganizationState(() => message = UiError.message(e));
      }
    }
  }

  Future<void> _employeeHistory(int id) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    try {
      final rows = (await ref
              .read(apiClientProvider)
              .get(ApiPaths.employeeHistory(id)) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Employee Branch History'),
          content: SizedBox(
            width: 600,
            height: 380,
            child: RecordsList(recordType: 'branch_history', rows: rows),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _setOrganizationState(() => message = UiError.message(e));
    }
  }

  Future<void> _transferEmployee(int employeeId, int currentBranch) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    final app = ref.read(appStateProvider);
    int? branchId;
    final date = TextEditingController(text: app.businessDate);
    final reason = TextEditingController();
    final available = app.branches
        .where((b) => int.parse('${b['id']}') != currentBranch)
        .toList();
    if (available.isEmpty) {
      _setOrganizationState(
        () => message =
            'Transfer ke liye dusri authorised branch available nahi hai.',
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Transfer Employee'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: branchId,
                  decoration: const InputDecoration(labelText: 'New Branch'),
                  items: available
                      .map(
                        (b) => DropdownMenuItem(
                          value: int.parse('${b['id']}'),
                          child: Text('${b['name']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => branchId = v),
                ),
                const SizedBox(height: 10),
                BusinessDateField(
                  controller: date,
                  label: 'Transfer Effective Date',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reason,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Transfer Reason',
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
                branchId != null && reason.text.trim().length >= 5,
              ),
              child: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );
    final payload = {
      'branch_id': branchId,
      'effective_date': date.text.trim(),
      'reason': reason.text.trim(),
    };
    date.dispose();
    reason.dispose();
    if (ok != true) return;
    try {
      await ref
          .read(apiClientProvider)
          .post(ApiPaths.employeeTransfer(employeeId), data: payload);
      if (mounted)
        _setOrganizationState(() {
          refresh++;
          message = 'Employee branch transfer complete; history preserved.';
        });
    } catch (e) {
      if (mounted) _setOrganizationState(() => message = UiError.message(e));
    }
  }

  Future<void> _branchAuthority(int employeeId, int assignedBranch) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    final app = ref.read(appStateProvider);
    int? branchId;
    var grant = true;
    final branches = app.branches
        .where((b) => int.parse('${b['id']}') != assignedBranch)
        .toList();
    if (branches.isEmpty) {
      _setOrganizationState(
        () => message =
            'Additional authority ke liye dusri authorised branch available nahi hai.',
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Additional Branch Authority'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: branchId,
                  decoration: const InputDecoration(labelText: 'Branch'),
                  items: branches
                      .map(
                        (b) => DropdownMenuItem(
                          value: int.parse('${b['id']}'),
                          child: Text('${b['name']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => branchId = v),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: grant,
                  title: Text(grant ? 'Grant authority' : 'Revoke authority'),
                  onChanged: (v) => setLocal(() => grant = v),
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
              onPressed: () => Navigator.pop(context, branchId != null),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).post(
        ApiPaths.branchAuthority,
        data: {
          'employee_id': employeeId,
          'branch_id': branchId,
          'active': grant,
        },
      );
      if (mounted)
        _setOrganizationState(
          () => message = grant
              ? 'Additional branch authority granted.'
              : 'Additional branch authority revoked.',
        );
    } catch (e) {
      if (mounted) _setOrganizationState(() => message = UiError.message(e));
    }
  }

}
