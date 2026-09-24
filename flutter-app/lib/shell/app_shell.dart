import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/administration/administration_screen.dart';
import '../screens/communication/communication_screen.dart';
import '../screens/communication/tasks_screen.dart';
import '../screens/finance/finance_screen.dart';
import '../screens/home/actions_screen.dart';
import '../screens/home/enterprise_hub_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/profile_screen.dart';
import '../screens/inventory/inventory_screen.dart';
import '../screens/my_work/my_work_workspace_screen.dart';
import '../screens/organization/organization_screen.dart';
import '../screens/organization/team_screen.dart';
import '../screens/performance/performance_screen.dart';
import '../screens/purchase/purchase_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/sales/sales_screen.dart';
import '../screens/tools/erp_tools_screen.dart';
import '../core/overlay_transition.dart';
import '../state/app_state.dart';
import '../theme/excel_brand.dart';
import 'shell_layout.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int mobileIndex = 0;
  String desktopRoute = 'home';

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = ShellLayout.isDesktopWidth(constraints.maxWidth);
        if (desktop) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  SizedBox(width: 274, child: _desktopSidebar(context, app)),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: ColoredBox(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerLowest,
                      child: _desktopContent(app),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final items = app.bottomNav.isNotEmpty
            ? app.bottomNav
            : const [
                {'id': 'home', 'label': 'Home'},
                {'id': 'profile', 'label': 'Profile'},
              ];
        final safeIndex = mobileIndex.clamp(0, items.length - 1);
        final route = '${items[safeIndex]['id']}';
        return Scaffold(
          drawerEdgeDragWidth: 28,
          appBar: AppBar(
            title: Text('${items[safeIndex]['label']}'),
            actions: [
              if (app.sectionVisible('communication'))
                IconButton(
                  tooltip: 'Announcements & notifications',
                  onPressed: () => _openModule('communication'),
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
              const SizedBox(width: 4),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          drawer: _mobileDrawer(app),
          body: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(.025, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(route),
                child: _mobilePage(app, route),
              ),
            ),
          ),
          bottomNavigationBar: _bottomNav(app, items, safeIndex),
        );
      },
    );
  }

  Widget _desktopSidebar(BuildContext context, AppState app) {
    final employee = Map<String, dynamic>.from(
      (app.me['employee'] as Map?) ?? const {},
    );
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 116,
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Image.asset(
                    'assets/branding/excel-herbal-logo.webp',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ERP Workspace',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Secure business access',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              children: [
                _sectionLabel(context, 'WORKSPACE'),
                _desktopTile('home', 'Home', Icons.home_outlined),
                if (app.sectionVisible('my_work'))
                  _desktopTile('my_work', 'My Work', Icons.work_outline),
                if (_quickActionsVisible(app))
                  _desktopTile(
                    'quick_actions',
                    'Quick Actions',
                    Icons.bolt_outlined,
                  ),
                if (_approvalVisible(app))
                  _desktopTile(
                    'approvals',
                    'Approvals',
                    Icons.approval_outlined,
                  ),
                if (!app.businessAccessBlocked)
                  _desktopTile(
                    'global_search',
                    'Global Search',
                    Icons.manage_search_outlined,
                  ),
                if (app.can('communication.view'))
                  _desktopTile('tasks', 'Tasks', Icons.task_alt_outlined),
                if (app.erpToolsVisible)
                  _desktopTile(
                    'erp_tools',
                    'My Account & Duty',
                    Icons.badge_outlined,
                  ),
                const SizedBox(height: 12),
                _sectionLabel(context, 'MODULES'),
                ...app.sections
                    .where(
                      (s) => !const {'home', 'my_work'}.contains('${s['id']}'),
                    )
                    .map(
                      (s) => _desktopTile(
                        '${s['id']}',
                        '${s['label']}',
                        _icon('${s['id']}'),
                      ),
                    ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  child: Text(_initials('${employee['full_name'] ?? 'U'}')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${employee['full_name'] ?? 'Employee'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(
                        '${employee['employee_code'] ?? ''} · ${employee['designation_code'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Logout',
                  onPressed: () => ref.read(appStateProvider.notifier).logout(),
                  icon: const Icon(Icons.logout, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: .9,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );

  Widget _desktopTile(String id, String label, IconData icon) {
    final selected = desktopRoute == id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        selected: selected,
        selectedTileColor: ExcelBrand.primarySoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        dense: true,
        leading: Icon(icon, size: 21),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => _selectDesktopRoute(id),
      ),
    );
  }

  Widget _desktopContent(AppState app) {
    final effectiveRoute = _routeAllowed(app, desktopRoute)
        ? desktopRoute
        : 'home';
    final child = switch (effectiveRoute) {
      'home' => HomeScreen(
          openMyWork: () => _selectDesktopRoute('my_work'),
        ),
      'my_work' => const MyWorkWorkspaceScreen(),
      'quick_actions' => ActionsScreen(
          openConnectedAction: _openConnectedAction,
        ),
      'tasks' => const TasksScreen(),
      'erp_tools' => const ErpToolsScreen(),
      'approvals' => const EnterpriseHubScreen(
          key: ValueKey('desktop-enterprise-approvals'),
          initialTab: 0,
        ),
      'global_search' => const EnterpriseHubScreen(
          key: ValueKey('desktop-enterprise-global-search'),
          initialTab: 1,
        ),
      'profile' => const ProfileScreen(),
      'team' => const TeamScreen(),
      'sales' => const SalesScreen(),
      'inventory' => const InventoryScreen(),
      'purchase' => const PurchaseScreen(),
      'finance' => const FinanceScreen(),
      'payroll_performance' => const PerformanceScreen(),
      'reports' => const ReportsScreen(),
      'organization' => const OrganizationScreen(),
      'communication' => const CommunicationScreen(),
      'administration' => const AdministrationScreen(),
      _ => const HomeScreen(),
    };

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _desktopWorkspaceHeader(app, effectiveRoute),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopWorkspaceHeader(AppState app, String route) {
    final theme = Theme.of(context);
    final businessDate = app.businessDate.trim();
    final branch = app.currentBranchName.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: ExcelBrand.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              _icon(route),
              size: 22,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _desktopRouteLabel(route),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Current authorised workspace',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _WorkspaceContextChip(
            icon: Icons.store_outlined,
            label: branch.isEmpty ? 'Branch unavailable' : branch,
          ),
          const SizedBox(width: 8),
          _WorkspaceContextChip(
            icon: Icons.event_outlined,
            label: businessDate.isEmpty
                ? 'Business date unavailable'
                : 'Business date $businessDate',
          ),
        ],
      ),
    );
  }

  String _desktopRouteLabel(String route) => switch (route) {
        'home' => 'Home',
        'my_work' => 'My Work',
        'quick_actions' => 'Quick Actions',
        'tasks' => 'Tasks',
        'erp_tools' => 'My Account & Duty',
        'approvals' => 'Approvals',
        'global_search' => 'Global Search',
        'profile' => 'Profile',
        'team' => 'Team Operations',
        'sales' => 'Sales & Collections',
        'inventory' => 'Inventory',
        'purchase' => 'Purchase & Suppliers',
        'finance' => 'Finance & Accounts',
        'payroll_performance' => 'Payroll & Performance',
        'reports' => 'Reports',
        'organization' => 'Organization',
        'communication' => 'Communication',
        'administration' => 'Administration',
        _ => 'ERP Workspace',
      };

  Drawer _mobileDrawer(AppState app) {
    final employee = Map<String, dynamic>.from(
      (app.me['employee'] as Map?) ?? const {},
    );
    final width = (MediaQuery.sizeOf(context).width * .9).clamp(300.0, 390.0);
    final branch = _currentBranchLabel(app);
    final designation =
        '${employee['designation_name'] ?? employee['designation_code'] ?? ''}'
            .trim();
    final moduleSections = app.sections
        .where((s) => !const {'home', 'my_work'}.contains('${s['id']}'))
        .toList();

    return Drawer(
      width: width,
      backgroundColor: ExcelBrand.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(26)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 13),
              decoration: const BoxDecoration(
                color: ExcelBrand.primaryDark,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 116,
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Image.asset(
                          'assets/branding/excel-herbal-logo.webp',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Close menu',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .28),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _initials('${employee['full_name'] ?? 'U'}'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${employee['full_name'] ?? 'Employee'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                designation,
                                branch,
                              ].where((e) => e.trim().isNotEmpty).join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: .78),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
                children: [
                  if (moduleSections.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _drawerSectionLabel('BUSINESS MODULES'),
                    for (final section in moduleSections)
                      _drawerTile(
                        app: app,
                        id: '${section['id']}',
                        label: '${section['label']}',
                        icon: _icon('${section['id']}'),
                      ),
                  ],
                  if (app.erpToolsVisible ||
                      _approvalVisible(app) ||
                      !app.businessAccessBlocked) ...[
                    const SizedBox(height: 12),
                    _drawerSectionLabel('WORKSPACE TOOLS'),
                  ],
                  if (app.erpToolsVisible)
                    _drawerTile(
                      app: app,
                      id: 'erp_tools',
                      label: 'My Account & Duty',
                      icon: Icons.badge_outlined,
                    ),
                  if (_approvalVisible(app))
                    _drawerTile(
                      app: app,
                      id: 'approvals',
                      label: 'Approvals',
                      icon: Icons.approval_outlined,
                    ),
                  if (!app.businessAccessBlocked)
                    _drawerTile(
                      app: app,
                      id: 'global_search',
                      label: 'Global Search',
                      icon: Icons.manage_search_outlined,
                    ),
                ],
              ),
            ),
            Container(
              color: ExcelBrand.surface,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: ListTile(
                leading: const Icon(
                  Icons.logout_rounded,
                  color: ExcelBrand.danger,
                ),
                title: const Text(
                  'Logout',
                  style: TextStyle(
                    color: ExcelBrand.danger,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onTap: () async {
                  final closed = await OverlayTransition.closeAndSettle(
                    context,
                  );
                  if (!closed || !mounted) return;
                  ref.read(appStateProvider.notifier).logout();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerSectionLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: .85,
              ),
        ),
      );

  Widget _drawerTile({
    required AppState app,
    required String id,
    required String label,
    required IconData icon,
  }) {
    final items = app.bottomNav;
    final safeIndex =
        items.isEmpty ? -1 : mobileIndex.clamp(0, items.length - 1);
    final current = safeIndex >= 0 ? '${items[safeIndex]['id']}' : 'home';
    final selected = current == id;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        selected: selected,
        selectedTileColor: ExcelBrand.primarySoft,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: selected ? Colors.white : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 21,
            color: selected ? ExcelBrand.primaryDark : scheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 19),
        onTap: () async {
          final closed = await OverlayTransition.closeAndSettle(context);
          if (!closed || !mounted) return;
          _openModule(id);
        },
      ),
    );
  }

  String _currentBranchLabel(AppState app) {
    for (final branch in app.branches) {
      if (int.tryParse('${branch['id']}') == app.currentBranchId) {
        return '${branch['name'] ?? branch['code'] ?? ''}'.trim();
      }
    }
    return '';
  }

  Widget _mobilePage(AppState app, String id) => switch (id) {
        'home' =>
          HomeScreen(openMyWork: () => _selectMobileRoute(app, 'my_work')),
        'my_work' => const MyWorkWorkspaceScreen(),
        'actions' => ActionsScreen(
            openConnectedAction: _openConnectedAction,
          ),
        'tasks' => const TasksScreen(),
        'erp_tools' => const ErpToolsScreen(),
        'approvals' => const EnterpriseHubScreen(initialTab: 0),
        'global_search' => const EnterpriseHubScreen(initialTab: 1),
        'profile' => const ProfileScreen(),
        _ => const HomeScreen(),
      };

  Future<void> _showQuickActions(AppState app) async {
    final actions = <({String id, String label, IconData icon})>[];
    if (app.can('workforce.attendance.self')) {
      actions.add((
        id: 'attendance',
        label: 'Check-In / Out',
        icon: Icons.location_on_outlined,
      ));
    }
    if (app.canAny(const ['daily_order.self', 'daily_order.others'])) {
      actions.add((
        id: 'daily_create',
        label: 'Create Daily Order',
        icon: Icons.shopping_cart_checkout,
      ));
      actions.add((
        id: 'evening',
        label: 'Evening Closing',
        icon: Icons.nightlight_outlined,
      ));
    }
    if (app.can('workforce.field_visit.self')) {
      actions.add((
        id: 'field_visit',
        label: 'Field Visit',
        icon: Icons.route_outlined,
      ));
    }
    if (app.can('workforce.leave.self')) {
      actions.add((
        id: 'leave',
        label: 'Apply Leave',
        icon: Icons.event_available_outlined,
      ));
    }
    if (app.can('sales.create')) {
      actions.add((
        id: 'counter_sale',
        label: 'Counter Sale',
        icon: Icons.point_of_sale,
      ));
    }
    if (app.can('inventory.transfer.create')) {
      actions.add((
        id: 'stock_transfer',
        label: 'Stock Transfer',
        icon: Icons.swap_horiz,
      ));
    }
    if (app.can('purchase.create')) {
      actions.add((
        id: 'purchase_entry',
        label: 'Purchase Entry',
        icon: Icons.local_shipping_outlined,
      ));
    }
    if (app.can('finance.expense.create')) {
      actions.add((
        id: 'expense_entry',
        label: 'Expense Entry',
        icon: Icons.receipt_long_outlined,
      ));
    }
    if (actions.isEmpty || !mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Text(
              'Quick Actions',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          for (final action in actions)
            ListTile(
              leading: Icon(action.icon),
              title: Text(action.label),
              trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
              onTap: () => Navigator.pop(sheetContext, action.id),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    _openConnectedAction(selected);
  }

  void _openConnectedAction(String id) {
    Widget? screen;
    switch (id) {
      case 'attendance':
        screen = const MyWorkWorkspaceScreen(initialSection: 'attendance');
        break;
      case 'daily_create':
        screen = const MyWorkWorkspaceScreen(
          initialSection: 'daily',
          initialAction: 'new_order',
        );
        break;
      case 'evening':
        screen = const MyWorkWorkspaceScreen(
          initialSection: 'daily',
          initialAction: 'evening',
        );
        break;
      case 'field_visit':
        screen = const MyWorkWorkspaceScreen(
          initialSection: 'leave_visit',
          initialAction: 'field_visit',
        );
        break;
      case 'leave':
        screen = const MyWorkWorkspaceScreen(
          initialSection: 'leave_visit',
          initialAction: 'leave',
        );
        break;
      case 'counter_sale':
        screen = const SalesScreen(initialAction: 'counter_sale');
        break;
      case 'stock_transfer':
        screen = const InventoryScreen(
          initialSection: 'transfers',
          initialAction: 'new_transfer',
        );
        break;
      case 'purchase_entry':
        screen = const PurchaseScreen(initialAction: 'new_bill');
        break;
      case 'expense_entry':
        screen = const FinanceScreen(
          initialSection: 'expenses',
          initialAction: 'expense',
        );
        break;
    }
    if (screen != null) {
      final routedScreen = screen is MyWorkWorkspaceScreen
          ? Scaffold(
              appBar: AppBar(title: const Text('My Work')),
              body: SafeArea(child: screen),
            )
          : screen;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => routedScreen),
      );
    }
  }

  Widget _bottomNav(
    AppState app,
    List<Map<String, dynamic>> items,
    int safeIndex,
  ) =>
      DecoratedBox(
        decoration: const BoxDecoration(
          color: ExcelBrand.surface,
          border: Border(top: BorderSide(color: ExcelBrand.border)),
          boxShadow: [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 18,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: safeIndex,
            onDestinationSelected: (v) {
              final id = '${items[v]['id']}';
              if (id == 'actions') {
                _showQuickActions(app);
                return;
              }
              _selectMobileRoute(app, id);
            },
            destinations: items
                .map(
                  (item) => NavigationDestination(
                    icon: Icon(_bottomIcon('${item['id']}', false)),
                    selectedIcon: Icon(_bottomIcon('${item['id']}', true)),
                    label: '${item['label']}',
                  ),
                )
                .toList(),
          ),
        ),
      );

  IconData _bottomIcon(String id, bool selected) => switch (id) {
        'home' => selected ? Icons.home : Icons.home_outlined,
        'my_work' => selected ? Icons.work : Icons.work_outline,
        'actions' => selected ? Icons.add_circle : Icons.add_circle_outline,
        'tasks' => selected ? Icons.task_alt : Icons.task_alt_outlined,
        'profile' => selected ? Icons.person : Icons.person_outline,
        'approvals' => selected ? Icons.approval : Icons.approval_outlined,
        'global_search' => Icons.manage_search_outlined,
        'erp_tools' => Icons.badge_outlined,
        _ => Icons.circle_outlined,
      };

  void _selectDesktopRoute(String id) {
    final app = ref.read(appStateProvider);
    final index = app.bottomNav.indexWhere((item) => '${item['id']}' == id);
    setState(() {
      desktopRoute = id;
      if (index >= 0) mobileIndex = index;
    });
  }

  void _selectMobileRoute(AppState app, String id) {
    final items = app.bottomNav;
    final index = items.indexWhere((item) => '${item['id']}' == id);
    if (index >= 0) {
      setState(() {
        mobileIndex = index;
        desktopRoute = id;
      });
    }
  }

  IconData _icon(String id) => switch (id) {
        'home' => Icons.home_outlined,
        'my_work' => Icons.work_outline,
        'team' => Icons.groups_outlined,
        'sales' => Icons.point_of_sale_outlined,
        'inventory' => Icons.inventory_2_outlined,
        'purchase' => Icons.local_shipping_outlined,
        'finance' => Icons.account_balance_outlined,
        'payroll_performance' => Icons.insights_outlined,
        'reports' => Icons.analytics_outlined,
        'organization' => Icons.apartment_outlined,
        'communication' => Icons.notifications_outlined,
        'administration' => Icons.admin_panel_settings_outlined,
        'approvals' => Icons.approval_outlined,
        'global_search' => Icons.manage_search_outlined,
        'erp_tools' => Icons.badge_outlined,
        _ => Icons.circle_outlined,
      };

  void _openModule(String id) {
    final app = ref.read(appStateProvider);
    if (!_routeAllowed(app, id)) return;
    if (ShellLayout.isDesktopWidth(MediaQuery.sizeOf(context).width)) {
      _selectDesktopRoute(id);
      return;
    }
    if (const {'home', 'my_work', 'actions', 'tasks', 'profile'}.contains(id)) {
      _selectMobileRoute(app, id);
      return;
    }
    Widget? screen;
    switch (id) {
      case 'approvals':
        screen = const EnterpriseHubScreen(initialTab: 0);
        break;
      case 'global_search':
        screen = const EnterpriseHubScreen(initialTab: 1);
        break;
      case 'team':
        screen = const TeamScreen();
        break;
      case 'sales':
        screen = const SalesScreen();
        break;
      case 'inventory':
        screen = const InventoryScreen();
        break;
      case 'purchase':
        screen = const PurchaseScreen();
        break;
      case 'finance':
        screen = const FinanceScreen();
        break;
      case 'payroll_performance':
        screen = const PerformanceScreen();
        break;
      case 'reports':
        screen = const ReportsScreen();
        break;
      case 'organization':
        screen = const OrganizationScreen();
        break;
      case 'communication':
        screen = const CommunicationScreen();
        break;
      case 'administration':
        screen = const AdministrationScreen();
        break;
      case 'erp_tools':
        screen = const ErpToolsScreen();
        break;
    }
    if (screen != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen!));
    }
  }

  bool _quickActionsVisible(AppState app) => app.canAny(const [
        'workforce.attendance.self',
        'workforce.field_visit.self',
        'workforce.leave.self',
        'daily_order.self',
        'daily_order.others',
        'sales.create',
        'inventory.transfer.create',
        'inventory.adjustment.create',
        'purchase.create',
        'finance.expense.create',
      ]);

  bool _routeAllowed(AppState app, String id) {
    if (const {'home', 'profile'}.contains(id)) return true;
    if (id == 'erp_tools') return app.erpToolsVisible;
    if (id == 'quick_actions' || id == 'actions')
      return _quickActionsVisible(app);
    if (id == 'tasks') return app.can('communication.view');
    if (id == 'approvals') return _approvalVisible(app);
    if (id == 'global_search') return !app.businessAccessBlocked;
    return app.sectionVisible(id);
  }

  bool _approvalVisible(AppState app) => app.canAny(const [
        'daily_order.approve',
        'daily_order.issue',
        'finance.expense.approve',
        'inventory.adjustment.approve',
        'workforce.leave.manage',
        'performance.manage',
        'payroll.approve',
        'finance.reversal.approve',
      ]);

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _WorkspaceContextChip extends StatelessWidget {
  const _WorkspaceContextChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
