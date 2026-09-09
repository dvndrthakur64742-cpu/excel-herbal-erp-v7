from pathlib import Path

ROOT = Path('flutter-app/lib')


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    path.write_text(text.replace(old, new, 1))


# My Work: deep-linkable section/action entry points.
p = ROOT / 'screens/my_work/my_work_screen.dart'
replace_once(
    p,
    """class MyWorkScreen extends ConsumerStatefulWidget {\n  const MyWorkScreen({super.key});\n\n  @override\n  ConsumerState<MyWorkScreen> createState() => _MyWorkScreenState();\n}\n\nclass _MyWorkScreenState extends ConsumerState<MyWorkScreen> {\n  int refresh = 0;\n  String? message;\n\n  @override\n  Widget build(BuildContext context) {""",
    """class MyWorkScreen extends ConsumerStatefulWidget {\n  const MyWorkScreen({\n    super.key,\n    this.initialSection = 'attendance',\n    this.initialAction,\n  });\n\n  final String initialSection;\n  final String? initialAction;\n\n  @override\n  ConsumerState<MyWorkScreen> createState() => _MyWorkScreenState();\n}\n\nclass _MyWorkScreenState extends ConsumerState<MyWorkScreen> {\n  int refresh = 0;\n  String? message;\n  bool _handledInitialAction = false;\n\n  @override\n  void initState() {\n    super.initState();\n    WidgetsBinding.instance.addPostFrameCallback((_) async {\n      await _runInitialAction();\n    });\n  }\n\n  Future<void> _runInitialAction() async {\n    if (_handledInitialAction || !mounted || widget.initialAction == null) return;\n    _handledInitialAction = true;\n    try {\n      switch (widget.initialAction) {\n        case 'new_order':\n          await _newDailyOrder();\n          break;\n        case 'leave':\n          await _applyLeave();\n          break;\n        case 'field_visit':\n          await _startVisit();\n          break;\n        case 'evening':\n          final app = ref.read(appStateProvider);\n          final api = ref.read(apiClientProvider);\n          final rows = await _dailyRows(app, api);\n          final candidates = rows\n              .where((row) =>\n                  '${row['business_date'] ?? ''}' == app.businessDate &&\n                  const {'issued', 'evening_draft'}.contains('${row['status']}'))\n              .toList()\n            ..sort((a, b) =>\n                (int.tryParse('${b['id']}') ?? 0)\n                    .compareTo(int.tryParse('${a['id']}') ?? 0));\n          if (candidates.isEmpty) {\n            if (mounted) {\n              setState(() => message =\n                  'Aaj Evening Closing ke liye koi issued order available nahi hai.');\n            }\n            return;\n          }\n          final row = candidates.first;\n          await _dailyAction(\n            int.parse('${row['id']}'),\n            '${row['status']}' == 'evening_draft' ? 'evening_edit' : 'evening',\n          );\n          break;\n      }\n    } catch (e) {\n      if (mounted) setState(() => message = UiError.message(e));\n    }\n  }\n\n  @override\n  Widget build(BuildContext context) {""",
    'my work constructor/deep-link',
)
replace_once(
    p,
    """    return DefaultTabController(\n      length: tabs.length,""",
    """    final preferredLabel = switch (widget.initialSection) {\n      'daily' => 'Daily Order',\n      'leave_visit' => 'Leave & Visit',\n      _ => 'Attendance & Duty',\n    };\n    final requestedIndex = tabs.indexWhere((tab) => tab.$1 == preferredLabel);\n    final initialIndex = requestedIndex < 0 ? 0 : requestedIndex;\n    return DefaultTabController(\n      length: tabs.length,\n      initialIndex: initialIndex,""",
    'my work initial tab',
)

# Sales: direct action entry.
p = ROOT / 'screens/sales/sales_screen.dart'
replace_once(
    p,
    """class SalesScreen extends ConsumerStatefulWidget {\n  const SalesScreen({super.key});\n  @override\n  ConsumerState<SalesScreen> createState() => _SalesScreenState();\n}\n\nclass _SalesScreenState extends ConsumerState<SalesScreen> {\n  int refresh = 0;\n  String? message;\n\n  @override\n  Widget build(BuildContext context) {""",
    """class SalesScreen extends ConsumerStatefulWidget {\n  const SalesScreen({super.key, this.initialAction});\n\n  final String? initialAction;\n\n  @override\n  ConsumerState<SalesScreen> createState() => _SalesScreenState();\n}\n\nclass _SalesScreenState extends ConsumerState<SalesScreen> {\n  int refresh = 0;\n  String? message;\n  bool _handledInitialAction = false;\n\n  @override\n  void initState() {\n    super.initState();\n    WidgetsBinding.instance.addPostFrameCallback((_) async {\n      if (_handledInitialAction || widget.initialAction == null || !mounted) return;\n      _handledInitialAction = true;\n      switch (widget.initialAction) {\n        case 'counter_sale':\n          await _counterSale();\n          break;\n        case 'new_customer':\n          await _createCustomer();\n          break;\n        case 'receipt':\n          await _receipt();\n          break;\n      }\n    });\n  }\n\n  @override\n  Widget build(BuildContext context) {""",
    'sales deep-link',
)

