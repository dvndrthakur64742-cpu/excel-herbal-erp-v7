import 'package:flutter/material.dart';
import '../theme/excel_brand.dart';

/// Stages describe only the original authorised Daily Order list.
/// These counters are not sales, stock, Cash or global branch totals.
abstract final class V8DailyOrderStages {
  static const all = 'all';
  static const filters = <(String, String)>[
    ('all', 'All'), ('draft', 'Draft'), ('approval', 'Approval'),
    ('issue', 'Stock Issue'), ('field', 'Field Closing'),
    ('review', 'Final Review'), ('closed', 'Closed'),
  ];

  static String stage(Map<String, dynamic> row) {
    final status = '${row['status'] ?? ''}';
    final additional = '${row['additional_request_status'] ?? ''}';
    if (status == 'issued' && additional == 'submitted') return 'approval';
    if (status == 'issued' && additional == 'approved') return 'issue';
    return switch (status) {
      'morning_draft' => 'draft',
      'stock_requested' => 'approval',
      'approved' => 'issue',
      'issued' || 'evening_draft' => 'field',
      'evening_submitted' => 'review',
      'completed' || 'cancelled' || 'rejected' => 'closed',
      _ => '',
    };
  }

  static List<Map<String, dynamic>> visible(
      List<Map<String, dynamic>> rows, String filter) {
    if (filter == all) return List.unmodifiable(rows);
    if (!filters.any((f) => f.$1 == filter)) return const [];
    return List.unmodifiable(rows.where((r) => stage(r) == filter));
  }

  static int count(List<Map<String, dynamic>> rows, String stage) =>
      visible(rows, stage).length;
}

class V8DailyOrderBoard extends StatelessWidget {
  const V8DailyOrderBoard({
    super.key, required this.rows, required this.selectedStage,
    required this.onStageChanged,
  });
  final List<Map<String, dynamic>> rows;
  final String selectedStage;
  final ValueChanged<String> onStageChanged;

  @override
  Widget build(BuildContext context) {
    final typography = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('v8-daily-workboard'),
      margin: const EdgeInsets.fromLTRB(14, 9, 14, 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ExcelBrand.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ExcelBrand.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_tree_rounded,
              color: ExcelBrand.primaryDark, size: 24),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Daily Order Workflow',
                style: typography.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900)),
              Text('${rows.length} loaded records · authorised scope only',
                style: typography.bodySmall),
            ],
          )),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 7, runSpacing: 7, children: [
          for (final f in V8DailyOrderStages.filters)
            FilterChip(
              key: ValueKey('v8-daily-filter-${f.$1}'),
              label: Text('${f.$2}  ${V8DailyOrderStages.count(rows, f.$1)}'),
              selected: selectedStage == f.$1,
              showCheckmark: false,
              onSelected: (_) => onStageChanged(f.$1),
              visualDensity: VisualDensity.compact),
        ]),
        const SizedBox(height: 7),
        Text('Counts describe this loaded list, not ledger balances.',
          style: typography.bodySmall),
      ]),
    );
  }
}

class V8DailyOrderCard extends StatelessWidget {
  const V8DailyOrderCard({
    super.key, required this.id, required this.employee,
    required this.branch, required this.businessDate,
    required this.statusBadge, required this.action, required this.onOpen,
  });
  final int id;
  final String employee;
  final String branch;
  final String businessDate;
  final Widget statusBadge;
  final Widget action;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('v8-daily-order-$id'),
    child: InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 40, height: 40,
                decoration: BoxDecoration(color: ExcelBrand.primarySoft,
                  borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.receipt_long_outlined,
                  color: ExcelBrand.primaryDark)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ORDER #$id', style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w900)),
                  Text(employee, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                ],
              )),
              const Icon(Icons.chevron_right_rounded),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 5, children: [
              statusBadge,
              Text(businessDate, style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 5),
            Text(branch, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            const Divider(height: 15),
            Align(alignment: Alignment.centerLeft, child: action),
          ],
        ),
      ),
    ),
  );
}
