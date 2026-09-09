import 'package:flutter/material.dart';

import '../core/business_format.dart';
import '../screens/common/record_detail_screen.dart';

class RecordsList extends StatefulWidget {
  const RecordsList({
    super.key,
    required this.rows,
    this.titleKeys = const [
      'name',
      'full_name',
      'employee_name',
      'product_name',
      'supplier_name',
      'customer_name',
      'reference',
      'entry_no',
      'sale_no',
      'bill_no',
      'title',
    ],
    this.onTap,
    this.recordType,
  });

  final List<Map<String, dynamic>> rows;
  final List<String> titleKeys;
  final void Function(Map<String, dynamic>)? onTap;
  final String? recordType;

  @override
  State<RecordsList> createState() => _RecordsListState();
}

class _RecordsListState extends State<RecordsList> {
  bool _opening = false;

  static const _priorityKeys = [
    'employee_name',
    'employee_code',
    'full_name',
    'name',
    'product_name',
    'supplier_name',
    'customer_name',
    'reference',
    'entry_no',
    'sale_no',
    'bill_no',
    'business_date',
    'bill_date',
    'sale_date',
    'entry_date',
    'status',
    'quantity',
    'gross_amount',
    'total_amount',
    'paid_amount',
    'outstanding_amount',
    'amount',
    'balance',
    'debit',
    'credit',
    'points',
    'created_at',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 820) return _desktopTable(context);
        return _mobileCards(context);
      },
    );
  }

  Widget _desktopTable(BuildContext context) {
    final keys = _desktopKeys();
    if (widget.rows.isEmpty) return const SizedBox.shrink();

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 46,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 64,
              horizontalMargin: 18,
              columnSpacing: 28,
              showBottomBorder: true,
              columns: [
                for (final key in keys)
                  DataColumn(
                    numeric: _isNumericKey(key),
                    label: Text(
                      BusinessFormat.label(key),
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                const DataColumn(label: Text('Action')),
              ],
              rows: [
                for (final row in widget.rows)
                  DataRow(
                    onSelectChanged: (_) => _openDetail(row),
                    cells: [
                      for (final key in keys)
                        DataCell(
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: _cellWidth(key),
                            ),
                            child: Text(
                              BusinessFormat.value(key, row[key]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      DataCell(
                        IconButton(
                          tooltip: widget.onTap == null
                              ? 'View details'
                              : 'Open actions',
                          onPressed: () => widget.onTap == null
                              ? _openDetail(row)
                              : _handleAction(row),
                          icon: Icon(
                            widget.onTap == null
                                ? Icons.arrow_forward_ios
                                : Icons.more_horiz,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mobileCards(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
    itemCount: widget.rows.length,
    separatorBuilder: (_, __) => const SizedBox(height: 10),
    itemBuilder: (_, i) => _BusinessCard(
      row: widget.rows[i],
      title: _title(widget.rows[i], i),
      fields: _mobileFields(widget.rows[i]),
      recordType: widget.recordType,
      onTap: () => _openDetail(widget.rows[i]),
      onAction: widget.onTap == null
          ? null
          : () => _handleAction(widget.rows[i]),
    ),
  );

  Future<void> _handleAction(Map<String, dynamic> row) async {
    if (_opening || !mounted || widget.onTap == null) return;
    _opening = true;
    try {
      widget.onTap!(row);
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      _opening = false;
    }
  }

  Future<void> _openDetail(Map<String, dynamic> row) async {
    if (_opening || !mounted) return;
    _opening = true;
    try {
      final title = _title(row, 0);
      if (usesEntityWorkspace(widget.recordType)) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RecordDetailScreen(
              row: row,
              title: title,
              recordType: widget.recordType,
            ),
          ),
        );
        return;
      }
      if (MediaQuery.sizeOf(context).width >= 820) {
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: SizedBox(
              width: 720,
              height: MediaQuery.sizeOf(context).height * .82,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Record Details',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: BusinessRecordDetailView(
                      row: row,
                      title: title,
                      recordType: widget.recordType,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RecordDetailScreen(
              row: row,
              title: title,
              recordType: widget.recordType,
            ),
          ),
        );
      }
    } finally {
      _opening = false;
    }
  }

  String _title(Map<String, dynamic> row, int index) {
    for (final key in widget.titleKeys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty) {
        return key.contains('name')
            ? BusinessFormat.displayName('$value')
            : BusinessFormat.value(key, value);
      }
    }
    final ref =
        row['reference'] ?? row['entry_no'] ?? row['bill_no'] ?? row['sale_no'];
    if (ref != null && '$ref'.trim().isNotEmpty) return '$ref';
    return widget.recordType == null
        ? 'Record ${index + 1}'
        : '${BusinessFormat.displayName(widget.recordType!.replaceAll('_', ' '))} ${index + 1}';
  }

  List<MapEntry<String, dynamic>> _mobileFields(Map<String, dynamic> row) {
    final hidden = <String>{
      ...widget.titleKeys,
      'status',
      'reference',
      'entry_no',
      'sale_no',
      'bill_no',
    };
    final available = <String, dynamic>{};
    for (final entry in row.entries) {
      if (BusinessFormat.isTechnicalKey(entry.key) ||
          hidden.contains(entry.key))
        continue;
      if (entry.value == null ||
          entry.value is Map ||
          entry.value is List ||
          '${entry.value}'.trim().isEmpty ||
          '${entry.value}' == 'null')
        continue;
      if ((entry.key == 'batch_no' || entry.key == 'custodian_name') &&
          '${entry.value}'.trim().isEmpty)
        continue;
      available[entry.key] = entry.value;
    }

    final typePriority = switch (widget.recordType) {
      'stock' => const [
        'quantity',
        'sku',
        'uom',
        'batch_no',
        'custodian_name',
        'expires_on',
      ],
      'purchase' => const [
        'bill_date',
        'total_amount',
        'paid_amount',
        'outstanding_amount',
      ],
      'sales' => const [
        'business_date',
        'gross_amount',
        'paid_amount',
        'outstanding_amount',
      ],
      'finance' => const ['entry_date', 'debit', 'credit', 'balance', 'memo'],
      'customer' => const ['mobile', 'email', 'outstanding_amount', 'status'],
      'supplier' => const ['mobile', 'gstin', 'outstanding_amount', 'status'],
      'task' => const ['type', 'due_at', 'priority', 'description'],
      'announcement' => const ['created_at', 'description', 'message'],
      'notification' => const ['created_at', 'type', 'message'],
      'attendance' => const [
        'business_date',
        'check_in_at',
        'check_out_at',
        'status',
      ],
      'employee' => const [
        'employee_code',
        'designation_code',
        'mobile',
        'status',
      ],
      'product' => const ['sku', 'mrp', 'sale_price', 'status'],
      'daily_order' => const [
        'business_date',
        'employee_name',
        'branch_name',
        'status',
      ],
      'performance' => const [
        'employee_name',
        'points',
        'salary_fund',
        'business_date',
      ],
      'target' => const [
        'employee_name',
        'target_points',
        'from_date',
        'to_date',
      ],
      'payroll' => const [
        'period_start',
        'period_end',
        'gross_total',
        'net_total',
        'status',
      ],
      'reversal' => const ['source_type', 'reason', 'created_at', 'status'],
      'audit' => const ['event_type', 'entity_type', 'created_at', 'action'],
      'branch_history' => const [
        'branch_name',
        'from_date',
        'to_date',
        'reason',
      ],
      'product_history' => const [
        'effective_from',
        'mrp',
        'sale_price',
        'status',
      ],
      _ => const <String>[],
    };

    final ordered = <MapEntry<String, dynamic>>[];
    for (final key in [...typePriority, ..._priorityKeys]) {
      if (available.containsKey(key)) {
        ordered.add(MapEntry(key, available.remove(key)));
      }
    }
    for (final entry in available.entries) {
      ordered.add(entry);
    }
    return ordered.take(4).toList();
  }

  List<String> _desktopKeys() {
    final available = <String>{};
    for (final row in widget.rows.take(30)) {
      for (final entry in row.entries) {
        if (entry.value == null ||
            entry.value is Map ||
            entry.value is List ||
            BusinessFormat.isTechnicalKey(entry.key)) {
          continue;
        }
        available.add(entry.key);
      }
    }

    final ordered = <String>[];
    for (final key in _priorityKeys) {
      if (available.remove(key)) ordered.add(key);
    }
    final rest = available.toList()..sort();
    ordered.addAll(rest);

    if (ordered.isEmpty) return const ['status'];
    return ordered.take(7).toList();
  }

  bool _isNumericKey(String key) {
    final k = key.toLowerCase();
    return k == 'quantity' ||
        k.endsWith('_qty') ||
        k.endsWith('_amount') ||
        const {
          'amount',
          'gross_amount',
          'paid_amount',
          'outstanding_amount',
          'debit',
          'credit',
          'balance',
          'points',
        }.contains(k);
  }

  double _cellWidth(String key) {
    if (key.contains('name') || key == 'title' || key == 'memo') return 240;
    if (key == 'status') return 160;
    if (key.endsWith('_at')) return 190;
    return 170;
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({
    required this.row,
    required this.title,
    required this.fields,
    required this.onTap,
    this.recordType,
    this.onAction,
  });

  final Map<String, dynamic> row;
  final String title;
  final List<MapEntry<String, dynamic>> fields;
  final String? recordType;
  final VoidCallback onTap;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final status = row['status'];
    final reference = _reference(row);
    final visual = _recordVisual(recordType, row);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (visual != null) ...[
                Container(
                  key: ValueKey('${recordType ?? 'record'}-leading-icon'),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: visual.tint(Theme.of(context).colorScheme),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    visual.icon,
                    size: 23,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.18,
                                ),
                          ),
                        ),
                        if (status != null) ...[
                          const SizedBox(width: 8),
                          _StatusPill(BusinessFormat.status(status)),
                        ],
                      ],
                    ),
                    if (reference != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        reference,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (fields.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 14,
                        runSpacing: 8,
                        children: [
                          for (final field in fields) _FieldValue(field: field),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: onAction == null
                    ? Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                        ),
                      )
                    : IconButton(
                        tooltip: 'Actions',
                        onPressed: onAction,
                        icon: const Icon(Icons.more_vert_rounded),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _reference(Map<String, dynamic> row) {
    for (final key in const ['reference', 'entry_no', 'sale_no', 'bill_no']) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty)
        return '${BusinessFormat.label(key)}: $value';
    }
    return null;
  }
}

_RecordVisual? _recordVisual(String? recordType, Map<String, dynamic> row) {
  final type = (recordType ?? '${row['type'] ?? ''}').toLowerCase();
  return switch (type) {
    'announcement' => const _RecordVisual(Icons.campaign_outlined, .14),
    'notification' => const _RecordVisual(
      Icons.notifications_none_rounded,
      .16,
    ),
    'task' => const _RecordVisual(Icons.task_alt_rounded, .12),
    'attendance' => const _RecordVisual(Icons.verified_user_outlined, .12),
    'sales' => const _RecordVisual(Icons.point_of_sale_outlined, .12),
    'purchase' => const _RecordVisual(Icons.shopping_bag_outlined, .12),
    'stock' => const _RecordVisual(Icons.inventory_2_outlined, .12),
    'finance' => const _RecordVisual(
      Icons.account_balance_wallet_outlined,
      .12,
    ),
    _ => null,
  };
}

class _RecordVisual {
  const _RecordVisual(this.icon, this.alpha);
  final IconData icon;
  final double alpha;

  Color tint(ColorScheme scheme) => scheme.primary.withOpacity(alpha);
}

class _FieldValue extends StatelessWidget {
  const _FieldValue({required this.field});
  final MapEntry<String, dynamic> field;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 92, maxWidth: 160),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          BusinessFormat.label(field.key),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          BusinessFormat.value(field.key, field.value),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}
