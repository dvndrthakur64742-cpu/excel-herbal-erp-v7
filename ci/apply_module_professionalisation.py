from pathlib import Path

ROOT = Path('flutter-app')


def read(path):
    return path.read_text()


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def add_import(path, anchor, new_import):
    text = read(path)
    if new_import in text:
        return
    if anchor not in text:
        raise SystemExit(f'Import anchor missing in {path}: {anchor}')
    write(path, text.replace(anchor, anchor + new_import, 1))


def replace_region(path, start_marker, end_marker, replacement):
    text = read(path)
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f'Start marker missing in {path}: {start_marker[:80]!r}')
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f'End marker missing in {path}: {end_marker[:80]!r}')
    write(path, text[:start] + replacement + text[end:])


module_workspace = r'''import 'package:flutter/material.dart';

class ModuleWorkspaceHeader extends StatelessWidget {
  const ModuleWorkspaceHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.contextLabel,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String contextLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      contextLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ModuleActionPanel extends StatelessWidget {
  const ModuleActionPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            );
            final actionWrap = Wrap(
              spacing: 7,
              runSpacing: 7,
              alignment: WrapAlignment.start,
              children: actions,
            );
            if (constraints.maxWidth < 680) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  copy,
                  const SizedBox(height: 9),
                  actionWrap,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: copy),
                const SizedBox(width: 14),
                Flexible(flex: 2, child: actionWrap),
              ],
            );
          },
        ),
      ),
    );
  }
}

class ModuleSectionHeader extends StatelessWidget {
  const ModuleSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}

class ModuleMessageBanner extends StatelessWidget {
  const ModuleMessageBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 17, color: scheme.onSecondaryContainer),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
'''
write(ROOT / 'lib/widgets/module_workspace.dart', module_workspace)

# SALES
sales = ROOT / 'lib/screens/sales/sales_screen.dart'
add_import(sales, "import '../../widgets/records_list.dart';\n", "import '../../widgets/module_workspace.dart';\n")
sales_build = r'''  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final actions = <Widget>[
      if (app.can('sales.create'))
        FilledButton.icon(
          onPressed: app.currentBranchId == null ? null : _counterSale,
          icon: const Icon(Icons.point_of_sale_outlined, size: 18),
          label: const Text('Counter Sale'),
        ),
      if (app.can('sales.create'))
        OutlinedButton.icon(
          onPressed: app.currentBranchId == null ? null : _createCustomer,
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('New Customer'),
        ),
      if (app.can('sales.receipt.create'))
        OutlinedButton.icon(
          onPressed: app.currentBranchId == null ? null : _receipt,
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: const Text('Receipt'),
        ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Sales')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: ModuleWorkspaceHeader(
                title: 'Sales Desk',
                subtitle: 'Counter billing, customer accounts and collections.',
                icon: Icons.point_of_sale_outlined,
                contextLabel: 'Business date · ${app.businessDate}',
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: BranchSelector(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: ModuleActionPanel(
                title: 'Transactions',
                subtitle: 'Start billing, maintain customers or post a collection.',
                actions: actions,
              ),
            ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ModuleMessageBanner(message: message!),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 7),
              child: ModuleSectionHeader(
                title: 'Customer Accounts',
                subtitle: 'Registered customer master for the selected branch.',
              ),
            ),
            Expanded(
              child: app.currentBranchId == null
                  ? const Center(child: Text('Select an authorised branch.'))
                  : AsyncPanel(
                      key: ValueKey('${app.currentBranchId}-$refresh'),
                      future: api.get(
                        ApiPaths.customers,
                        query: {'branch_id': app.currentBranchId},
                      ),
                      emptyMessage: 'No customer accounts are available.',
                      builder: (context, data) => RecordsList(
                        recordType: 'customer',
                        rows: (data as List)
                            .map((e) => Map<String, dynamic>.from(e as Map))
                            .toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

'''
replace_region(sales, '  @override\n  Widget build(BuildContext context) {', '  Future<void> _createCustomer()', sales_build)

