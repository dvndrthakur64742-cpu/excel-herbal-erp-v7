/// Defensive client-side projection for an existing server-authorised menu.
///
/// The backend remains the only security authority. This layer merely keeps
/// stale cached navigation from advertising tasks whose capability was revoked.
/// It mirrors the IDs/capability sets in App/NavigationProjection.php; unknown
/// modules are hidden until explicitly reviewed.
class NavigationAuthority {
  const NavigationAuthority._();

  static const Map<String, List<String>> _sections = {
    'my_work': [
      'workforce.attendance.self',
      'workforce.leave.self',
      'workforce.field_visit.self',
      'daily_order.self',
    ],
    'team': [
      'organization.employee.view',
      'workforce.attendance.manage',
      'workforce.leave.manage',
      'daily_order.others',
      'daily_order.approve',
      'daily_order.issue',
      'daily_order.review',
    ],
    'sales': [
      'sales.view', 'sales.create', 'sales.receipt.create',
    ],
    'inventory': [
      'inventory.view',
      'inventory.transfer.create',
      'inventory.transfer.receive',
      'inventory.transfer.cancel',
      'inventory.adjustment.create',
      'inventory.adjustment.approve',
    ],
    'purchase': [
      'purchase.view',
      'purchase.create',
      'finance.supplier_payment.create',
    ],
    'finance': [
      'finance.view',
      'finance.accounting.view',
      'finance.account.manage',
      'finance.expense.create',
      'finance.expense.approve',
      'finance.branch_close',
      'finance.branch_reopen',
      'finance.reversal.create',
      'finance.reversal.approve',
      'finance.period.manage',
      'finance.bank_reconcile',
    ],
    'payroll_performance': [
      'payroll.generate',
      'payroll.approve',
      'payroll.pay',
      'performance.view',
      'performance.manage',
    ],
    'reports': ['reports.view', 'finance.accounting.view'],
    'organization': [
      'organization.employee.view',
      'organization.employee.manage',
      'organization.hr.view',
      'organization.hr.manage',
      'organization.hr.review',
      'organization.branch.view',
      'organization.branch.manage',
      'catalog.product.view',
      'catalog.product.manage',
    ],
    'communication': ['communication.view', 'communication.manage'],
    'administration': [
      'administration.audit.view',
      'administration.access.manage',
      'finance.reversal.create',
      'finance.reversal.approve',
      'finance.period.manage',
    ],
  };

  static const List<String> _quickTaskCapabilities = [
    'daily_order.self',
    'daily_order.others',
    'sales.create',
    'sales.receipt.create',
    'inventory.transfer.create',
    'inventory.adjustment.create',
    'purchase.create',
    'finance.expense.create',
  ];

  static bool sectionAllowed(String id, bool Function(String) can) {
    if (id == 'home') return true;
    final required = _sections[id];
    return required != null && required.any(can);
  }

  static bool bottomAllowed(
    String id,
    bool Function(String) can, {
    required bool erpToolsVisible,
  }) {
    switch (id) {
      case 'home':
      case 'profile':
        return true;
      case 'my_work':
        return sectionAllowed('my_work', can);
      case 'actions':
        return _quickTaskCapabilities.any(can);
      case 'tasks':
        return can('communication.view');
      case 'erp_tools':
        return erpToolsVisible;
      default:
        return false;
    }
  }
}
