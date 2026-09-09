import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';

class ActionsScreen extends ConsumerWidget {
  const ActionsScreen({
    super.key,
    required this.openMyWork,
    required this.openModule,
  });

  final void Function(String section) openMyWork;
  final void Function(String) openModule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final actions = <({String label, IconData icon, VoidCallback run})>[];

    if (app.can('workforce.attendance.self')) {
      actions.add((
        label: 'Check-In / Out',
        icon: Icons.location_on_outlined,
        run: () => openMyWork('attendance'),
      ));
    }
    if (app.canAny(const ['daily_order.self', 'daily_order.others'])) {
      actions.add((
        label: 'Create Daily Order',
        icon: Icons.shopping_cart_checkout,
        run: () => openMyWork('daily'),
      ));
      actions.add((
        label: 'Evening Closing',
        icon: Icons.nightlight_outlined,
        run: () => openMyWork('daily'),
      ));
    }
    if (app.can('workforce.field_visit.self')) {
      actions.add((
        label: 'Field Visit',
        icon: Icons.route_outlined,
        run: () => openMyWork('leave_visit'),
      ));
    }
    if (app.can('workforce.leave.self')) {
      actions.add((
        label: 'Apply Leave',
        icon: Icons.event_available_outlined,
        run: () => openMyWork('leave_visit'),
      ));
    }
    if (app.can('sales.create')) {
      actions.add((
        label: 'Counter Sale',
        icon: Icons.point_of_sale,
        run: () => openModule('sales'),
      ));
    }
    if (app.can('inventory.transfer.create')) {
      actions.add((
        label: 'Stock Transfer',
        icon: Icons.swap_horiz,
        run: () => openModule('inventory'),
      ));
    }
    if (app.can('purchase.create')) {
      actions.add((
        label: 'Purchase Entry',
        icon: Icons.local_shipping_outlined,
        run: () => openModule('purchase'),
      ));
    }
    if (app.can('finance.expense.create')) {
      actions.add((
        label: 'Expense Entry',
        icon: Icons.receipt_long_outlined,
        run: () => openModule('finance'),
      ));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 5),
        Text(
          'Role-based shortcuts for the actions you can perform now.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: ExcelBrand.muted),
        ),
        const SizedBox(height: 16),
        if (actions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Aapke role ke liye koi quick action available nahi hai.',
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisExtent: 72,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: actions.length,
            itemBuilder: (_, i) {
              final action = actions[i];
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: action.run,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: ExcelBrand.primarySoft,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            action.icon,
                            size: 18,
                            color: ExcelBrand.primaryDark,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            action.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: ExcelBrand.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
