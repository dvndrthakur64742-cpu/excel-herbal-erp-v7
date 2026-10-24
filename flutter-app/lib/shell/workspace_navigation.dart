/// Shared destination ownership for desktop and mobile. Authorization remains
/// with the shell and backend; this catalog never grants capabilities.
class WorkspaceDestination {
  const WorkspaceDestination(this.id, this.label, this.group);
  final String id;
  final String label;
  final String group;
}

class WorkspaceNavigation {
  static const destinations = <WorkspaceDestination>[
    WorkspaceDestination('home', 'Overview', 'Daily Work'),
    WorkspaceDestination('my_work', 'My Work', 'Daily Work'),
    WorkspaceDestination('tasks', 'My Tasks', 'Daily Work'),
    WorkspaceDestination('approvals', 'Action Inbox', 'Daily Work'),
    WorkspaceDestination('quick_actions', 'Create / Record', 'Daily Work'),
    WorkspaceDestination('global_search', 'Find Records', 'Daily Work'),
    WorkspaceDestination('inventory', 'Stock & Transfers', 'Stock & Sales'),
    WorkspaceDestination('sales', 'Sales', 'Stock & Sales'),
    WorkspaceDestination('purchase', 'Purchases', 'Stock & Sales'),
    WorkspaceDestination('finance', 'Finance Workspace', 'Finance'),
    WorkspaceDestination('team', 'My Team', 'People'),
    WorkspaceDestination('organization', 'People & Organization', 'People'),
    WorkspaceDestination('payroll_performance', 'Payroll & Performance', 'People'),
    WorkspaceDestination('reports', 'Business Reports', 'Reports & Administration'),
    WorkspaceDestination('communication', 'Communication', 'Reports & Administration'),
    WorkspaceDestination('administration', 'Administration', 'Reports & Administration'),
    WorkspaceDestination('erp_tools', 'ERP Tools', 'Reports & Administration'),
  ];

  static Map<String, List<WorkspaceDestination>> groups({
    required bool Function(String) allowed,
    Set<String> excluded = const {},
  }) {
    final result = <String, List<WorkspaceDestination>>{};
    for (final destination in destinations) {
      if (!excluded.contains(destination.id) && allowed(destination.id)) {
        result.putIfAbsent(destination.group, () => []).add(destination);
      }
    }
    return result;
  }
}
