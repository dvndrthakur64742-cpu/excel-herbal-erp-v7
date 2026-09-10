import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final employee = app.employee;
    final manager = '${employee['reporting_employee_name'] ?? ''}'.trim();
    final managerCode = '${employee['reporting_employee_code'] ?? ''}'.trim();
    final reporting = _reportingLabel(app.reportingCategory);
    final extras = app.additionalDesignations;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Profile', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: ExcelBrand.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: ExcelBrand.primaryDark,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${employee['full_name'] ?? 'Employee'}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${employee['employee_code'] ?? '—'} · ${app.primaryDesignationLabel}',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: ExcelBrand.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              _InfoTile(
                icon: Icons.badge_outlined,
                label: 'Primary Designation',
                value: app.primaryDesignationLabel,
              ),
              const Divider(height: 1),
              _InfoTile(
                icon: Icons.account_tree_outlined,
                label: 'Reporting Category',
                value: reporting,
                helper: 'Reporting grouping only — permission/branch authority नहीं बढ़ती।',
              ),
              const Divider(height: 1),
              _InfoTile(
                icon: Icons.supervisor_account_outlined,
                label: 'Reporting Manager',
                value: manager.isEmpty
                    ? 'Not assigned'
                    : managerCode.isEmpty
                    ? manager
                    : '$manager · $managerCode',
              ),
              const Divider(height: 1),
              _InfoTile(
                icon: Icons.store_outlined,
                label: 'Current Branch',
                value: app.currentBranchName,
              ),
              const Divider(height: 1),
              _InfoTile(
                icon: Icons.shield_outlined,
                label: 'Authorised Access',
                value:
                    '${app.branches.length} branch${app.branches.length == 1 ? '' : 'es'}',
              ),
              const Divider(height: 1),
              _InfoTile(
                icon: Icons.phone_outlined,
                label: 'Mobile',
                value: '${employee['mobile'] ?? '—'}',
              ),
              const Divider(height: 1),
              _InfoTile(
                icon: Icons.email_outlined,
                label: 'Email',
                value: '${employee['email'] ?? '—'}',
              ),
            ],
          ),
        ),
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Additional / Temporary Designations',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'These are responsibility/display assignments only; they do not inherit authority.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: ExcelBrand.muted),
                  ),
                  const SizedBox(height: 10),
                  for (final item in extras) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        '${item['assignment_type']}' == 'temporary'
                            ? Icons.schedule_outlined
                            : Icons.add_moderator_outlined,
                      ),
                      title: Text(_designationLabel(item)),
                      subtitle: Text(_assignmentPeriod(item)),
                      trailing: Chip(
                        label: Text(
                          '${item['assignment_type'] ?? 'additional'}'
                              .toUpperCase(),
                        ),
                      ),
                    ),
                    if (item != extras.last) const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => ref.read(appStateProvider.notifier).logout(),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Logout'),
        ),
      ],
    );
  }

  String _reportingLabel(String value) {
    if (value.isEmpty) return 'Not assigned';
    return value
        .split('_')
        .where((e) => e.isNotEmpty)
        .map((e) => '${e[0]}${e.substring(1).toLowerCase()}')
        .join(' ');
  }

  String _designationLabel(Map<String, dynamic> item) {
    final name = '${item['designation_name'] ?? ''}'.trim();
    final code = '${item['designation_code'] ?? ''}'.trim();
    if (name.isEmpty) return code.isEmpty ? 'Designation' : code;
    if (code.isEmpty || name.toUpperCase() == code.toUpperCase()) return name;
    return '$name ($code)';
  }

  String _assignmentPeriod(Map<String, dynamic> item) {
    final from = '${item['effective_from'] ?? ''}'.trim();
    final to = '${item['effective_to'] ?? ''}'.trim();
    if (from.isEmpty && to.isEmpty) return 'Effective period not supplied';
    if (to.isEmpty) return 'From $from · ongoing';
    return '$from → $to';
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.helper,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? helper;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label, style: Theme.of(context).textTheme.bodySmall),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (helper != null) ...[
            const SizedBox(height: 2),
            Text(
              helper!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: ExcelBrand.muted),
            ),
          ],
        ],
      ),
    ),
  );
}
