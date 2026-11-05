import 'package:flutter/material.dart';

import '../theme/excel_brand.dart';

/// Task-first launchers. A task always opens an existing, authorised ERP
/// workflow; this widget never edits data or starts a second transaction flow.
class HomeStartTask {
  const HomeStartTask({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
}

abstract final class HomeStartTaskPlanner {
  static List<HomeStartTask> recommend({
    required bool Function(String) can,
    required bool Function(String) sectionVisible,
    required bool businessAccessBlocked,
  }) {
    if (businessAccessBlocked) return const [];

    final urgent = <HomeStartTask>[];
    final ownWork = <HomeStartTask>[];
    final otherWork = <HomeStartTask>[];

    if (sectionVisible('team') &&
        (can('daily_order.approve') ||
            can('daily_order.issue') ||
            can('daily_order.review'))) {
      urgent.add(const HomeStartTask(
        id: 'team_orders',
        title: 'Review Daily Orders',
        description: 'Open your authorised team order queue',
        icon: Icons.fact_check_outlined,
      ));
    }
    if (sectionVisible('inventory') && can('inventory.transfer.receive')) {
      urgent.add(const HomeStartTask(
        id: 'receive_stock',
        title: 'Receive Stock',
        description: 'Check transferred stock and confirm quantities',
        icon: Icons.move_to_inbox_outlined,
      ));
    }
    if (sectionVisible('finance') && can('finance.expense.approve')) {
      urgent.add(const HomeStartTask(
        id: 'review_expenses',
        title: 'Review Expenses',
        description: 'Review requests under your branch authority',
        icon: Icons.receipt_long_outlined,
      ));
    }
    if (sectionVisible('organization') && can('organization.hr.review')) {
      urgent.add(const HomeStartTask(
        id: 'review_hr',
        title: 'Review HR Requests',
        description: 'Open candidate and separation requests',
        icon: Icons.how_to_reg_outlined,
      ));
    }

    if (sectionVisible('my_work') && can('workforce.attendance.self')) {
      ownWork.add(const HomeStartTask(
        id: 'attendance',
        title: "Today's Duty",
        description: 'View automatic attendance and GPS status',
        icon: Icons.schedule_outlined,
      ));
    }
    if (sectionVisible('my_work') &&
        (can('daily_order.self') || can('daily_order.others'))) {
      ownWork.add(const HomeStartTask(
        id: 'daily_create',
        title: 'Create Daily Order',
        description: 'Choose products and quantities in PCS',
        icon: Icons.shopping_cart_checkout,
      ));
      ownWork.add(const HomeStartTask(
        id: 'evening',
        title: 'Evening Closing',
        description: 'Continue an issued order and submit closing',
        icon: Icons.nights_stay_outlined,
      ));
    }
    if (sectionVisible('my_work') && can('workforce.leave.self')) {
      ownWork.add(const HomeStartTask(
        id: 'leave',
        title: 'Request Leave',
        description: 'Choose dates, add a reason and submit',
        icon: Icons.event_available_outlined,
      ));
    }
    if (sectionVisible('my_work') && can('workforce.field_visit.self')) {
      ownWork.add(const HomeStartTask(
        id: 'field_visit',
        title: 'Field Visit',
        description: 'Start your authorised field visit',
        icon: Icons.route_outlined,
      ));
    }

    if (sectionVisible('sales') && can('sales.create')) {
      otherWork.add(const HomeStartTask(
        id: 'counter_sale',
        title: 'New Counter Sale',
        description: 'Start a sale in your authorised branch',
        icon: Icons.point_of_sale_outlined,
      ));
    }
    if (sectionVisible('purchase') && can('purchase.create')) {
      otherWork.add(const HomeStartTask(
        id: 'purchase_entry',
        title: 'New Purchase Bill',
        description: 'Enter a supplier bill with supporting details',
        icon: Icons.local_shipping_outlined,
      ));
    }
    if (sectionVisible('inventory') && can('inventory.transfer.create')) {
      otherWork.add(const HomeStartTask(
        id: 'stock_transfer',
        title: 'Transfer Stock',
        description: 'Prepare a stock request between branches',
        icon: Icons.swap_horiz_rounded,
      ));
    }
    if (sectionVisible('finance') && can('finance.expense.create')) {
      otherWork.add(const HomeStartTask(
        id: 'expense_entry',
        title: 'New Expense',
        description: 'Enter the amount, purpose and evidence',
        icon: Icons.payments_outlined,
      ));
    }
    if (sectionVisible('administration') && can('administration.access.manage')) {
      otherWork.add(const HomeStartTask(
        id: 'admin_access',
        title: 'Manage Access',
        description: 'Review roles and authorised permissions',
        icon: Icons.admin_panel_settings_outlined,
      ));
    }

    // Prioritise a manager's pending workflow, or an employee's own daily
    // work. Never use a job title to grant authority or invent activity counts.
    final ranked = urgent.isEmpty
        ? <HomeStartTask>[...ownWork, ...otherWork]
        : <HomeStartTask>[...urgent, ...otherWork, ...ownWork];
    return List<HomeStartTask>.unmodifiable(ranked.take(3));
  }
}

class HomeStartTasks extends StatelessWidget {
  const HomeStartTasks({
    super.key,
    required this.tasks,
    required this.onOpen,
  });

  final List<HomeStartTask> tasks;
  final ValueChanged<HomeStartTask> onOpen;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Start here',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 5),
        Text(
          'Choose a task to open its usual ERP workflow.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: ExcelBrand.muted,
              ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 890
                ? 3
                : constraints.maxWidth >= 580
                    ? 2
                    : 1;
            const gap = 12.0;
            final tileWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < tasks.length; i++)
                  SizedBox(
                    width: tileWidth,
                    child: _TaskCard(
                      task: tasks[i],
                      primary: i == 0,
                      onPressed: () => onOpen(tasks[i]),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.primary,
    required this.onPressed,
  });

  final HomeStartTask task;
  final bool primary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: ExcelBrand.primarySoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(task.icon, color: ExcelBrand.primaryDark),
              ),
              const SizedBox(height: 14),
              Text(
                task.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 7),
              Text(
                task.description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ExcelBrand.muted,
                    ),
              ),
              const SizedBox(height: 16),
              if (primary)
                FilledButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Open task'),
                )
              else
                OutlinedButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Open task'),
                ),
            ],
          ),
        ),
      );
}
