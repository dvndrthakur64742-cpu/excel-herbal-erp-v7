import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';
import '../tools/erp_tools_screen.dart';
import '../organization/employee_360_screen.dart';
import 'employee_id_card_screen.dart';

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
                _profilePhoto(employee),
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
        FilledButton.tonalIcon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EmployeeIdCardScreen(
                employee: Map<String, dynamic>.from(employee),
                branchName: app.currentBranchName,
                designation: app.primaryDesignationLabel,
              ),
            ),
          ),
          icon: const Icon(Icons.badge_outlined),
          label: const Text('View / Print Employee I-Card'),
        ),
        if ((int.tryParse('${employee['id'] ?? ''}') ?? 0) > 0) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('employee-360-self'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => Employee360Screen(
                  employeeId: int.parse('${employee['id']}'),
                  employeeName: '${employee['full_name'] ?? 'Employee'}',
                ),
              ),
            ),
            icon: const Icon(Icons.insights_outlined),
            label: const Text('My Sales, Points & Stock'),
          ),
        ],
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
                helper:
                    'Reporting group only. It does not increase role permissions or branch authority.',
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
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ErpToolsScreen(accountOnly: true),
            ),
          ),
          icon: const Icon(Icons.security_outlined),
          label: const Text('Account & Security'),
        ),
        const SizedBox(height: 12),
        const _ActingDutySummary(),
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
          label: const Text('Sign out'),
        ),
      ],
    );
  }

  Widget _profilePhoto(Map<String, dynamic> employee) {
    final photoUrl = _photoUrl(employee);
    return Container(
      width: 58,
      height: 58,
      decoration: const BoxDecoration(
        color: ExcelBrand.primarySoft,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: photoUrl == null
          ? const Icon(
              Icons.person_rounded,
              color: ExcelBrand.primaryDark,
              size: 30,
            )
          : Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.person_rounded,
                color: ExcelBrand.primaryDark,
                size: 30,
              ),
            ),
    );
  }

  String? _photoUrl(Map<String, dynamic> employee) {
    for (final key in const [
      'profile_photo_url',
      'photo_url',
      'employee_photo_url',
      'photo',
    ]) {
      final value = '${employee[key] ?? ''}'.trim();
      if (value.startsWith('https://') || value.startsWith('http://')) {
        return value;
      }
    }
    return null;
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


class _ActingDutySummary extends ConsumerWidget {
  const _ActingDutySummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final employeeId = int.tryParse('${app.employee['id'] ?? ''}') ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<dynamic>>(
          future: Future.wait<dynamic>([
            api.get(ApiPaths.actingDelegations),
            api.get(ApiPaths.actingInbox),
          ]),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 72,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            if (snapshot.hasError) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.assignment_ind_outlined),
                title: const Text('Acting Duty'),
                subtitle: Text(UiError.message(snapshot.error!)),
              );
            }

            final values = snapshot.data ?? const [];
            final delegationData = values.isNotEmpty && values[0] is Map
                ? Map<String, dynamic>.from(values[0] as Map)
                : <String, dynamic>{};
            final inboxData = values.length > 1 && values[1] is Map
                ? Map<String, dynamic>.from(values[1] as Map)
                : <String, dynamic>{};
            final delegations =
                ((delegationData['delegations'] as List?) ?? const [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .where((row) {
                      final status = '${row['effective_status'] ?? row['status'] ?? ''}';
                      return status == 'active' || status == 'scheduled';
                    })
                    .toList();
            final inbox = ((inboxData['items'] as List?) ?? const [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();

            if (delegations.isEmpty && inbox.isEmpty) {
              return const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.assignment_ind_outlined),
                title: Text('Acting Duty'),
                subtitle: Text(
                  'No temporary acting duty is currently assigned. Permanent role and branch authority remain unchanged.',
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.assignment_ind_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Acting Duty',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (inbox.isNotEmpty)
                      Chip(label: Text('${inbox.length} work item${inbox.length == 1 ? '' : 's'}')),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Temporary authority is limited to the exact action, branch and time window shown below.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: ExcelBrand.muted),
                ),
                if (delegations.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final row in delegations.take(4))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        int.tryParse('${row['delegate_employee_id']}') ==
                                employeeId
                            ? Icons.login_rounded
                            : Icons.logout_rounded,
                      ),
                      title: Text(_actingActionLabel('${row['action_code']}')),
                      subtitle: Text(
                        int.tryParse('${row['delegate_employee_id']}') ==
                                employeeId
                            ? 'From ${row['delegator_name'] ?? 'delegator'} · Branch #${row['branch_id']} · until ${row['ends_at']}'
                            : 'To ${row['delegate_name'] ?? 'delegate'} · Branch #${row['branch_id']} · until ${row['ends_at']}',
                      ),
                      trailing: Text(
                        '${row['effective_status'] ?? row['status'] ?? ''}',
                      ),
                    ),
                ],
                if (inbox.isNotEmpty) ...[
                  const Divider(),
                  Text(
                    'Delegated Work Inbox',
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  for (final item in inbox.take(4))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.task_alt_outlined),
                      title: Text(
                        _actingActionLabel('${item['action_code'] ?? ''}'),
                      ),
                      subtitle: Text(
                        '${(item['work'] as Map?)?['employee_name'] ?? 'Pending work'} · expires ${item['expires_at'] ?? ''}',
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  String _actingActionLabel(String action) => switch (action) {
        'daily.approve' => 'Approve Daily Order',
        'daily.issue' => 'Issue Daily Stock',
        'daily.final_post' => 'Final Post Daily Order',
        'workforce.leave.decision' => 'Decide Leave Request',
        _ => action,
      };
}
