import 'package:flutter/material.dart';

import '../core/daily_order_workflow.dart';

/// Reviewer picks an ORIGINAL server-listed Daily Order, not a shadow close.
/// Selection alone makes no stock, sale, Cash or ledger mutation.
class EveningOrderPicker extends StatelessWidget {
  const EveningOrderPicker({super.key, required this.candidates});

  final List<Map<String, dynamic>> candidates;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose Evening Closing'),
    content: SizedBox(
      width: 480,
      height: 330,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('More than one order needs closing today. '
              'Choose the correct employee and original order.'),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: candidates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final row = candidates[i];
                final id = int.parse('${row['id']}');
                final name = '${row['employee_name'] ?? 'Employee #${row['employee_id']}'}';
                final code = '${row['employee_code'] ?? ''}'.trim();
                final branch = '${row['branch_name'] ?? 'Selected branch'}';
                return ListTile(
                  key: ValueKey('evening-order-$id'),
                  leading: const Icon(Icons.assignment_outlined),
                  title: Text('#$id · $name'),
                  subtitle: Text([
                    if (code.isNotEmpty) code,
                    branch,
                    DailyOrderWorkflow.statusLabel('${row['status']}'),
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).pop(id),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
    ],
  );
}
