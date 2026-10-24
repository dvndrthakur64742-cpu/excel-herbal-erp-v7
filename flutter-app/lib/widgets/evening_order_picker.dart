import 'package:flutter/material.dart';

import '../core/daily_order_workflow.dart';

/// Search and select one ORIGINAL server-authorised Daily Order.
/// Filtering is purely in-memory; caller and REST service must recheck
/// branch, actor, status and current permissions before mutation.
class EveningOrderPicker extends StatefulWidget {
  const EveningOrderPicker({super.key, required this.candidates});

  final List<Map<String, dynamic>> candidates;

  @override
  State<EveningOrderPicker> createState() => _EveningOrderPickerState();
}

class _EveningOrderPickerState extends State<EveningOrderPicker> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _visible() {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.candidates;
    return widget.candidates.where((row) {
      final id = '${row['id'] ?? ''}';
      final name = '${row['employee_name'] ?? ''}';
      final code = '${row['employee_code'] ?? ''}';
      final branch = '${row['branch_name'] ?? ''}';
      final status = DailyOrderWorkflow.orderStatusLabel(row);
      return [id, '#$id', name, code, branch, status].any(
        (field) => field.toLowerCase().contains(query),
      );
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible();
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height - media.viewInsets.bottom;
    final contentHeight = (availableHeight * .54).clamp(168.0, 360.0).toDouble();

    return AlertDialog(
      key: const ValueKey('v8-evening-order-picker'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: const Text('Choose Evening Closing'),
      content: SizedBox(
        width: 480,
        height: contentHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose the correct employee and original order. '
              'Only the already-authorised orders are listed.',
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('evening-order-search'),
              controller: _search,
              onChanged: (query) => setState(() => _query = query),
              decoration: InputDecoration(
                labelText: 'Search order or employee',
                hintText: 'Order ID, employee name or code',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear order search',
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              'Showing ${visible.length} of ${widget.candidates.length} eligible orders',
              key: const ValueKey('evening-order-result-count'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 7),
            Expanded(
              child: visible.isEmpty
                  ? const Center(
                      key: ValueKey('evening-order-no-results'),
                      child: Text(
                        'No matching orders. Check the ID or employee name.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final row = visible[i];
                        final id = int.parse('${row['id']}');
                        final name =
                            '${row['employee_name'] ?? 'Employee #${row['employee_id']}'}';
                        final code = '${row['employee_code'] ?? ''}'.trim();
                        final branch =
                            '${row['branch_name'] ?? 'Selected branch'}';
                        return ListTile(
                          key: ValueKey('evening-order-$id'),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: const Icon(Icons.assignment_outlined),
                          title: Text('#$id · $name',
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [
                              if (code.isNotEmpty) code,
                              branch,
                              DailyOrderWorkflow.orderStatusLabel(row),
                            ].join(' · '),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
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
}
