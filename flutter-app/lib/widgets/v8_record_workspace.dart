import 'package:flutter/material.dart';

import '../theme/excel_brand.dart';
import 'records_list.dart';

/// A presentation-only V8 record workspace. "Loaded" is deliberate:
/// neither paginated profile registers nor branch records claim global totals.
class V8RecordWorkspace extends StatelessWidget {
  const V8RecordWorkspace({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rows,
    this.recordType,
    this.onTap,
    this.contextLabel,
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> rows;
  final String? recordType;
  final String? contextLabel;
  final void Function(Map<String, dynamic>)? onTap;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        key: const ValueKey('v8-record-workspace'),
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 2),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
        decoration: BoxDecoration(
          color: ExcelBrand.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ExcelBrand.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 35, height: 35,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ExcelBrand.primarySoft,
                borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.dataset_outlined,
                color: ExcelBrand.primaryDark, size: 21)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: style.titleSmall?.copyWith(
                    color: ExcelBrand.ink, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(subtitle,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: style.bodySmall),
              ],
            )),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 7, runSpacing: 7, children: [
            _V8RecordChip(label: '${rows.length} records loaded',
              icon: Icons.table_rows_outlined),
            if (contextLabel != null && contextLabel!.trim().isNotEmpty)
              _V8RecordChip(label: contextLabel!,
                icon: Icons.shield_outlined),
          ]),
        ]),
      ),
      Expanded(
        child: RecordsList(
          rows: rows, recordType: recordType, onTap: onTap),
      ),
    ]);
  }
}

class _V8RecordChip extends StatelessWidget {
  const _V8RecordChip({required this.label, required this.icon});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: ExcelBrand.canvas,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: ExcelBrand.border)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: ExcelBrand.primaryDark),
      const SizedBox(width: 5),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800)),
    ]),
  );
}