# PURCHASE
purchase = ROOT / 'lib/screens/purchase/purchase_screen.dart'
add_import(purchase, "import '../../widgets/records_list.dart';\n", "import '../../widgets/module_workspace.dart';\n")
purchase_build = r'''  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final actions = <Widget>[
      if (app.can('purchase.create'))
        FilledButton.icon(
          onPressed: app.currentBranchId == null ? null : _newBill,
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: const Text('Purchase Entry'),
        ),
      if (app.can('finance.supplier_payment.create'))
        OutlinedButton.icon(
          onPressed: app.currentBranchId == null ? null : _payBill,
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: const Text('Supplier Payment'),
        ),
      if (app.can('purchase.create'))
        OutlinedButton.icon(
          onPressed: _createSupplier,
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('New Supplier'),
        ),
    ];
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Purchase'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Outstanding'),
              Tab(text: 'Suppliers'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: ModuleWorkspaceHeader(
                  title: 'Procurement Desk',
                  subtitle: 'Supplier bills, liabilities, payments and master data.',
                  icon: Icons.local_shipping_outlined,
                  contextLabel: 'Business date · ${app.businessDate}',
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: BranchSelector(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ModuleActionPanel(
                  title: 'Procurement Actions',
                  subtitle: 'Post a supplier bill, settle liability or maintain supplier master.',
                  actions: actions,
                ),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ModuleMessageBanner(message: message!),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(12, 12, 12, 7),
                          child: ModuleSectionHeader(
                            title: 'Outstanding Supplier Bills',
                            subtitle: 'Open supplier liabilities for the selected branch.',
                          ),
                        ),
                        Expanded(
                          child: app.currentBranchId == null
                              ? const Center(
                                  child: Text('Select an authorised branch.'),
                                )
                              : AsyncPanel(
                                  key: ValueKey(
                                    'bills-${app.currentBranchId}-$refresh',
                                  ),
                                  future: api.get(
                                    ApiPaths.openBills,
                                    query: {
                                      'branch_id': app.currentBranchId,
                                    },
                                  ),
                                  emptyMessage: 'No supplier bills are outstanding.',
                                  builder: (context, data) => RecordsList(
                                    recordType: 'purchase',
                                    rows: (data as List)
                                        .map(
                                          (e) => Map<String, dynamic>.from(
                                            e as Map,
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(12, 12, 12, 7),
                          child: ModuleSectionHeader(
                            title: 'Supplier Master',
                            subtitle: 'Registered suppliers available for procurement.',
                          ),
                        ),
                        Expanded(
                          child: AsyncPanel(
                            key: ValueKey('suppliers-$refresh'),
                            future: api.get(ApiPaths.suppliers),
                            emptyMessage: 'No suppliers are registered.',
                            builder: (context, data) => RecordsList(
                              recordType: 'supplier',
                              rows: (data as List)
                                  .map(
                                    (e) => Map<String, dynamic>.from(e as Map),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

'''
replace_region(purchase, '  @override\n  Widget build(BuildContext context) {', '  Future<void> _createSupplier()', purchase_build)

# INVENTORY - keep permission/tab construction, replace only the rendered workspace.
inventory = ROOT / 'lib/screens/inventory/inventory_screen.dart'
add_import(inventory, "import '../../widgets/records_list.dart';\n", "import '../../widgets/module_workspace.dart';\n")
text = read(inventory)
start = text.find('    return DefaultTabController(', text.find('  Widget build(BuildContext context)'))
end = text.find('\n  List<Map<String, dynamic>> _rows', start)
if start < 0 or end < 0:
    raise SystemExit('Inventory render region missing')