# Inventory: section + exact action entry.
p = ROOT / 'screens/inventory/inventory_screen.dart'
replace_once(
    p,
    """class InventoryScreen extends ConsumerStatefulWidget {\n  const InventoryScreen({super.key});\n  @override\n  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();\n}\n\nclass _InventoryScreenState extends ConsumerState<InventoryScreen> {\n  int refresh = 0;\n  String? message;\n\n  @override\n  Widget build(BuildContext context) {""",
    """class InventoryScreen extends ConsumerStatefulWidget {\n  const InventoryScreen({\n    super.key,\n    this.initialSection = 'stock',\n    this.initialAction,\n  });\n\n  final String initialSection;\n  final String? initialAction;\n\n  @override\n  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();\n}\n\nclass _InventoryScreenState extends ConsumerState<InventoryScreen> {\n  int refresh = 0;\n  String? message;\n  bool _handledInitialAction = false;\n\n  @override\n  void initState() {\n    super.initState();\n    WidgetsBinding.instance.addPostFrameCallback((_) async {\n      if (_handledInitialAction || widget.initialAction == null || !mounted) return;\n      _handledInitialAction = true;\n      switch (widget.initialAction) {\n        case 'new_transfer':\n          await _createTransfer();\n          break;\n        case 'adjustment':\n          await _createAdjustment();\n          break;\n      }\n    });\n  }\n\n  @override\n  Widget build(BuildContext context) {""",
    'inventory deep-link',
)
replace_once(
    p,
    """    return DefaultTabController(\n      length: tabs.length,""",
    """    final preferredLabel = switch (widget.initialSection) {\n      'transfers' => 'Transfers',\n      'adjustments' => 'Adjustments',\n      'quarantine' => 'Quarantine',\n      _ => 'Stock',\n    };\n    final requestedIndex = tabs.indexWhere((tab) => tab.$1 == preferredLabel);\n    final initialIndex = requestedIndex < 0 ? 0 : requestedIndex;\n    return DefaultTabController(\n      length: tabs.length,\n      initialIndex: initialIndex,""",
    'inventory initial tab',
)

# Purchase: direct action entry.
p = ROOT / 'screens/purchase/purchase_screen.dart'
replace_once(
    p,
    """class PurchaseScreen extends ConsumerStatefulWidget {\n  const PurchaseScreen({super.key});\n  @override\n  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();\n}\n\nclass _PurchaseScreenState extends ConsumerState<PurchaseScreen> {\n  int refresh = 0;\n  String? message;\n  @override\n  Widget build(BuildContext context) {""",
    """class PurchaseScreen extends ConsumerStatefulWidget {\n  const PurchaseScreen({super.key, this.initialAction});\n\n  final String? initialAction;\n\n  @override\n  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();\n}\n\nclass _PurchaseScreenState extends ConsumerState<PurchaseScreen> {\n  int refresh = 0;\n  String? message;\n  bool _handledInitialAction = false;\n\n  @override\n  void initState() {\n    super.initState();\n    WidgetsBinding.instance.addPostFrameCallback((_) async {\n      if (_handledInitialAction || widget.initialAction == null || !mounted) return;\n      _handledInitialAction = true;\n      switch (widget.initialAction) {\n        case 'new_bill':\n          await _newBill();\n          break;\n        case 'supplier_payment':\n          await _payBill();\n          break;\n        case 'new_supplier':\n          await _createSupplier();\n          break;\n      }\n    });\n  }\n\n  @override\n  Widget build(BuildContext context) {""",
    'purchase deep-link',
)

