import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/commercial_integrity.dart';
import '../../core/providers.dart';
import '../../core/overlay_transition.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';
import '../../widgets/module_workspace.dart';
import '../common/record_detail_screen.dart';

class OrganizationScreen extends ConsumerStatefulWidget {
  const OrganizationScreen({super.key});
  @override
  ConsumerState<OrganizationScreen> createState() => _OrganizationScreenState();
}

class _OrganizationScreenState extends ConsumerState<OrganizationScreen> {
  int refresh = 0;
  String? message;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final tabs = <(String, Widget)>[];
    if (app.canAny(const [
      'organization.branch.view',
      'organization.branch.manage',
    ])) {
      tabs.add(('Branches', _branchesTab(app)));
    }
    if (app.canAny(const [
      'organization.employee.view',
      'organization.employee.manage',
    ])) {
      tabs.add(('Employees', _employeesTab(app, api)));
    }
    if (app.canAny(const ['catalog.product.view', 'catalog.product.manage'])) {
      tabs.add(('Products', _productsTab(app, api)));
    }
    if (tabs.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No authorised organization functions.')),
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Organization & Masters'),
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
                  title: 'Organization & Masters',
                  subtitle:
                      'Branches, employees and product masters in one authorised workspace.',
                  icon: Icons.corporate_fare_outlined,
                  contextLabel: app.currentBranchName,
                ),
              ),
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
                  title: 'Master Data Workspace',
                  subtitle:
                      'Use the tabs below to manage authorised organization records.',
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

  Widget _branchesTab(AppState app) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (app.can('organization.branch.manage'))
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _createBranch,
              icon: const Icon(Icons.add_business),
              label: const Text('New Branch'),
            ),
          ),
        if (app.can('organization.branch.manage')) const SizedBox(height: 12),
        Text(
          'Authorised Branches',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        ...app.branches.map(
          (b) => Card(
            child: ListTile(
              leading: Icon(
                '${b['is_head_office']}' == '1'
                    ? Icons.corporate_fare
                    : Icons.store_outlined,
              ),
              title: Text('${b['name']}'),
              subtitle: Text('${b['code']}'),
              trailing: int.tryParse('${b['id']}') == app.currentBranchId
                  ? const Chip(label: Text('Current'))
                  : const Icon(Icons.chevron_right),
              onTap: () => _openBranchDetail(Map<String, dynamic>.from(b)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openBranchDetail(Map<String, dynamic> branch) async {
    final title = '${branch['name'] ?? 'Branch'}';
    if (MediaQuery.sizeOf(context).width >= 820) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: SizedBox(
            width: 680,
            height: MediaQuery.sizeOf(context).height * .72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Branch Details',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: BusinessRecordDetailView(
                    row: branch,
                    title: title,
                    recordType: 'branch',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RecordDetailScreen(row: branch, title: title, recordType: 'branch'),
      ),
    );
  }

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

  Widget _productsTab(AppState app, dynamic api) {
    return Column(
      children: [
        if (app.can('catalog.product.manage'))
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _createProduct,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('New Product'),
              ),
            ),
          ),
        Expanded(
          child: AsyncPanel(
            key: ValueKey('products-$refresh'),
            future: api.get(ApiPaths.products),
            emptyMessage: 'Product master empty hai.',
            builder: (context, data) => RecordsList(
              recordType: 'product',
              rows: (data as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
              onTap: _productActions,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createBranch() async {
    final code = TextEditingController();
    final name = TextEditingController();
    var headOffice = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New Branch'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  decoration: const InputDecoration(labelText: 'Branch Code'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Branch Name'),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: headOffice,
                  title: const Text('Head Office'),
                  onChanged: (v) => setLocal(() => headOffice = v == true),
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
                code.text.trim().isNotEmpty && name.text.trim().isNotEmpty,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    final payload = {
      'code': code.text.trim(),
      'name': name.text.trim(),
      'is_head_office': headOffice,
    };
    code.dispose();
    name.dispose();
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).post(ApiPaths.branches, data: payload);
      await ref.read(appStateProvider.notifier).refreshBootstrap();
      if (mounted)
        setState(
          () => message =
              'Branch create ho gaya; creator authority bootstrap ho gayi.',
        );
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
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
      final payload = {
        'assigned_branch_id': app.currentBranchId,
        'employee_code': code.text.trim(),
        'full_name': name.text.trim(),
        'designation_code': designationCode,
        if (roleId != null) 'role_ids': [roleId],
        if (reportingId != null) 'reporting_employee_id': reportingId,
        if (mobile.text.trim().isNotEmpty) 'mobile': mobile.text.trim(),
        if (email.text.trim().isNotEmpty) 'email': email.text.trim(),
        'monthly_salary': double.tryParse(salary.text) ?? 0,
        'joining_date': joining.text.trim(),
      };
      code.dispose();
      name.dispose();
      mobile.dispose();
      email.dispose();
      salary.dispose();
      joining.dispose();
      if (ok != true) return;
      await api.post(ApiPaths.employees, data: payload);
      if (mounted)
        setState(() {
          refresh++;
          message = 'Employee create ho gaya.';
        });
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
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
      if (mounted) setState(() => message = UiError.message(e));
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
      setState(
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
        setState(() {
          refresh++;
          message = 'Employee branch transfer complete; history preserved.';
        });
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
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
      setState(
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
        setState(
          () => message = grant
              ? 'Additional branch authority granted.'
              : 'Additional branch authority revoked.',
        );
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _createProduct() async {
    final sku = TextEditingController();
    final name = TextEditingController();
    final uom = TextEditingController(text: 'PCS');
    final mrp = TextEditingController(text: '0');
    final sale = TextEditingController(text: '0');
    final ho = TextEditingController(text: '0');
    final bm = TextEditingController(text: '0');
    final salary = TextEditingController(text: '0');
    final office = TextEditingController(text: '0');
    final points = TextEditingController(text: '0');
    final purchaseCost = TextEditingController(text: '0');
    final controllers = [
      sku,
      name,
      uom,
      mrp,
      sale,
      ho,
      bm,
      salary,
      office,
      points,
      purchaseCost,
    ];
    var batchMode = 'optional';
    var expiryTracking = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New Product'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: sku,
                    decoration: const InputDecoration(labelText: 'SKU'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration:
                        const InputDecoration(labelText: 'Product Name'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: uom,
                    decoration: const InputDecoration(labelText: 'UOM'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: batchMode,
                    decoration:
                        const InputDecoration(labelText: 'Batch Tracking'),
                    items: const [
                      DropdownMenuItem(value: 'off', child: Text('Off')),
                      DropdownMenuItem(
                          value: 'optional', child: Text('Optional')),
                      DropdownMenuItem(
                          value: 'required', child: Text('Required')),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => batchMode = v);
                    },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: expiryTracking,
                    title: const Text('Expiry Tracking'),
                    onChanged: (v) =>
                        setLocal(() => expiryTracking = v == true),
                  ),
                  _moneyPair(mrp, 'MRP', sale, 'Sale Price'),
                  const SizedBox(height: 10),
                  _moneyPair(ho, 'HO Amount', bm, 'BM Profit'),
                  const SizedBox(height: 10),
                  _moneyPair(salary, 'Salary Fund', office, 'Office Expense'),
                  const SizedBox(height: 10),
                  _moneyPair(
                      points, 'Points', purchaseCost, 'Initial Purchase Cost'),
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'Rule: Sale Price ≤ MRP and distribution total must equal Sale Price.'),
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
                sku.text.trim().isNotEmpty && name.text.trim().isNotEmpty,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) {
      _disposeControllers(controllers);
      return;
    }
    try {
      final commercial = _commercialValues(
        mrp: mrp,
        sale: sale,
        ho: ho,
        bm: bm,
        salary: salary,
        office: office,
        points: points,
        purchaseCost: purchaseCost,
      );
      final payload = {
        'sku': sku.text.trim(),
        'name': name.text.trim(),
        'uom': uom.text.trim(),
        'batch_tracking': batchMode,
        'expiry_tracking': expiryTracking,
        ...commercial.toPayload(),
      };
      await ref.read(apiClientProvider).post(ApiPaths.products, data: payload);
      if (mounted) {
        setState(() {
          refresh++;
          message = 'Product create ho gaya.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    } finally {
      _disposeControllers(controllers);
    }
  }

  void _productActions(Map<String, dynamic> product) {
    final app = ref.read(appStateProvider);
    final id = int.parse('${product['id']}');
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text('${product['name']} · ${product['sku']}'),
              subtitle: Text(
                'Sale ₹${product['sale_price'] ?? 0} · Batch ${product['batch_tracking']}',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Commercial History'),
              onTap: () => _productHistory(id),
            ),
            if (app.can('catalog.product.manage'))
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('New Commercial Revision'),
                onTap: () => _commercialRevision(product),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _productHistory(int id) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    try {
      final rows = (await ref
              .read(apiClientProvider)
              .get(ApiPaths.productHistory(id)) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Commercial History'),
          content: SizedBox(
            width: 680,
            height: 420,
            child: RecordsList(recordType: 'product_history', rows: rows),
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
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _commercialRevision(Map<String, dynamic> product) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    final app = ref.read(appStateProvider);
    try {
      final history = (await ref
                  .read(apiClientProvider)
                  .get(ApiPaths.productHistory(int.parse('${product['id']}')))
              as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      final latest = history.isNotEmpty ? history.first : product;
      final mrp = TextEditingController(
          text: '${latest['mrp'] ?? product['mrp'] ?? 0}');
      final sale = TextEditingController(
          text: '${latest['sale_price'] ?? product['sale_price'] ?? 0}');
      final ho = TextEditingController(
          text: '${latest['ho_amount'] ?? product['ho_amount'] ?? 0}');
      final bm = TextEditingController(
          text: '${latest['bm_profit'] ?? product['bm_profit'] ?? 0}');
      final salary = TextEditingController(
          text: '${latest['salary_fund'] ?? product['salary_fund'] ?? 0}');
      final office = TextEditingController(
          text:
              '${latest['office_expense'] ?? product['office_expense'] ?? 0}');
      final points = TextEditingController(
          text: '${latest['points'] ?? product['points'] ?? 0}');
      final purchaseCost = TextEditingController(
          text: '${latest['purchase_cost'] ?? product['purchase_cost'] ?? 0}');
      final effectiveDate = TextEditingController(text: app.businessDate);
      final reason = TextEditingController();
      final controllers = [
        mrp,
        sale,
        ho,
        bm,
        salary,
        office,
        points,
        purchaseCost,
        effectiveDate,
        reason,
      ];
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Commercial Revision · ${product['name']}'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _moneyPair(mrp, 'MRP', sale, 'Sale Price'),
                  const SizedBox(height: 10),
                  _moneyPair(ho, 'HO Amount', bm, 'BM Profit'),
                  const SizedBox(height: 10),
                  _moneyPair(salary, 'Salary Fund', office, 'Office Expense'),
                  const SizedBox(height: 10),
                  _moneyPair(points, 'Points', purchaseCost, 'Purchase Cost'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: effectiveDate,
                    decoration: const InputDecoration(
                      labelText: 'Effective Date YYYY-MM-DD',
                      helperText: 'Default ERP business date',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reason,
                    minLines: 2,
                    maxLines: 4,
                    decoration:
                        const InputDecoration(labelText: 'Change Reason'),
                  ),
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'Rule: Sale Price ≤ MRP and HO + BM + Salary Fund + Office Expense = Sale Price.'),
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
                    CommercialIntegrity.validBusinessDate(effectiveDate.text),
              ),
              child: const Text('Save Revision'),
            ),
          ],
        ),
      );
      if (ok != true) {
        _disposeControllers(controllers);
        return;
      }
      try {
        if (!CommercialIntegrity.validBusinessDate(effectiveDate.text)) {
          throw Exception(
              'Effective Date valid YYYY-MM-DD format me honi chahiye.');
        }
        final commercial = _commercialValues(
          mrp: mrp,
          sale: sale,
          ho: ho,
          bm: bm,
          salary: salary,
          office: office,
          points: points,
          purchaseCost: purchaseCost,
        );
        await ref.read(apiClientProvider).post(
          ApiPaths.productRevision(int.parse('${product['id']}')),
          data: {
            ...commercial.toPayload(),
            if (effectiveDate.text.trim() != app.businessDate)
              'effective_from': '${effectiveDate.text.trim()} 00:00:00',
            'reason': reason.text.trim(),
          },
        );
        if (mounted) {
          setState(() {
            refresh++;
            message = 'Commercial revision saved.';
          });
        }
      } finally {
        _disposeControllers(controllers);
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  CommercialValues _commercialValues({
    required TextEditingController mrp,
    required TextEditingController sale,
    required TextEditingController ho,
    required TextEditingController bm,
    required TextEditingController salary,
    required TextEditingController office,
    required TextEditingController points,
    required TextEditingController purchaseCost,
  }) {
    final parsedMrp = CommercialIntegrity.parseRequired(mrp.text);
    final parsedSale = CommercialIntegrity.parseRequired(sale.text);
    final parsedHo = CommercialIntegrity.parseRequired(ho.text);
    final parsedBm = CommercialIntegrity.parseRequired(bm.text);
    final parsedSalary = CommercialIntegrity.parseRequired(salary.text);
    final parsedOffice = CommercialIntegrity.parseRequired(office.text);
    final parsedPoints = CommercialIntegrity.parseRequired(points.text);
    final parsedPurchase = CommercialIntegrity.parseRequired(purchaseCost.text);
    final error = CommercialIntegrity.validate(
      mrp: parsedMrp,
      salePrice: parsedSale,
      hoAmount: parsedHo,
      bmProfit: parsedBm,
      salaryFund: parsedSalary,
      officeExpense: parsedOffice,
      points: parsedPoints,
      purchaseCost: parsedPurchase,
    );
    if (error != null) throw Exception(error);
    return CommercialIntegrity.values(
      mrp: parsedMrp!,
      salePrice: parsedSale!,
      hoAmount: parsedHo!,
      bmProfit: parsedBm!,
      salaryFund: parsedSalary!,
      officeExpense: parsedOffice!,
      points: parsedPoints!,
      purchaseCost: parsedPurchase!,
    );
  }

  void _disposeControllers(Iterable<TextEditingController> controllers) {
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  Widget _moneyPair(
    TextEditingController a,
    String aLabel,
    TextEditingController b,
    String bLabel,
  ) {
    return LayoutBuilder(
      builder: (context, c) {
        final first = TextField(
          controller: a,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: aLabel),
        );
        final second = TextField(
          controller: b,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: bLabel),
        );
        if (c.maxWidth < 480)
          return Column(children: [first, const SizedBox(height: 10), second]);
        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 10),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}
