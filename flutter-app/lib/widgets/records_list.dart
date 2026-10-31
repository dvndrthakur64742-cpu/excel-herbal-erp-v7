import 'package:flutter/material.dart';

import '../core/business_format.dart';
import '../screens/common/record_detail_screen.dart';
import '../shell/shell_layout.dart';

class RecordsList extends StatefulWidget {
  const RecordsList({
    super.key,
    required this.rows,
    this.titleKeys = const [
      'check_name',
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
  final _search = TextEditingController();
  final _verticalScroll = ScrollController();
  final _horizontalScroll = ScrollController();
  String? _status;
  String? _sortKey;
  bool _ascending = true;
  int _page = 0;
  static const _pageSize = 25;

  @override
  void dispose() {
    _search.dispose();
    _verticalScroll.dispose();
    _horizontalScroll.dispose();
    super.dispose();
  }

  void _resetPage() {
    _page = 0;
    if (_verticalScroll.hasClients) _verticalScroll.jumpTo(0);
  }

  List<Map<String, dynamic>> _visibleRows() {
    final query = _search.text.trim().toLowerCase();
    final rows = widget.rows.where((row) {
      if (_status != null && '${row['status']}' != _status) return false;
      return query.isEmpty || row.entries.any((entry) =>
          !BusinessFormat.isTechnicalKey(entry.key) &&
          entry.value != null &&
          entry.value is! Map &&
          entry.value is! List &&
          BusinessFormat.value(entry.key, entry.value)
              .toLowerCase().contains(query));
    }).toList();
    final key = _sortKey;
    if (key != null) {
      // Keep equal values in server order and never sort the caller's list.
      final indexed = rows.asMap().entries.toList();
      indexed.sort((a, b) {
        final left = a.value[key];
        final right = b.value[key];
        final ln = _isNumericKey(key) ? BusinessFormat.number(left) : null;
        final rn = _isNumericKey(key) ? BusinessFormat.number(right) : null;
        final result = ln != null && rn != null
            ? ln.compareTo(rn)
            : '${left ?? ''}'.toLowerCase()
                .compareTo('${right ?? ''}'.toLowerCase());
        return result == 0 ? a.key.compareTo(b.key)
            : (_ascending ? result : -result);
      });
      return indexed.map((entry) => entry.value).toList();
    }
    return rows;
  }

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
    final rows = _visibleRows();
    final lastPage = rows.isEmpty ? 0 : (rows.length - 1) ~/ _pageSize;
    final page = _page > lastPage ? lastPage : _page;
    final pageRows = rows.skip(page * _pageSize).take(_pageSize).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(context, constraints.maxWidth),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text(widget.rows.isEmpty
                      ? 'No records available.'
                      : 'No matching records. Clear search or filters.'))
                  : ShellLayout.isDesktopWidth(constraints.maxWidth)
                      ? _desktopTable(context, pageRows, constraints.maxWidth)
                      : _mobileCards(context, pageRows),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: Text(
                    rows.isEmpty ? '0 records'
                        : '${page * _pageSize + 1}–${page * _pageSize + pageRows.length} of ${rows.length} records',
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: page == 0 ? null : () => setState(() {
                      _page = page - 1;
                      if (_verticalScroll.hasClients) _verticalScroll.jumpTo(0);
                    }),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: page >= lastPage ? null : () => setState(() {
                      _page = page + 1;
                      if (_verticalScroll.hasClients) _verticalScroll.jumpTo(0);
                    }),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _toolbar(BuildContext context, double width) {
    final statuses = widget.rows.map((row) => '${row['status'] ?? ''}')
        .where((value) => value.isNotEmpty).toSet().toList()..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: width < 520 ? (width - 32).clamp(0.0, 360.0).toDouble() : 320,
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search records…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty ? null : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _search.clear();
                    _resetPage();
                  }),
                ),
              ),
              onChanged: (_) => setState(_resetPage),
            ),
          ),
          if (statuses.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Filter by status',
              onSelected: (value) => setState(() {
                _status = value.isEmpty ? null : value;
                _resetPage();
              }),
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: '', checked: _status == null,
                  child: const Text('All statuses'),
                ),
                for (final status in statuses)
                  CheckedPopupMenuItem(
                    value: status, checked: _status == status,
                    child: Text(BusinessFormat.status(status)),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_list_rounded, size: 18),
                  const SizedBox(width: 6),
                  Text(_status == null ? 'All statuses' : BusinessFormat.status(_status)),
                  const SizedBox(width: 3),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Sort records',
            icon: const Icon(Icons.sort),
            onSelected: (key) => setState(() {
              _ascending = _sortKey == key ? !_ascending : true;
              _sortKey = key;
              _resetPage();
            }),
            itemBuilder: (_) => [
              for (final key in _desktopKeys())
                CheckedPopupMenuItem(
                  value: key, checked: key == _sortKey,
                  child: Text(BusinessFormat.label(key)),
                ),
            ],
          ),
          if (_sortKey != null)
            Text('${BusinessFormat.label(_sortKey!)} ${_ascending ? '↑' : '↓'}',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _desktopTable(BuildContext context,
      List<Map<String, dynamic>> rows, double width) {
    final keys = _desktopKeys();

    return Scrollbar(
      controller: _verticalScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _verticalScroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Scrollbar(
          controller: _horizontalScroll,
          thumbVisibility: true,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontalScroll,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: width - 32),
              child: DataTable(
                showCheckboxColumn: false,
                sortColumnIndex: keys.contains(_sortKey) ? keys.indexOf(_sortKey!) : null,
                sortAscending: _ascending,
                headingRowHeight: 44,
                dataRowMinHeight: 46,
                dataRowMaxHeight: 58,
                horizontalMargin: 14,
                columnSpacing: 20,
                showBottomBorder: true,
                columns: [
                  for (final key in keys)
                    DataColumn(
                      numeric: _isNumericKey(key),
                      onSort: (_, ascending) => setState(() {
                        _sortKey = key;
                        _ascending = ascending;
                        _resetPage();
                      }),
                      label: Text(
                        BusinessFormat.label(key),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  DataColumn(
                    label: Text(widget.onTap == null ? 'View' : 'Actions'),
                  ),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      onSelectChanged: (_) => _openDetail(row),
                      cells: [
                        for (final key in keys)
                          DataCell(
                            _desktopCell(
                              context,
                              key,
                              row[key],
                              primary: key == keys.first,
                            ),
                          ),
                        DataCell(
                          Tooltip(
                            message: widget.onTap == null
                                ? 'View details'
                                : 'Open actions',
                            child: TextButton.icon(
                              onPressed: () => widget.onTap == null
                                  ? _openDetail(row)
                                  : _handleAction(row),
                              icon: Icon(
                                widget.onTap == null
                                    ? Icons.visibility_outlined
                                    : Icons.more_horiz,
                                size: 17,
                              ),
                              label:
                                  Text(widget.onTap == null ? 'View' : 'Actions'),
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
      ),
    );
  }

  Widget _mobileCards(BuildContext context,
      List<Map<String, dynamic>> rows) => ListView.separated(
    controller: _verticalScroll,
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
    itemCount: rows.length,
    separatorBuilder: (_, __) => const SizedBox(height: 6),
    itemBuilder: (_, i) => _BusinessCard(
      row: rows[i],
      title: _title(rows[i], i),
      fields: _mobileFields(rows[i]),
      recordType: widget.recordType,
      onTap: () => _openDetail(rows[i]),
      onAction: widget.onTap == null
          ? null
          : () => _handleAction(rows[i]),
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
      if (ShellLayout.isDesktopWidth(MediaQuery.sizeOf(context).width)) {
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
                          tooltip: 'Close details',
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
          hidden.contains(entry.key)) {
        continue;
      }
      if (entry.value == null ||
          entry.value is Map ||
          entry.value is List ||
          '${entry.value}'.trim().isEmpty ||
          '${entry.value}' == 'null') {
        continue;
      }
      if ((entry.key == 'batch_no' || entry.key == 'custodian_name') &&
          '${entry.value}'.trim().isEmpty) {
        continue;
      }
      available[entry.key] = entry.value;
    }

    final typePriority = switch (widget.recordType) {
      'stock' => const [
        'quantity',
        'custodian_name',
        'sku',
        'uom',
        'batch_no',
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
      'trial_balance' => const ['code', 'name', 'debit', 'credit', 'balance'],
      'profit_loss' => const ['section', 'name', 'amount'],
      'balance_sheet' => const ['section', 'name', 'amount'],
      'receivables' => const [
        'business_date',
        'customer_name',
        'outstanding_amount',
        'age_days',
      ],
      'payables' => const [
        'business_date',
        'supplier_name',
        'outstanding_amount',
        'age_days',
      ],
      'stock_reconciliation' => const [
        'product_name',
        'batch_no',
        'custodian_name',
        'status',
        'balance_quantity',
        'ledger_quantity',
        'difference_quantity',
        'difference_value',
      ],
      'finance_reconciliation' => const [
        'check_name',
        'book_label',
        'book_value',
        'control_label',
        'control_value',
        'difference',
        'status',
      ],
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
      'candidate' => const [
        'candidate_code',
        'proposed_designation_code',
        'mobile',
        'expected_joining_date',
        'status',
      ],
      'separation' => const [
        'employee_code',
        'designation_code',
        'separation_date',
        'reason',
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
    final limit = widget.recordType == 'stock' ? 4 : 3;
    return ordered.take(limit).toList();
  }

  List<String> _desktopKeys() {
    final available = <String>{};
    for (final row in widget.rows) {
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
    final typeKeys = switch (widget.recordType) {
      'customer' => const [
        'name',
        'mobile',
        'email',
        'outstanding_amount',
        'status',
        'address',
      ],
      'supplier' => const [
        'name',
        'mobile',
        'gstin',
        'outstanding_amount',
        'status',
        'address',
      ],
      'stock' => const [
        'product_name',
        'sku',
        'quantity',
        'uom',
        'custodian_name',
        'batch_no',
        'average_unit_cost',
      ],
      'finance' => const [
        'name',
        'entry_no',
        'entry_date',
        'debit',
        'credit',
        'balance',
        'type',
      ],
      'purchase' => const [
        'supplier_name',
        'bill_no',
        'bill_date',
        'total_amount',
        'outstanding_amount',
        'status',
      ],
      'sales' => const [
        'customer_name',
        'sale_no',
        'business_date',
        'gross_amount',
        'outstanding_amount',
        'status',
      ],
      'employee' => const [
        'employee_name',
        'employee_code',
        'designation_code',
        'mobile',
        'status',
      ],
      'product' => const [
        'product_name',
        'sku',
        'mrp',
        'sale_price',
        'status',
      ],
      'daily_order' => const [
        'business_date',
        'employee_name',
        'branch_name',
        'status',
      ],
      'attendance' => const [
        'business_date',
        'employee_name',
        'check_in_at',
        'check_out_at',
        'status',
      ],
      'task' => const [
        'title',
        'type',
        'due_at',
        'priority',
        'status',
      ],
      'candidate' => const [
        'full_name',
        'candidate_code',
        'proposed_designation_code',
        'expected_joining_date',
        'status',
      ],
      'payroll' => const [
        'employee_name',
        'period_start',
        'period_end',
        'gross_total',
        'net_total',
        'status',
      ],
      'target' => const [
        'employee_name',
        'target_points',
        'from_date',
        'to_date',
        'status',
      ],
      'audit' => const [
        'event_type',
        'entity_type',
        'action',
        'created_at',
      ],
      _ => const <String>[],
    };
    for (final key in [...typeKeys, ..._priorityKeys]) {
      if (available.remove(key)) ordered.add(key);
    }
    final rest = available.toList()..sort();
    ordered.addAll(rest);

    if (ordered.isEmpty) return const ['status'];
    // ERP list views should answer the first decision at a glance. Extra
    // attributes belong in the record detail view, not in the scanning table.
    return ordered.take(5).toList();
  }

  bool _isNumericKey(String key) {
    final k = key.toLowerCase();
    return k == 'quantity' ||
        k.endsWith('_qty') ||
        k.endsWith('_amount') ||
        k.contains('price') ||
        k.contains('cost') ||
        k.endsWith('_total') ||
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

  Widget _desktopCell(
    BuildContext context,
    String key,
    dynamic rawValue, {
    required bool primary,
  }) {
    final value = BusinessFormat.value(key, rawValue);
    final child = key == 'status'
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              BusinessFormat.status(rawValue),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          )
        : Text(
            value,
            textAlign: _isNumericKey(key) ? TextAlign.right : TextAlign.left,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: primary
                ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    )
                : null,
          );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _cellWidth(key)),
      child: Tooltip(message: value, child: child),
    );
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
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 9, 7, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (visual != null) ...[
                Container(
                  key: ValueKey('${recordType ?? 'record'}-leading-icon'),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: visual.tint(scheme),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(visual.icon, size: 17, color: scheme.primary),
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                          ),
                        ),
                        if (status != null) ...[
                          const SizedBox(width: 6),
                          _StatusPill(BusinessFormat.status(status)),
                        ],
                      ],
                    ),
                    if (reference != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        reference,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (fields.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 10,
                        runSpacing: 3,
                        children: [
                          for (final field in fields) _FieldValue(field: field),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              onAction == null
                  ? Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    )
                  : SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: 'Actions',
                        onPressed: onAction,
                        icon: const Icon(Icons.more_vert_rounded, size: 20),
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
      if (value != null && '$value'.trim().isNotEmpty) {
        return '${BusinessFormat.label(key)}: $value';
      }
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

  Color tint(ColorScheme scheme) => scheme.primary.withValues(alpha: alpha);
}

class _FieldValue extends StatelessWidget {
  const _FieldValue({required this.field});
  final MapEntry<String, dynamic> field;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${BusinessFormat.label(field.key)}: ',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: BusinessFormat.value(field.key, field.value),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}
