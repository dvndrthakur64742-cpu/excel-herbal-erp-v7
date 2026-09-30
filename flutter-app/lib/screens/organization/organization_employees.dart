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
      final results = await Future.wait([
        api.get(ApiPaths.designations),
        api.get(ApiPaths.roles),
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
                    DropdownButtonFormField<int?>(
                      initialValue: roleId,
                      decoration: const InputDecoration(labelText: 'Role'),
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
                    TextField(
                      controller: joining,
                      decoration: const InputDecoration(
                        labelText: 'Joining Date YYYY-MM-DD',
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
                onPressed: () => Navigator.pop(
                  context,
                  code.text.trim().isNotEmpty &&
                      name.text.trim().isNotEmpty &&
                      designationCode != null &&
                      roleId != null,
                ),
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
      final validation = TransactionGuardrails.employeeCreate(
        employeeCode: employeeCode,
        fullName: fullName,
        designationCode: designationCode,
        roleId: roleId,
        mobile: mobileValue,
        email: emailValue,
        joiningDate: joiningDate,
      );
      if (validation != null) {
        code.dispose();
        name.dispose();
        mobile.dispose();
        email.dispose();
        salary.dispose();
        joining.dispose();
        throw Exception(validation);
      }
      final payload = {
        'assigned_branch_id': app.currentBranchId,
        'employee_code': employeeCode,
        'full_name': fullName,
        'designation_code': designationCode,
        if (roleId != null) 'role_ids': [roleId],
        if (reportingId != null) 'reporting_employee_id': reportingId,
        if (mobileValue.isNotEmpty) 'mobile': mobileValue,
        if (emailValue.isNotEmpty) 'email': emailValue,
        'monthly_salary': double.tryParse(salary.text) ?? 0,
        'joining_date': joiningDate,
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
              subtitle: Text('${employee['designation_code']}'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Branch History'),
              onTap: () => _employeeHistory(id),
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
                TextField(
                  controller: date,
                  decoration: const InputDecoration(
                    labelText: 'Effective Date YYYY-MM-DD',
                  ),
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
