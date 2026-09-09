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
import '../screens/my_work/my_work_screen.dart';
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
        final desktop = constraints.maxWidth >= 1100;
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
            padding: const EdgeInsets.fromLTRB(20, 22, 18, 18),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.business_center_outlined,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Excel Herbal ERP',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Version 7 workspace',
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
                _desktopTile(
                  'erp_tools',
                  'ERP Tools',
                  Icons.construction_outlined,
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
        onTap: () => setState(() => desktopRoute = id),
      ),
    );
  }

  Widget _desktopContent(AppState app) {
    if (!_routeAllowed(app, desktopRoute)) desktopRoute = 'home';
    final child = switch (desktopRoute) {
      'home' => const HomeScreen(),
      'my_work' => const MyWorkScreen(),
      'quick_actions' => ActionsScreen(
          openMyWork: () {
            if (app.sectionVisible('my_work'))
              setState(() => desktopRoute = 'my_work');
          },
          openModule: (id) {
            if (_routeAllowed(app, id)) setState(() => desktopRoute = id);
          },
        ),
      'tasks' => const TasksScreen(),
      'erp_tools' => const ErpToolsScreen(),
      'approvals' => const EnterpriseHubScreen(initialTab: 0),
      'global_search' => const EnterpriseHubScreen(initialTab: 1),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
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
    final width = (MediaQuery.sizeOf(context).width * .86).clamp(292.0, 360.0);
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
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 14),
              decoration: const BoxDecoration(
                color: ExcelBrand.primaryDark,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 118,
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
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
                          color: Colors.white.withOpacity(.16),
                          border: Border.all(
                            color: Colors.white.withOpacity(.28),
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _initials('${employee['full_name'] ?? 'U'}'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
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
                                    color: Colors.white.withOpacity(.78),
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
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
                children: [
                  if (moduleSections.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _drawerSectionLabel('MODULES'),
                    for (final section in moduleSections)
                      _drawerTile(
                        app: app,
                        id: '${section['id']}',
                        label: '${section['label']}',
                        icon: _icon('${section['id']}'),
                      ),
                  ],
                  const SizedBox(height: 12),
                  _drawerSectionLabel('TOOLS & CONTROL'),
                  _drawerTile(
                    app: app,
                    id: 'erp_tools',
                    label: 'ERP Tools',
                    icon: Icons.tune_rounded,
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
        'home' => const HomeScreen(),
        'my_work' => const MyWorkScreen(),
        'actions' => ActionsScreen(
            openMyWork: () => _selectMobileRoute(app, 'my_work'),
            openModule: _openModule,
          ),
        'tasks' => const TasksScreen(),
        'erp_tools' => const ErpToolsScreen(),
        'approvals' => const EnterpriseHubScreen(initialTab: 0),
        'global_search' => const EnterpriseHubScreen(initialTab: 1),
        'profile' => const ProfileScreen(),
        _ => const HomeScreen(),
      };

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
            onDestinationSelected: (v) => setState(() => mobileIndex = v),
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
        'erp_tools' => Icons.construction_outlined,
        _ => Icons.circle_outlined,
      };

  void _selectMobileRoute(AppState app, String id) {
    final items = app.bottomNav;
    final index = items.indexWhere((item) => '${item['id']}' == id);
    if (index >= 0) setState(() => mobileIndex = index);
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
        'erp_tools' => Icons.construction_outlined,
        _ => Icons.circle_outlined,
      };

  void _openModule(String id) {
    final app = ref.read(appStateProvider);
    if (!_routeAllowed(app, id)) return;
    if (MediaQuery.sizeOf(context).width >= 1100) {
      setState(() => desktopRoute = id);
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
    if (const {'home', 'profile', 'erp_tools'}.contains(id)) return true;
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
