import 'package:flutter/material.dart';
import '../../theme/excel_brand.dart';

/// Navigation only: destinations are supplied AFTER the profile permission
/// checks. All records still belong to the original Employee 360 controllers.
class Employee360Workspace extends StatelessWidget {
  const Employee360Workspace({
    super.key,
    required this.tabs,
    required this.child,
  });

  final List<Tab> tabs;
  final Widget child;

  static const _groups = <String, List<String>>{
    'Overview': ['Summary'],
    'Operations': ['Sales', 'Stock', 'Stock Requests', 'Daily Reconciliation'],
    'Finance': [
      'Finance Review',
      'Person Ledger',
      'Cash Control',
      'Cash Responsibility',
      'Ledger',
    ],
    'People': ['Attendance'],
    'GPS': ['GPS Route'],
  };

  static const _icons = <String, IconData>{
    'Overview': Icons.person_outline,
    'Operations': Icons.inventory_2_outlined,
    'Finance': Icons.account_balance_outlined,
    'People': Icons.badge_outlined,
    'GPS': Icons.route_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    final visible = <String, List<int>>{
      for (final group in _groups.entries)
        group.key: [
          for (final label in group.value)
            for (var index = 0; index < tabs.length; index++)
              if (tabs[index].text == label) index,
        ],
    }..removeWhere((_, indices) => indices.isEmpty);
    assert(visible.values.expand((indices) => indices).length == tabs.length);
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, content) {
        final selected = visible.entries
            .firstWhere((group) => group.value.contains(controller.index))
            .key;
        void openGroup(String group) {
          if (group != selected) controller.animateTo(visible[group]!.first);
        }

        String label(int index) =>
            tabs[index].text == 'Ledger' ? 'Journal Lines' : tabs[index].text!;

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 840) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 224,
                    child: Material(
                      color: ExcelBrand.canvas,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                            child: Text(
                              'PROFILE WORKSPACE / V8',
                              key: const ValueKey('v8-profile-navigation'),
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: ExcelBrand.primaryDark,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .65,
                              ),
                            ),
                          ),
                          for (final group in visible.keys) ...[
                            ListTile(
                              key: ValueKey('employee360-group-$group'),
                              leading: Icon(_icons[group],
                                color: group == selected
                                    ? ExcelBrand.primaryDark : ExcelBrand.muted),
                              title: Text(group, style: TextStyle(
                                fontWeight: group == selected
                                    ? FontWeight.w900 : FontWeight.w600)),
                              selected: group == selected,
                              selectedTileColor: ExcelBrand.primarySoft,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onTap: () => openGroup(group),
                            ),
                            if (group == selected && visible[group]!.length > 1)
                              for (final index in visible[group]!)
                                ListTile(
                                  key: ValueKey('employee360-view-$index'),
                                  contentPadding: const EdgeInsets.only(
                                    left: 28,
                                    right: 8,
                                  ),
                                  title: Text(label(index)),
                                  selected: controller.index == index,
                                  selectedTileColor: ExcelBrand.primarySoft,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                  onTap: () => controller.animateTo(index),
                                ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content!),
                ],
              );
            }
            // Two bounded selectors avoid a long horizontal tab strip and keep
            // the register usable on short phones and with enlarged text.
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('employee360-section-$selected'),
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Profile section',
                    ),
                    items: [
                      for (final group in visible.keys)
                        DropdownMenuItem(value: group, child: Text(group)),
                    ],
                    onChanged: (group) {
                      if (group != null) openGroup(group);
                    },
                  ),
                ),
                if (visible[selected]!.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('employee360-record-${controller.index}'),
                      initialValue: controller.index,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'View records',
                      ),
                      items: [
                        for (final index in visible[selected]!)
                          DropdownMenuItem(
                            value: index,
                            child: Text(label(index)),
                          ),
                      ],
                      onChanged: (index) {
                        if (index != null) controller.animateTo(index);
                      },
                    ),
                  ),
                Expanded(child: content!),
              ],
            );
          },
        );
      },
    );
  }
}
