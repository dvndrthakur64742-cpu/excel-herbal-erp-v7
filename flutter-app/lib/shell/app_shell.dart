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
import '../screens/organization/hr_lifecycle_screen.dart';
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
import 'workspace_navigation.dart';
import 'workspace_action_catalog.dart';
import 'v8_workspace_chrome.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int mobileIndex = 0;
  String desktopRoute = 'home';

  @override
  void initState() {
    super.initState();
    const allowed = {
      'home',
      'my_work',
      'quick_actions',
      'tasks',
      'erp_tools',
      'approvals',
      'global_search',
      'profile',
      'team',
      'sales',
      'inventory',
      'purchase',
      'finance',
      'payroll_performance',
      'reports',
      'organization',
      'communication',
      'administration',
    };
    final requested = Uri.base.queryParameters['eh7_module']?.trim();
    if (requested != null && allowed.contains(requested)) {
      desktopRoute = requested;
    }
  }

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
                  SizedBox(width: 264, child: _desktopSidebar(context, app)),
                  Expanded(
                    child: ColoredBox(
                      color: ExcelBrand.canvas,
                      child: Column(children: [
                        V8WorkspaceContextBar(
                          branch: _currentBranchLabel(app),
                          activeRoute: _activeRouteTitle(app),
                          onOpenActions: _quickActionsVisible(app)
                            ? () => _openModule('quick_actions') : null,
                        ),
                        Expanded(child: _desktopContent(app)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final items = _mobileItems(app);
        final selectedIndex = items.indexWhere((item) => item['id'] == desktopRoute);
        final safeIndex = selectedIndex >= 0 ? selectedIndex : 0;
        final route = '${items[safeIndex]['id']}';
        return Scaffold(
          drawerEdgeDragWidth: 28,
          appBar: AppBar(
            title: V8MobileTitle(title: '${items[safeIndex]['label']}'),
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
      color: ExcelBrand.navDark,
      child: Column(
        children: [
          const V8SidebarBrand(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              children: [
                for (final group in WorkspaceNavigation.groups(
                  allowed: (id) => _routeAllowed(app, id),
                ).entries) ...[
                  _sectionLabel(context, group.key),
                  for (final destination in group.value)
                    _desktopTile(destination.id, destination.label,
                        _icon(destination.id)),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: ExcelBrand.navRaised),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: ExcelBrand.navRaised,
                  foregroundColor: Colors.white,
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
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white),
                      ),
                      Text(
                        '${employee['employee_code'] ?? ''} · ${employee['designation_code'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ExcelBrand.navMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Logout',
                  onPressed: () => ref.read(appStateProvider.notifier).logout(),
                  icon: const Icon(Icons.logout, size: 20, color: ExcelBrand.navMuted),
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
                color: ExcelBrand.navMuted,
              ),
        ),
      );

  Widget _desktopTile(String id, String label, IconData icon) {
    final selected = desktopRoute == id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: AnimatedContainer(
        key: ValueKey('v8-nav-$id'),
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? ExcelBrand.navRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          border: selected
              ? const Border(left: BorderSide(color: ExcelBrand.accent, width: 3))
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
          leading: Icon(icon, size: 21,
            color: selected ? ExcelBrand.accent : ExcelBrand.navMuted),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : ExcelBrand.navText,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
          onTap: () => _selectDesktopRoute(id),
          ),
        ),
      ),
    );
  }

  String _activeRouteTitle(AppState app) {
    final id = _routeAllowed(app, desktopRoute) ? desktopRoute : 'home';
    for (final item in WorkspaceNavigation.destinations) {
      if (item.id == id) return item.label;
    }
    return 'Overview';
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
      'organization' => OrganizationScreen(
          initialTab: Uri.base.queryParameters['eh7_tab'],
        ),
      'communication' => const CommunicationScreen(),
      'administration' => const AdministrationScreen(),
      _ => const HomeScreen(),
    };

    // Desktop modules already provide their own AppBar/title/tabs. Keeping a
    // second workspace header here created competing page hierarchies and
    // reduced the usable data area, especially on record-heavy ERP screens.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: child,
        ),
      ),
    );
  }

  Drawer _mobileDrawer(AppState app) {
    final employee = Map<String, dynamic>.from(
      (app.me['employee'] as Map?) ?? const {},
    );
    final width = (MediaQuery.sizeOf(context).width * .9).clamp(300.0, 390.0);
    final branch = _currentBranchLabel(app);
    final designation =
        '${employee['designation_name'] ?? employee['designation_code'] ?? ''}'
            .trim();
    final groups = WorkspaceNavigation.groups(
      allowed: (id) => _routeAllowed(app, id),
      excluded: {
        for (final item in _mobileItems(app)) '${item['id']}',
        // Mobile creation shortcuts already have their bottom-bar entry.
        if (_mobileItems(app).any((item) => item['id'] == 'actions'))
          'quick_actions',
      },
    );

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
                  for (final group in groups.entries) ...[
                    _drawerSectionLabel(group.key),
                    for (final destination in group.value)
                      _drawerTile(
                        app: app,
                        id: destination.id,
                        label: destination.label,
                        icon: _icon(destination.id),
                      ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            Material(
              color: ExcelBrand.surface,
              child: Padding(
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
    final items = _mobileItems(app);
    final safeIndex = items.indexWhere((item) => item['id'] == desktopRoute);
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
    final actions = WorkspaceActionCatalog.visible(app.can);
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
    // The sheet captured a former bootstrap/branch. Never honor that stale
    // action after the server-authorized capability projection changes.
    if (!WorkspaceActionCatalog.allows(
        selected, ref.read(appStateProvider).can)) return;
    _openConnectedAction(selected);
  }

  void _openConnectedAction(String id) {
    // Defense in depth for BOTH full Actions screen and mobile action sheet.
    // The backend separately validates every original ERP mutation.
    if (!WorkspaceActionCatalog.allows(
        id, ref.read(appStateProvider).can)) return;
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
      case 'stock_adjustment':
        screen = const InventoryScreen(
          initialSection: 'adjustments',
          initialAction: 'adjustment',
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
      case 'hr_lifecycle':
        screen = const HrLifecycleScreen();
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
    final index = _mobileItems(app).indexWhere((item) => '${item['id']}' == id);
    setState(() {
      desktopRoute = id;
      if (index >= 0) mobileIndex = index;
    });
  }

  void _selectMobileRoute(AppState app, String id) {
    final items = _mobileItems(app);
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
        'quick_actions' => Icons.add_circle_outline,
        'tasks' => Icons.task_alt_outlined,
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
    if (const {'home', 'my_work', 'actions', 'tasks', 'profile'}.contains(id) &&
        _mobileItems(app).any((item) => item['id'] == id)) {
      _selectMobileRoute(app, id);
      return;
    }
    Widget? screen;
    switch (id) {
      case 'home':
        screen = const HomeScreen();
        break;
      case 'my_work':
        screen = const Scaffold(
          body: SafeArea(child: MyWorkWorkspaceScreen()),
        );
        break;
      case 'tasks':
        screen = const TasksScreen();
        break;
      case 'quick_actions':
        _showQuickActions(app);
        return;
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

  List<Map<String, dynamic>> _mobileItems(AppState app) =>
      WorkspaceNavigation.mobileItems(
        app.bottomNav,
        allowed: (id) => _routeAllowed(app, id),
      );

  bool _quickActionsVisible(AppState app) =>
      WorkspaceActionCatalog.visible(app.can).isNotEmpty;

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