# Finance: section + direct expense entry.
p = ROOT / 'screens/finance/finance_screen.dart'
replace_once(
    p,
    """class FinanceScreen extends ConsumerStatefulWidget {\n  const FinanceScreen({super.key});\n  @override\n  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();\n}\n\nclass _FinanceScreenState extends ConsumerState<FinanceScreen> {\n  int refresh = 0;\n  String? message;\n\n  @override\n  Widget build(BuildContext context) {""",
    """class FinanceScreen extends ConsumerStatefulWidget {\n  const FinanceScreen({\n    super.key,\n    this.initialSection = 'books',\n    this.initialAction,\n  });\n\n  final String initialSection;\n  final String? initialAction;\n\n  @override\n  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();\n}\n\nclass _FinanceScreenState extends ConsumerState<FinanceScreen> {\n  int refresh = 0;\n  String? message;\n  bool _handledInitialAction = false;\n\n  @override\n  void initState() {\n    super.initState();\n    WidgetsBinding.instance.addPostFrameCallback((_) async {\n      if (_handledInitialAction || widget.initialAction == null || !mounted) return;\n      _handledInitialAction = true;\n      if (widget.initialAction == 'expense') await _expense();\n    });\n  }\n\n  @override\n  Widget build(BuildContext context) {""",
    'finance deep-link',
)
replace_once(
    p,
    """    return DefaultTabController(\n      length: tabs.length,""",
    """    final preferredLabel = switch (widget.initialSection) {\n      'expenses' => 'Expenses',\n      'closing' => 'Closing',\n      'bank' => 'Bank',\n      'periods' => 'Periods',\n      _ => 'Books',\n    };\n    final requestedIndex = tabs.indexWhere((tab) => tab.$1 == preferredLabel);\n    final initialIndex = requestedIndex < 0 ? 0 : requestedIndex;\n    return DefaultTabController(\n      length: tabs.length,\n      initialIndex: initialIndex,""",
    'finance initial tab',
)

# Home: use shell navigation when supplied instead of nesting another Scaffold.
p = ROOT / 'screens/home/home_screen.dart'
replace_once(
    p,
    """class HomeScreen extends ConsumerWidget {\n  const HomeScreen({super.key});""",
    """class HomeScreen extends ConsumerWidget {\n  const HomeScreen({super.key, this.openMyWork});\n\n  final VoidCallback? openMyWork;""",
    'home callback constructor',
)
replace_once(
    p,
    """                    FilledButton.tonalIcon(\n                      onPressed: () => Navigator.of(context).push(\n                        MaterialPageRoute(\n                          builder: (_) => const Scaffold(\n                            body: SafeArea(child: MyWorkScreen()),\n                          ),\n                        ),\n                      ),\n                      icon: const Icon(Icons.arrow_forward, size: 18),\n                      label: const Text('Open My Work'),\n                    ),""",
    """                    FilledButton.tonalIcon(\n                      onPressed: openMyWork ??\n                          () => Navigator.of(context).push(\n                                MaterialPageRoute(\n                                  builder: (_) => const Scaffold(\n                                    body: SafeArea(child: MyWorkScreen()),\n                                  ),\n                                ),\n                              ),\n                      icon: const Icon(Icons.arrow_forward, size: 18),\n                      label: const Text('Open My Work'),\n                    ),""",
    'home shell connection',
)

