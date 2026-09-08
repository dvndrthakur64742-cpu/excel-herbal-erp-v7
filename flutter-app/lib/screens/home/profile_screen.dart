import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final employee = Map<String, dynamic>.from(
      (app.me['employee'] as Map?) ?? const {},
    );
    final designation =
        '${employee['designation_name'] ?? employee['designation_code'] ?? '—'}';
    final manager = '${employee['reporting_employee_name'] ?? ''}'.trim();
    final managerCode = '${employee['reporting_employee_code'] ?? ''}'.trim();

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
                  child: const Icon(Icons.person_rounded, color: ExcelBrand.primaryDark, size: 30),
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
                        '${employee['employee_code'] ?? '—'} · $designation',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ExcelBrand.muted),
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
              _InfoTile(icon: Icons.store_outlined, label: 'Current Branch', value: app.currentBranchName),
              const Divider(height: 1),
              _InfoTile(icon: Icons.shield_outlined, label: 'Authorised Access', value: '${app.branches.length} branch${app.branches.length == 1 ? '' : 'es'}'),
              const Divider(height: 1),
              _InfoTile(icon: Icons.phone_outlined, label: 'Mobile', value: '${employee['mobile'] ?? '—'}'),
              const Divider(height: 1),
              _InfoTile(icon: Icons.email_outlined, label: 'Email', value: '${employee['email'] ?? '—'}'),
              const Divider(height: 1),
              _InfoTile(
                icon: Icons.account_tree_outlined,
                label: 'Reporting Manager',
                value: manager.isEmpty
                    ? 'Not assigned'
                    : managerCode.isEmpty
                        ? manager
                        : '$manager · $managerCode',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => ref.read(appStateProvider.notifier).logout(),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Logout'),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(label, style: Theme.of(context).textTheme.bodySmall),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(value, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
        ),
      );
}