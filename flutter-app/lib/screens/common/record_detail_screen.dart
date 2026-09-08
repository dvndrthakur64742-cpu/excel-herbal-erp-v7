import 'package:flutter/material.dart';
import '../../core/business_format.dart';

class RecordDetailScreen extends StatelessWidget {
  const RecordDetailScreen({
    super.key,
    required this.row,
    required this.title,
    this.recordType,
  });

  final Map<String, dynamic> row;
  final String title;
  final String? recordType;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_pageTitle())),
        body: BusinessRecordDetailView(
            row: row, title: title, recordType: recordType),
      );

  String _pageTitle() {
    final ref = _reference(row);
    if (ref != null) return ref;
    if (recordType != null && recordType!.trim().isNotEmpty) {
      return '${BusinessFormat.displayName(recordType!.replaceAll('_', ' '))} Details';
    }
    return 'Record Details';
  }
}

class BusinessRecordDetailView extends StatelessWidget {
  const BusinessRecordDetailView({
    super.key,
    required this.row,
    required this.title,
    this.recordType,
  });

  final Map<String, dynamic> row;
  final String title;
  final String? recordType;

  @override
  Widget build(BuildContext context) {
    final status = row['status'];
    final reference = _reference(row);
    final fields = row.entries
        .where((e) =>
            e.key != 'status' &&
            !BusinessFormat.isTechnicalKey(e.key) &&
            !_skipValue(e.value) &&
            e.value is! List &&
            e.value is! Map)
        .toList();
    final lists = row.entries
        .where((e) => e.value is List && (e.value as List).isNotEmpty)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        BusinessFormat.displayName(title),
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (status != null)
                      _StatusChip(label: BusinessFormat.status(status)),
                  ],
                ),
                if (reference != null) ...[
                  const SizedBox(height: 6),
                  Text(reference,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('Details',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                _DetailRow(field: fields[i]),
                if (i != fields.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
        for (final listEntry in lists) ...[
          const SizedBox(height: 18),
          Text(BusinessFormat.label(listEntry.key),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ..._nestedCards(context, listEntry.value as List),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  List<Widget> _nestedCards(BuildContext context, List values) {
    return values.map((value) {
      if (value is! Map)
        return Card(
            child: Padding(
                padding: const EdgeInsets.all(14), child: Text('$value')));
      final map = Map<String, dynamic>.from(value);
      final heading = _title(map);
      final fields = map.entries
          .where((e) =>
              !BusinessFormat.isTechnicalKey(e.key) &&
              !_skipValue(e.value) &&
              e.value is! Map &&
              e.value is! List)
          .take(8)
          .toList();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (heading.isNotEmpty) ...[
                  Text(BusinessFormat.displayName(heading),
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                ],
                for (final f in fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                            width: 128,
                            child: Text(BusinessFormat.label(f.key),
                                style: Theme.of(context).textTheme.bodySmall)),
                        Expanded(
                            child: Text(BusinessFormat.value(f.key, f.value),
                                textAlign: TextAlign.right)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  bool _skipValue(dynamic value) {
    if (value == null || '$value'.trim().isEmpty || '$value' == 'null')
      return true;
    return false;
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.field});
  final MapEntry<String, dynamic> field;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Text(
                BusinessFormat.label(field.key),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Text(
                BusinessFormat.value(field.key, field.value),
                textAlign: TextAlign.right,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      );
}

String _title(Map<String, dynamic> row) {
  const keys = [
    'product_name',
    'supplier_name',
    'customer_name',
    'employee_name',
    'full_name',
    'name',
    'title',
    'reference',
    'entry_no',
    'sale_no',
    'bill_no'
  ];
  for (final key in keys) {
    final value = row[key];
    if (value != null && '$value'.trim().isNotEmpty) return '$value';
  }
  return '';
}

String? _reference(Map<String, dynamic> row) {
  const keys = ['reference', 'entry_no', 'sale_no', 'bill_no'];
  for (final key in keys) {
    final value = row[key];
    if (value != null && '$value'.trim().isNotEmpty)
      return '${BusinessFormat.label(key)}: $value';
  }
  return null;
}