inventory_tail = r'''    final actions = <Widget>[
      if (app.can('inventory.transfer.create'))
        FilledButton.icon(
          onPressed: app.currentBranchId == null ? null : _createTransfer,
          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
          label: const Text('New Transfer'),
        ),
      if (app.can('inventory.adjustment.create'))
        OutlinedButton.icon(
          onPressed: app.currentBranchId == null ? null : _createAdjustment,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Adjustment'),
        ),
    ];
    return DefaultTabController(
      length: tabs.length,
      initialIndex: initialIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inventory'),
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
                  title: 'Inventory Control',
                  subtitle: 'Branch stock, transfers, adjustments and quarantine control.',
                  icon: Icons.inventory_2_outlined,
                  contextLabel: 'Business date · ${app.businessDate}',
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: BranchSelector(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ModuleActionPanel(
                  title: 'Stock Actions',
                  subtitle: 'Move authorised stock or record a controlled adjustment.',
                  actions: actions,
                ),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ModuleMessageBanner(message: message!),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 7),
                child: ModuleSectionHeader(
                  title: 'Inventory Workspace',
                  subtitle: 'Use the tabs to review stock and controlled inventory movements.',
                ),
              ),
              Expanded(
                child: app.currentBranchId == null
                    ? const Center(child: Text('Select an authorised branch.'))
                    : TabBarView(children: [for (final tab in tabs) tab.$2]),
              ),
            ],
          ),
        ),
      ),
    );
  }
'''
write(inventory, text[:start] + inventory_tail + text[end:])

# FINANCE - preserve dynamic permissions and section implementations; professionalise workspace shell.
finance = ROOT / 'lib/screens/finance/finance_screen.dart'
add_import(finance, "import '../../widgets/records_list.dart';\n", "import '../../widgets/module_workspace.dart';\n")
text = read(finance)
start = text.find('    return DefaultTabController(', text.find('  Widget build(BuildContext context)'))
end = text.find('\n  Widget _books', start)
if start < 0 or end < 0:
    raise SystemExit('Finance render region missing')
finance_tail = r'''    return DefaultTabController(
      length: tabs.length,
      initialIndex: initialIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Finance'),
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
                  title: 'Finance Control Centre',
                  subtitle: 'Books, expenses, branch closing, bank reconciliation and periods.',
                  icon: Icons.account_balance_outlined,
                  contextLabel: 'Business date · ${app.businessDate}',
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
                  title: 'Accounting Workspace',
                  subtitle: 'Select the finance function required for the current business date.',
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
'''
write(finance, text[:start] + finance_tail + text[end:])

