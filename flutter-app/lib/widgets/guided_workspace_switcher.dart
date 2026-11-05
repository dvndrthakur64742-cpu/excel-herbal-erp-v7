import 'package:flutter/material.dart';

/// One navigation control for an existing TabBarView. This replaces a second
/// layer of duplicated action buttons; it never posts or modifies records.
class GuidedWorkspaceSection {
  const GuidedWorkspaceSection({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  /// Uses exactly the tab labels projected by the existing permission gates.
  /// Nothing here grants access, creates a workflow or invents any record.
  factory GuidedWorkspaceSection.forTab(String label) => switch (label) {
        'Daily Orders' => const GuidedWorkspaceSection(
            title: 'Review Daily Orders',
            description: 'Check submitted team orders and authorised stock issue.',
            icon: Icons.assignment_turned_in_outlined,
          ),
        'Attendance' => const GuidedWorkspaceSection(
            title: 'Team Attendance',
            description: 'See recorded attendance for the selected branch.',
            icon: Icons.event_available_outlined,
          ),
        'GPS Team' => const GuidedWorkspaceSection(
            title: 'Team GPS & Routes',
            description: 'View authorised field team location and route records.',
            icon: Icons.route_outlined,
          ),
        'Holidays' => const GuidedWorkspaceSection(
            title: 'Holiday Calendar',
            description: 'Check the branch calendar and permitted holiday actions.',
            icon: Icons.calendar_today_outlined,
          ),
        'Hierarchy' => const GuidedWorkspaceSection(
            title: 'Reporting Hierarchy',
            description: 'Check team reporting links and missing assignments.',
            icon: Icons.account_tree_outlined,
          ),
        'Employees' => const GuidedWorkspaceSection(
            title: 'Team Directory',
            description: 'Browse authorised employee records; avoid duplicate HR entry.',
            icon: Icons.people_outline_rounded,
          ),
        'Books' => const GuidedWorkspaceSection(
            title: 'Accounts & Books',
            description: 'Check balances and account records before taking action.',
            icon: Icons.menu_book_outlined,
          ),
        'Expenses' => const GuidedWorkspaceSection(
            title: 'Expenses & Approvals',
            description: 'Review expenses or create an authorised expense entry.',
            icon: Icons.receipt_long_outlined,
          ),
        'Closing' => const GuidedWorkspaceSection(
            title: 'Branch Day Closing',
            description: 'Run preflight checks before creating or closing a draft.',
            icon: Icons.fact_check_outlined,
          ),
        'Bank' => const GuidedWorkspaceSection(
            title: 'Bank Reconciliation',
            description: 'Check matching and outstanding bank movements.',
            icon: Icons.account_balance_outlined,
          ),
        'Periods' => const GuidedWorkspaceSection(
            title: 'Accounting Periods',
            description: 'Review authorised period controls and status.',
            icon: Icons.calendar_month_outlined,
          ),
        'Reversals' => const GuidedWorkspaceSection(
            title: 'Reversal Requests',
            description: 'Review sensitive reversals using existing approval checks.',
            icon: Icons.undo_outlined,
          ),
        'Acting Duty' => const GuidedWorkspaceSection(
            title: 'Acting Duty',
            description: 'Manage authorised temporary delegated responsibilities.',
            icon: Icons.badge_outlined,
          ),
        'Access' => const GuidedWorkspaceSection(
            title: 'Roles & Permissions',
            description: 'Manage access within your existing branch authority.',
            icon: Icons.admin_panel_settings_outlined,
          ),
        'Audit Log' => const GuidedWorkspaceSection(
            title: 'Audit History',
            description: 'Read the immutable history of recorded ERP actions.',
            icon: Icons.history_outlined,
          ),
        'System Health' => const GuidedWorkspaceSection(
            title: 'System Health',
            description: 'Review diagnostics before requesting a technical change.',
            icon: Icons.health_and_safety_outlined,
          ),
        _ => GuidedWorkspaceSection(
            title: label,
            description: 'Review authorised records in this section.',
            icon: Icons.view_list_outlined,
          ),
      };
}

class GuidedWorkspaceSwitcher extends StatelessWidget {
  const GuidedWorkspaceSwitcher({
    super.key,
    required this.title,
    required this.sections,
  });

  final String title;
  final List<GuidedWorkspaceSection> sections;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) return const SizedBox.shrink();
    final controller = DefaultTabController.of(context);
    assert(controller.length == sections.length);
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final active = controller.index >= 0 &&
                controller.index < sections.length
            ? controller.index
            : 0;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 710;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Choose a task to see its authorised records and next steps.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    if (compact)
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'What do you need to do?',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: active,
                            isExpanded: true,
                            items: [
                              for (var i = 0; i < sections.length; i++)
                                DropdownMenuItem<int>(
                                  value: i,
                                  child: Text(
                                    sections[i].title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (index) {
                              if (index != null) controller.animateTo(index);
                            },
                          ),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < sections.length; i++)
                            ChoiceChip(
                              key: ValueKey('workspace-section-$i'),
                              selected: active == i,
                              label: Text(sections[i].title),
                              avatar: Icon(
                                sections[i].icon,
                                size: 18,
                                color: active == i
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurfaceVariant,
                              ),
                              onSelected: (_) => controller.animateTo(i),
                            ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 17,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sections[active].description,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
