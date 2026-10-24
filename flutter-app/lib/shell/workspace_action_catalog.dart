import 'package:flutter/material.dart';

/// Single navigation contract for the existing connected workflow screens.
/// This only filters UI actions; the existing V7 REST service owns RBAC and
/// enforces every mutation again. Never use this to grant permissions.
class WorkspaceAction {
  const WorkspaceAction(this.id, this.label, this.icon, this.anyCapability);

  final String id;
  final String label;
  final IconData icon;
  final List<String> anyCapability;

  bool allowed(bool Function(String) can) => anyCapability.any(can);
}

abstract final class WorkspaceActionCatalog {
  static const actions = <WorkspaceAction>[
    WorkspaceAction('attendance', 'Check-In / Out',
        Icons.location_on_outlined, ['workforce.attendance.self']),
    WorkspaceAction('daily_create', 'Create Daily Order',
        Icons.shopping_cart_checkout, ['daily_order.self', 'daily_order.others']),
    WorkspaceAction('evening', 'Evening Closing',
        Icons.nightlight_outlined, ['daily_order.self', 'daily_order.others']),
    WorkspaceAction('field_visit', 'Field Visit',
        Icons.route_outlined, ['workforce.field_visit.self']),
    WorkspaceAction('leave', 'Apply Leave',
        Icons.event_available_outlined, ['workforce.leave.self']),
    WorkspaceAction('counter_sale', 'Counter Sale',
        Icons.point_of_sale, ['sales.create']),
    WorkspaceAction('stock_transfer', 'Stock Transfer',
        Icons.swap_horiz, ['inventory.transfer.create']),
    WorkspaceAction('stock_adjustment', 'Stock Adjustment',
        Icons.fact_check_outlined, ['inventory.adjustment.create']),
    WorkspaceAction('purchase_entry', 'Purchase Entry',
        Icons.local_shipping_outlined, ['purchase.create']),
    WorkspaceAction('expense_entry', 'Expense Entry',
        Icons.receipt_long_outlined, ['finance.expense.create']),
    WorkspaceAction('hr_lifecycle', 'HR Lifecycle',
        Icons.badge_outlined, [
          'organization.hr.view', 'organization.hr.manage',
          'organization.hr.review',
        ]),
  ];

  static List<WorkspaceAction> visible(bool Function(String) can) =>
      List<WorkspaceAction>.unmodifiable(
        actions.where((action) => action.allowed(can)),
      );

  /// Check again when the user taps: a dialog or a cached widget can outlive
  /// a changed branch, revoked role, logout or refreshed bootstrap.
  static bool allows(String id, bool Function(String) can) {
    for (final action in actions) {
      if (action.id == id) return action.allowed(can);
    }
    return false;
  }
}
