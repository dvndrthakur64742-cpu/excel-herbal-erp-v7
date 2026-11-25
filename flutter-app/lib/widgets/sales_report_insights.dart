import 'package:flutter/material.dart';
import '../core/business_format.dart';
import '../core/sales_report_totals.dart';

/// One compact entry point for totals and daily record drill-down.
class SalesReportInsights extends StatelessWidget {
  const SalesReportInsights({super.key, required this.rows, required this.scope});
  final List<Map<String, dynamic>> rows;
  final String scope;

  @override
  Widget build(BuildContext context) {
    final totals = SalesReportTotals.read(rows);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: totals == null ? null : () => showDialog<void>(
          context: context,
          builder: (_) => _SalesBreakdown(totals: totals, scope: scope, count: rows.length),
        ),
        icon: const Icon(Icons.insights_outlined),
        label: Text(totals == null
          ? 'Sales analytics unavailable: verify report rows'
          : 'Sales totals & daily breakdown · ${rows.length} records'),
      ),
    );
  }
}

class _SalesBreakdown extends StatelessWidget {
  const _SalesBreakdown({required this.totals, required this.scope, required this.count});
  final SalesReportTotals totals;
  final String scope;
  final int count;
  String _money(int cents) => BusinessFormat.money(cents / 100);

  @override
  Widget build(BuildContext context) {
    final maxGross = totals.days.fold<int>(0, (max, day) =>
        day.grossMinor > max ? day.grossMinor : max);
    final canChart = maxGross > 0 && totals.days.every((d) => d.grossMinor >= 0);
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 680,
          maxHeight: MediaQuery.sizeOf(context).height * .80),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(children: [
              Expanded(child: Text('Sales insights', style: theme.textTheme.titleLarge)),
              IconButton(onPressed: () => Navigator.pop(context), tooltip: 'Close',
                icon: const Icon(Icons.close)),
            ])),
          const Divider(height: 1),
          Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(scope, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Text('$count returned records · all returned statuses'),
            Text('Gross is not net revenue; recorded paid is not bank collections.',
              style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 8, children: [
              _Total(label: 'Reported gross', value: _money(totals.grossMinor)),
              _Total(label: 'Recorded paid', value: _money(totals.paidMinor)),
              _Total(label: 'Recorded outstanding', value: _money(totals.outstandingMinor)),
            ]),
            const SizedBox(height: 16),
            Text('Gross by business date', style: theme.textTheme.titleMedium),
            const Text('Expand a date to see its exact returned sales records.'),
            if (!canChart && totals.days.isNotEmpty)
              const Text('Chart unavailable for zero or signed gross totals. Values remain listed.'),
            for (final day in totals.days)
              ExpansionTile(
                title: Text(BusinessFormat.date(day.date)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_money(day.grossMinor)} · ${day.rows.length} records'),
                  if (canChart) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: day.grossMinor / maxGross,
                      semanticsLabel: 'Reported gross relative to highest day'),
                  ],
                ]),
                children: [
                  for (final row in day.rows)
                    ListTile(
                      title: Text('${row['reference'] ?? 'Record'}'),
                      subtitle: Text('Status: ${BusinessFormat.status(row['status'])} · '
                        'Gross: ${BusinessFormat.money(row['gross_amount'])} · '
                        'Paid: ${BusinessFormat.money(row['paid_amount'])} · '
                        'Outstanding: ${BusinessFormat.money(row['outstanding_amount'])}'),
                    ),
                ],
              ),
          ])),
        ]),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(width: 160, child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  ));
}