# REPORTS - responsive desktop navigation rail, mobile segmented selector.
reports = ROOT / 'lib/screens/reports/reports_screen.dart'
add_import(reports, "import '../../widgets/records_list.dart';\n", "import '../../widgets/module_workspace.dart';\n")
reports_region = r'''  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final config = _config(type);
    final needsBranch = type != 'trial';

    final query = <String, dynamic>{
      if (app.currentBranchId != null) 'branch_id': app.currentBranchId,
      if (type != 'stock' && type != 'trial') 'from': app.businessMonthStart,
      if (type != 'stock') 'to': app.businessDate,
    };
    final scopeLabel = type == 'stock'
        ? 'Live stock'
        : type == 'trial'
            ? BusinessFormat.date(app.businessDate)
            : '${BusinessFormat.date(app.businessMonthStart)} – ${BusinessFormat.date(app.businessDate)}';
    final reportView = needsBranch && app.currentBranchId == null
        ? const _BranchRequired()
        : AsyncPanel(
            key: ValueKey(
              '$type-${app.currentBranchId}-${app.businessDate}',
            ),
            future: api.get(config.path, query: query),
            emptyMessage: config.emptyMessage,
            builder: (context, data) => RecordsList(
              recordType: config.recordType,
              rows: ((data as List?) ?? const [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
            ),
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: ModuleWorkspaceHeader(
                title: 'Reports Centre',
                subtitle: 'Operational, inventory and financial reporting workspace.',
                icon: Icons.analytics_outlined,
                contextLabel: scopeLabel,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: BranchSelector(),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final content = Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 7),
                        child: ModuleSectionHeader(
                          title: config.title,
                          subtitle: config.subtitle,
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              scopeLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: reportView),
                    ],
                  );
                  if (constraints.maxWidth >= 900) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            child: SizedBox(
                              width: 220,
                              child: _reportRail(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: content),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      const SizedBox(height: 8),
                      _mobileReportSelector(),
                      Expanded(child: content),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileReportSelector() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'sales',
              icon: Icon(Icons.point_of_sale_outlined),
              label: Text('Sales'),
            ),
            ButtonSegment(
              value: 'purchase',
              icon: Icon(Icons.local_shipping_outlined),
              label: Text('Purchase'),
            ),
            ButtonSegment(
              value: 'stock',
              icon: Icon(Icons.inventory_2_outlined),
              label: Text('Stock'),
            ),
            ButtonSegment(
              value: 'finance',
              icon: Icon(Icons.account_balance_outlined),
              label: Text('Finance'),
            ),
            ButtonSegment(
              value: 'trial',
              icon: Icon(Icons.balance_outlined),
              label: Text('Trial'),
            ),
          ],
          selected: {type},
          onSelectionChanged: (value) => setState(() => type = value.first),
        ),
      );

  Widget _reportRail() {
    const values = ['sales', 'purchase', 'stock', 'finance', 'trial'];
    return NavigationRail(
      selectedIndex: values.indexOf(type),
      extended: true,
      minExtendedWidth: 220,
      backgroundColor: Colors.transparent,
      onDestinationSelected: (index) => setState(() => type = values[index]),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.point_of_sale_outlined),
          label: Text('Sales'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.local_shipping_outlined),
          label: Text('Purchase'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.inventory_2_outlined),
          label: Text('Stock'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.account_balance_outlined),
          label: Text('Finance'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.balance_outlined),
          label: Text('Trial Balance'),
        ),
      ],
    );
  }

'''
replace_region(reports, '  @override\n  Widget build(BuildContext context) {', '  _ReportConfig _config(String value)', reports_region)
text = read(reports)
text = text.replace("        'purchase' => const _ReportConfig(\n            path: ApiPaths.reportsPurchase,", "        'purchase' => const _ReportConfig(\n            title: 'Purchase Summary',\n            path: ApiPaths.reportsPurchase,", 1)
text = text.replace("        'stock' => const _ReportConfig(\n            path: ApiPaths.reportsStock,", "        'stock' => const _ReportConfig(\n            title: 'Stock Position',\n            path: ApiPaths.reportsStock,", 1)
text = text.replace("        'finance' => const _ReportConfig(\n            path: ApiPaths.reportsFinance,", "        'finance' => const _ReportConfig(\n            title: 'Finance Movement',\n            path: ApiPaths.reportsFinance,", 1)
text = text.replace("        'trial' => const _ReportConfig(\n            path: ApiPaths.trialBalance,", "        'trial' => const _ReportConfig(\n            title: 'Trial Balance',\n            path: ApiPaths.trialBalance,", 1)
text = text.replace("        _ => const _ReportConfig(\n            path: ApiPaths.reportsSales,", "        _ => const _ReportConfig(\n            title: 'Sales Summary',\n            path: ApiPaths.reportsSales,", 1)
text = text.replace("  const _ReportConfig({\n    required this.path,", "  const _ReportConfig({\n    required this.title,\n    required this.path,", 1)
text = text.replace("  final String path;", "  final String title;\n  final String path;", 1)
write(reports, text)

# UI widget regression test for the shared mobile workspace primitives.
test = r'''import 'package:excel_herbal_erp/widgets/module_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('module workspace remains usable at 320px width', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const ModuleWorkspaceHeader(
                  title: 'Inventory Control',
                  subtitle: 'Branch stock, transfers, adjustments and quarantine control.',
                  icon: Icons.inventory_2_outlined,
                  contextLabel: 'Business date · 2026-09-09',
                ),
                ModuleActionPanel(
                  title: 'Stock Actions',
                  subtitle: 'Move stock or record a controlled adjustment.',
                  actions: [
                    FilledButton(onPressed: () {}, child: const Text('Transfer')),
                    OutlinedButton(onPressed: () {}, child: const Text('Adjustment')),
                    OutlinedButton(onPressed: () {}, child: const Text('Quarantine')),
                  ],
                ),
                const ModuleSectionHeader(
                  title: 'Inventory Workspace',
                  subtitle: 'Review stock and controlled inventory movements.',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Inventory Control'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
  });
}
'''
write(ROOT / 'test/module_workspace_test.dart', test)

print('Module professionalisation patch applied.')
