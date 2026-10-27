import 'package:flutter/material.dart';

import 'v8_module_banner.dart';

/// Stock identity uses the same light Command Center design as Sales, Finance
/// and Employee 360. Scope comes from the selected, authorised branch.
class V8InventoryBanner extends StatelessWidget {
  const V8InventoryBanner({
    super.key,
    required this.branch,
    required this.businessDate,
  });

  final String branch;
  final String businessDate;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
        key: const ValueKey('v8-inventory-banner'),
        child: V8ModuleBanner(
          eyebrow: 'Stock operations / ERP V8',
          title: 'Inventory control',
          description: 'Stock, transfers, adjustments and quarantine.',
          icon: Icons.inventory_2_outlined,
          context: [branch, businessDate],
        ),
      );
}
