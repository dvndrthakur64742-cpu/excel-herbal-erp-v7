import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';
import '../organization/hr_lifecycle_screen.dart';

class ActionsScreen extends ConsumerWidget {
  const ActionsScreen({
    super.key,
    required this.openMyWork,
    required this.openModule,
  });

  final VoidCallback openMyWork;
  final void Function(String) openModule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final actions = <({String label, IconData icon, VoidCallback run})>[];

    if (app.can('workforce.attendance.self')) {
      actions.add((
        label: 'Check-In / Out',
        icon: Icons.location_on_outlined,
        run: openMyWork,
      ));
    }
    if (app.canAny(const ['daily_order.self', 'daily_order.others'])) {
      actions.add((
        label: 'Create Daily Order',
        icon: Icons.shopping_cart_checkout,
        run: openMyWork,
      ));
      actions.add((
        label: 'Evening Closing',
        icon: Icons.nightlight_outlined,
        run: openMyWork,
      ));
    }
    if (app.can('workforce.field_visit.self')) {
      actions.add((
        label: 'Field Visit',
        icon: Icons.route_outlined,
        run: openMyWork,
      ));
    }
    if (app.can('workforce.leave.self')) {
      actions.add((
        label: 'Apply Leave',
        icon: Icons.event_available_outlined,
        run: openMyWork,
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
    if (app.canAny(const [
      'organization.hr.view',
      'organization.hr.manage',
      'organization.hr.review',
    ])) {
      actions.add((
        label: 'HR Lifecycle',
        icon: Icons.badge_outlined,
        run: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const HrLifecycleScreen(),
          ),
        ),
      ));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 5),
        Text(
          'Sirf aapke role aur permission ke authorised actions yahan dikhte hain.',
          style: Theme.of(context).textTheme.bodyMedium
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
              maxCrossAxisExtent: 240,
              mainAxisExtent: 116,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: actions.length,
            itemBuilder: (_, i) {
              final action = actions[i];
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: action.run,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            color: ExcelBrand.primarySoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            action.icon,
                            size: 20,
                            color: ExcelBrand.primaryDark,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          action.label,
                          style: Theme.of(context).textTheme.titleSmall,
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
