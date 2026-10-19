part of 'organization_screen.dart';

extension _OrganizationEmployeesFeature on _OrganizationScreenState {
  Widget _employeesTab(AppState app, dynamic api) {
    return Column(
      children: [
        if (!app.can('organization.employee.manage'))
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'View only · Employee manage permission required for changes.',
              ),
            ),
          ),
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

  Future<void> _openEmployee360(int employeeId, String employeeName) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Employee360Screen(
          employeeId: employeeId,
          employeeName: employeeName,
        ),
      ),
    );
  }

  void _employeeActions(Map<String, dynamic> employee) {
    final app = ref.read(appStateProvider);
    final id = int.parse('${employee['id']}');
    final assignedBranchId =
        int.tryParse('${employee['assigned_branch_id'] ?? ''}');
    final assignedBranch = app.branches.cast<Map>().firstWhere(
          (branch) => int.tryParse('${branch['id']}') == assignedBranchId,
          orElse: () => const <String, dynamic>{},
        );
    final branchName = '${assignedBranch['name'] ?? ''}'.trim();
    final designation =
        BusinessFormat.value('designation_code', employee['designation_code']);
    final status = BusinessFormat.status(employee['status'] ?? 'active');
    final mobile = '${employee['mobile'] ?? ''}'.trim();
    final email = '${employee['email'] ?? ''}'.trim();
    final joining = BusinessFormat.date(employee['joining_date']);

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .82,
        minChildSize: .55,
        maxChildSize: .96,
        builder: (sheetContext, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: ExcelBrand.primarySoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: ExcelBrand.primaryDark,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${employee['full_name'] ?? 'Employee'}',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${employee['employee_code'] ?? ''}',
                        style: Theme.of(sheetContext).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          Chip(
                            avatar: const Icon(Icons.badge_outlined, size: 17),
                            label: Text(designation),
                          ),
                          Chip(
                            avatar: const Icon(
                              Icons.verified_user_outlined,
                              size: 17,
                            ),
                            label: Text(status),
                          ),
                          if (branchName.isNotEmpty)
                            Chip(
                              avatar:
                                  const Icon(Icons.store_outlined, size: 17),
                              label: Text(branchName),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Employee 360',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'Profile, job movement, documents and access controls in one place.',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: const Text('Mobile'),
                    subtitle: Text(mobile.isEmpty ? 'Not added' : mobile),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: const Text('Email'),
                    subtitle: Text(email.isEmpty ? 'Not added' : email),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Joining Date'),
                    subtitle: Text(joining),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Profile & Job',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  if (app.can('organization.employee.manage'))
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Edit Employee Details'),
                      subtitle: const Text(
                        'Name, mobile, email, designation and joining date',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _editEmployee(employee),
                    ),
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: const Text('Branch History'),
                    subtitle: const Text('View assignment and transfer history'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _employeeHistory(id),
                  ),
                  if (app.can('organization.employee.manage'))
                    ListTile(
                      leading: const Icon(Icons.swap_horiz_rounded),
                      title: const Text('Transfer Assigned Branch'),
                      subtitle: const Text('Move employee with effective date and reason'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _transferEmployee(
                        id,
                        int.parse('${employee['assigned_branch_id']}'),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Records & Access',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  if (app.can('organization.employee.view'))
                    ListTile(
                      leading: const Icon(Icons.insights_outlined),
                      title: const Text('Sales, Points & Stock'),
                      subtitle: const Text(
                        'Monthly sales, incentive points, stock, attendance and authorised history',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openEmployee360(
                        id,
                        '${employee['full_name'] ?? 'Employee'}',
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.folder_shared_outlined),
                    title: const Text('Private Documents'),
                    subtitle: const Text('Employee document vault'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _employeeDocuments(
                      id,
                      '${employee['full_name'] ?? 'Employee'}',
                    ),
                  ),
                  if (app.can('organization.employee.manage'))
                    ListTile(
                      leading: const Icon(Icons.phonelink_lock_outlined),
                      title: const Text('App Login & Sessions'),
                      subtitle: const Text(
                        'Reset login password or revoke active sessions',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _employeeLoginDialog(employee),
                    ),
                  if (app.can('administration.access.manage'))
                    ListTile(
                      leading: const Icon(Icons.account_tree_outlined),
                      title: const Text('Additional Branch Authority'),
                      subtitle: const Text(
                        'Grant or revoke authorised branch access',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _branchAuthority(
                        id,
                        int.parse('${employee['assigned_branch_id']}'),
                      ),
                    ),
                ],
              ),
            ),
            if (app.canAny(const [
                  'payroll.salary.view',
                  'payroll.salary.manage',
                  'payroll.salary.approve',
                ]) ||
                app.can('administration.access.manage')) ...[
              const SizedBox(height: 18),
              Text(
                'Compensation & Access',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (app.canAny(const [
                      'payroll.salary.view',
                      'payroll.salary.manage',
                      'payroll.salary.approve',
                    ]))
                      ListTile(
                        leading: const Icon(Icons.currency_rupee_rounded),
                        title: const Text('Salary Revisions'),
                        subtitle: const Text(
                          'View authorised revision history · maker-checker changes stay in Payroll & Performance',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _employeeSalaryHistory(employee),
                      ),
                    if (app.can('administration.access.manage'))
                      ListTile(
                        leading:
                            const Icon(Icons.admin_panel_settings_outlined),
                        title: const Text('Roles & Permissions'),
                        subtitle: const Text(
                          'Review designation defaults, roles, overrides and effective access',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _employeeAccessSummary(employee),
                      ),
                  ],
                ),
              ),
            ],
            if (!app.can('organization.employee.manage')) ...[
              const SizedBox(height: 14),
              const Text(
                'View only · Employee manage permission required for changes.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editEmployee(Map<String, dynamic> employee) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    final id = int.tryParse('${employee['id']}') ?? 0;
    if (id < 1) return;
    try {
      final designations = (await ref
              .read(apiClientProvider)
              .get(ApiPaths.designations) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
      if (!mounted) return;

      final name = TextEditingController(text: '${employee['full_name'] ?? ''}');
      final mobile =
          TextEditingController(text: '${employee['mobile'] ?? ''}');
      final email = TextEditingController(text: '${employee['email'] ?? ''}');
      final joining =
          TextEditingController(text: '${employee['joining_date'] ?? ''}');
      String designationCode = '${employee['designation_code'] ?? ''}'.trim();
      String? formError;

      final ok = await showModalBottomSheet<bool>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setLocal) => FractionallySizedBox(
            heightFactor: .94,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: ExcelBrand.primarySoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.manage_accounts_outlined,
                          color: ExcelBrand.primaryDark,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Employee',
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              '${employee['employee_code'] ?? ''} · Profile & job details',
                              style: Theme.of(sheetContext).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(sheetContext, false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                    children: [
                      Text(
                        'Personal Details',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final fields = <Widget>[
                            TextField(
                              controller: mobile,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Mobile',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                            ),
                            TextField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                            ),
                          ];
                          if (constraints.maxWidth < 620) {
                            return Column(
                              children: [
                                fields[0],
                                const SizedBox(height: 12),
                                fields[1],
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: fields[0]),
                              const SizedBox(width: 12),
                              Expanded(child: fields[1]),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Job Details',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: designations.any(
                                (d) => '${d['code']}' == designationCode)
                            ? designationCode
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Primary Designation',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        items: designations
                            .map(
                              (d) => DropdownMenuItem<String>(
                                value: '${d['code']}',
                                child: Text('${d['name']} · ${d['code']}'),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) {
                            setLocal(() => designationCode = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      BusinessDateField(
                        controller: joining,
                        label: 'Joining Date',
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Theme.of(sheetContext)
                              .colorScheme
                              .surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'Salary is intentionally separate. Use Salary Revisions so every change remains effective-dated, audited and maker-checker controlled.',
                        ),
                      ),
                      if (formError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          formError!,
                          style: TextStyle(
                            color: Theme.of(sheetContext).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: const BoxDecoration(
                      color: ExcelBrand.surface,
                      border: Border(
                        top: BorderSide(color: ExcelBrand.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.pop(sheetContext, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () {
                              final n = name.text.trim();
                              final m = mobile.text
                                  .trim()
                                  .replaceAll(RegExp(r'\D+'), '');
                              final e = email.text.trim();
                              final j = joining.text.trim();
                              if (n.isEmpty) {
                                setLocal(
                                  () =>
                                      formError = 'Employee name required hai.',
                                );
                                return;
                              }
                              if (m.isNotEmpty &&
                                  (m.length < 8 || m.length > 15)) {
                                setLocal(
                                  () => formError =
                                      'Mobile 8 se 15 digits hona chahiye.',
                                );
                                return;
                              }
                              if (e.isNotEmpty) {
                                final at = e.indexOf('@');
                                final dot = e.lastIndexOf('.');
                                if (at <= 0 ||
                                    dot <= at + 1 ||
                                    dot >= e.length - 1) {
                                  setLocal(
                                    () => formError =
                                        'Valid email enter karein.',
                                  );
                                  return;
                                }
                              }
                              if (designationCode.isEmpty) {
                                setLocal(
                                  () =>
                                      formError = 'Designation select karein.',
                                );
                                return;
                              }
                              if (!CommercialIntegrity.validBusinessDate(j)) {
                                setLocal(
                                  () => formError =
                                      'Joining Date valid YYYY-MM-DD format me honi chahiye.',
                                );
                                return;
                              }
                              Navigator.pop(sheetContext, true);
                            },
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save Employee'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (ok != true) {
        name.dispose();
        mobile.dispose();
        email.dispose();
        joining.dispose();
        return;
      }

      final payload = {
        'full_name': name.text.trim(),
        'mobile': mobile.text.trim(),
        'email': email.text.trim(),
        'designation_code': designationCode,
        'joining_date': joining.text.trim(),
      };
      name.dispose();
      mobile.dispose();
      email.dispose();
      joining.dispose();

      await ref
          .read(apiClientProvider)
          .post(ApiPaths.employeeUpdate(id), data: payload);
      if (mounted) {
        _setOrganizationState(() {
          refresh++;
          message = 'Employee details update ho gaye.';
        });
      }
    } catch (e) {
      if (mounted) {
        _setOrganizationState(() => message = UiError.message(e));
      }
    }
  }

  Future<void> _employeeSalaryHistory(
    Map<String, dynamic> employee,
  ) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    final id = int.tryParse('${employee['id']}') ?? 0;
    if (id < 1) return;
    try {
      final rows = (await ref
              .read(apiClientProvider)
              .get(ApiPaths.salaryRevisions(id)) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (sheetContext) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .78,
          minChildSize: .5,
          maxChildSize: .95,
          builder: (sheetContext, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
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
                'Salary Revisions · ${employee['full_name'] ?? 'Employee'}',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                '${employee['employee_code'] ?? ''} · Audited effective-dated history',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ExcelBrand.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Salary changes are created/reviewed only in Payroll & Performance → Salary. Employee 360 shows the same authorised history without creating a second workflow.',
                  style: TextStyle(
                    color: ExcelBrand.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text('No salary revision history.')),
                )
              else
                ...rows.map((row) {
                  final status =
                      BusinessFormat.status(row['status'] ?? 'pending');
                  final amount = row['monthly_salary'];
                  final effective = row['effective_from'];
                  final reason = '${row['reason'] ?? ''}'.trim();
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.currency_rupee_rounded),
                      title: Text(
                        '${BusinessFormat.money(amount)} · ${BusinessFormat.date(effective)}',
                      ),
                      subtitle: Text(
                        reason.isEmpty ? status : '$reason · $status',
                      ),
                      trailing: Chip(label: Text(status)),
                    ),
                  );
                }),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        _setOrganizationState(() => message = UiError.message(e));
      }
    }
  }

  Future<void> _employeeAccessSummary(
    Map<String, dynamic> employee,
  ) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    final id = int.tryParse('${employee['id']}') ?? 0;
    if (id < 1) return;
    try {
      final detail = Map<String, dynamic>.from(
        await ref.read(apiClientProvider).get(ApiPaths.employeeAccess(id))
            as Map,
      );
      final roles = ((detail['roles'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
      final defaults = ((detail['designation_defaults'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(growable: false);
      final effective = ((detail['effective_capabilities'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(growable: false);
      final overrides = ((detail['overrides'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (sheetContext) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .82,
          minChildSize: .55,
          maxChildSize: .96,
          builder: (sheetContext, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
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
                'Roles & Permissions · ${employee['full_name'] ?? 'Employee'}',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                '${employee['employee_code'] ?? ''} · ${employee['designation_code'] ?? ''}',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ExcelBrand.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Employee 360 is the visibility layer. Role and Grant/Deny changes stay in Administration → Access so access logic has one canonical workflow.',
                  style: TextStyle(
                    color: ExcelBrand.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('${roles.length} assigned roles')),
                  Chip(label: Text('${defaults.length} designation defaults')),
                  Chip(label: Text('${effective.length} effective permissions')),
                  Chip(label: Text('${overrides.length} overrides')),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Assigned Roles',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              if (roles.isEmpty)
                const Text('No additional roles assigned.')
              else
                ...roles.map(
                  (role) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.security_outlined),
                      title: Text('${role['name'] ?? role['code'] ?? 'Role'}'),
                      subtitle: Text('${role['code'] ?? ''}'),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                'Individual Overrides',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              if (overrides.isEmpty)
                const Text('No individual Grant/Deny overrides.')
              else
                ...overrides.map(
                  (item) => Card(
                    child: ListTile(
                      leading: Icon(
                        '${item['effect']}' == 'deny'
                            ? Icons.block_outlined
                            : Icons.add_task_outlined,
                      ),
                      title: Text('${item['capability'] ?? ''}'),
                      trailing: Chip(
                        label: Text(
                          BusinessFormat.status(item['effect'] ?? 'inherit'),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        _setOrganizationState(() => message = UiError.message(e));
      }
    }
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