# App shell: remove duplicate workspace drawer destinations and turn + into a true action launcher.
p = ROOT / 'shell/app_shell.dart'
replace_once(
    p,
    """                  _drawerSectionLabel('WORKSPACE'),\n                  _drawerTile(\n                    app: app,\n                    id: 'home',\n                    label: 'Home',\n                    icon: Icons.home_outlined,\n                  ),\n                  if (app.sectionVisible('my_work'))\n                    _drawerTile(\n                      app: app,\n                      id: 'my_work',\n                      label: 'My Work',\n                      icon: Icons.work_outline_rounded,\n                    ),\n                  if (_quickActionsVisible(app))\n                    _drawerTile(\n                      app: app,\n                      id: 'actions',\n                      label: 'Quick Actions',\n                      icon: Icons.bolt_outlined,\n                    ),\n                  if (app.can('communication.view'))\n                    _drawerTile(\n                      app: app,\n                      id: 'tasks',\n                      label: 'Tasks',\n                      icon: Icons.task_alt_outlined,\n                    ),\n""",
    """,
    'remove duplicate mobile workspace drawer',
)
replace_once(
    p,
    """      'home' => const HomeScreen(),""",
    """      'home' => HomeScreen(\n        openMyWork: () => setState(() => desktopRoute = 'my_work'),\n      ),""",
    'desktop home connection',
)
replace_once(
    p,
    """    'home' => const HomeScreen(),\n    'my_work' => const MyWorkScreen(),""",
    """    'home' => HomeScreen(\n      openMyWork: () => _selectMobileRoute(app, 'my_work'),\n    ),\n    'my_work' => const MyWorkScreen(),""",
    'mobile home connection',
)
replace_once(
    p,
    """        onDestinationSelected: (v) => setState(() => mobileIndex = v),""",
    """        onDestinationSelected: (v) {\n          final id = '${items[v]['id']}';\n          if (id == 'actions') {\n            _showQuickActions(app);\n            return;\n          }\n          setState(() => mobileIndex = v);\n        },""",
    'bottom nav action launcher',
)
replace_once(
    p,
    """  Widget _bottomNav(\n""",
    """  Future<void> _showQuickActions(AppState app) async {\n    final actions = <({String id, String label, IconData icon})>[];\n    if (app.can('workforce.attendance.self')) {\n      actions.add((id: 'attendance', label: 'Check-In / Out', icon: Icons.location_on_outlined));\n    }\n    if (app.canAny(const ['daily_order.self', 'daily_order.others'])) {\n      actions.add((id: 'daily_create', label: 'Create Daily Order', icon: Icons.shopping_cart_checkout));\n      actions.add((id: 'evening', label: 'Evening Closing', icon: Icons.nightlight_outlined));\n    }\n    if (app.can('workforce.field_visit.self')) {\n      actions.add((id: 'field_visit', label: 'Field Visit', icon: Icons.route_outlined));\n    }\n    if (app.can('workforce.leave.self')) {\n      actions.add((id: 'leave', label: 'Apply Leave', icon: Icons.event_available_outlined));\n    }\n    if (app.can('sales.create')) {\n      actions.add((id: 'counter_sale', label: 'Counter Sale', icon: Icons.point_of_sale));\n    }\n    if (app.can('inventory.transfer.create')) {\n      actions.add((id: 'stock_transfer', label: 'Stock Transfer', icon: Icons.swap_horiz));\n    }\n    if (app.can('purchase.create')) {\n      actions.add((id: 'purchase_entry', label: 'Purchase Entry', icon: Icons.local_shipping_outlined));\n    }\n    if (app.can('finance.expense.create')) {\n      actions.add((id: 'expense_entry', label: 'Expense Entry', icon: Icons.receipt_long_outlined));\n    }\n    if (actions.isEmpty || !mounted) return;\n    final selected = await showModalBottomSheet<String>(\n      context: context,\n      useSafeArea: true,\n      showDragHandle: true,\n      builder: (sheetContext) => ListView(\n        shrinkWrap: true,\n        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),\n        children: [\n          Padding(\n            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),\n            child: Text(\n              'Quick Actions',\n              style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(\n                    fontWeight: FontWeight.w800,\n                  ),\n            ),\n          ),\n          for (final action in actions)\n            ListTile(\n              leading: Icon(action.icon),\n              title: Text(action.label),\n              trailing: const Icon(Icons.arrow_forward_rounded, size: 18),\n              onTap: () => Navigator.pop(sheetContext, action.id),\n            ),\n        ],\n      ),\n    );\n    if (selected == null || !mounted) return;\n    _openConnectedAction(selected);\n  }\n\n  void _openConnectedAction(String id) {\n    Widget? screen;\n    switch (id) {\n      case 'attendance':\n        screen = const MyWorkScreen(initialSection: 'attendance');\n        break;\n      case 'daily_create':\n        screen = const MyWorkScreen(initialSection: 'daily', initialAction: 'new_order');\n        break;\n      case 'evening':\n        screen = const MyWorkScreen(initialSection: 'daily', initialAction: 'evening');\n        break;\n      case 'field_visit':\n        screen = const MyWorkScreen(initialSection: 'leave_visit', initialAction: 'field_visit');\n        break;\n      case 'leave':\n        screen = const MyWorkScreen(initialSection: 'leave_visit', initialAction: 'leave');\n        break;\n      case 'counter_sale':\n        screen = const SalesScreen(initialAction: 'counter_sale');\n        break;\n      case 'stock_transfer':\n        screen = const InventoryScreen(initialSection: 'transfers', initialAction: 'new_transfer');\n        break;\n      case 'purchase_entry':\n        screen = const PurchaseScreen(initialAction: 'new_bill');\n        break;\n      case 'expense_entry':\n        screen = const FinanceScreen(initialSection: 'expenses', initialAction: 'expense');\n        break;\n    }\n    if (screen != null) {\n      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen!));\n    }\n  }\n\n  Widget _bottomNav(\n""",
    'quick actions sheet/deep links',
)

print('IA connection reset patched 7 Flutter files')
