import 'package:flutter/material.dart';
import '../core/business_format.dart';
import '../core/stock_report_insight.dart';

class StockReportInsights extends StatelessWidget {
  const StockReportInsights({super.key, required this.rows, required this.scope, required this.businessDate});
  final List<Map<String, dynamic>> rows;
  final String scope;
  final DateTime businessDate;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      icon: const Icon(Icons.inventory_2_outlined),
      label: const Text('Stock & expiry insights'),
      onPressed: () => showDialog<void>(context: context,
        builder: (_) => _StockBreakdown(rows: rows, scope: scope, businessDate: businessDate)),
    ),
  );
}

class _StockBreakdown extends StatefulWidget {
  const _StockBreakdown({required this.rows, required this.scope, required this.businessDate});
  final List<Map<String, dynamic>> rows;
  final String scope;
  final DateTime businessDate;
  @override
  State<_StockBreakdown> createState() => _StockBreakdownState();
}

class _StockBreakdownState extends State<_StockBreakdown> {
  int horizon = 30;
  static const labels = {
    StockInsightKind.negative: 'Negative stock',
    StockInsightKind.expired: 'Expired stock',
    StockInsightKind.expiresToday: 'Expires today',
    StockInsightKind.upcoming: 'Upcoming expiry',
    StockInsightKind.missingExpiry: 'Required expiry missing',
    StockInsightKind.unverified: 'Unverified data',
    StockInsightKind.current: 'Other stock rows',
  };

  @override
  Widget build(BuildContext context) {
    final data = widget.rows.map((r) => StockInsight.classify(r, widget.businessDate, horizon)).toList();
    return Dialog(child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 680, maxHeight: MediaQuery.sizeOf(context).height * .8),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 8), child: Row(children: [
          Expanded(child: Text('Stock & expiry insights', style: Theme.of(context).textTheme.titleLarge)),
          IconButton(onPressed: () => Navigator.pop(context), tooltip: 'Close', icon: const Icon(Icons.close)),
        ])),
        const Divider(height: 1),
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(widget.scope),
          Text('Business date: ${BusinessFormat.date(widget.businessDate.toIso8601String())}'),
          const Text('Counts are returned stock balance rows, not total units or distinct products. Zero-stock rows are excluded by the report.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: horizon,
            decoration: const InputDecoration(labelText: 'Upcoming expiry window'),
            items: const [
              DropdownMenuItem(value: 7, child: Text('Next 7 days')),
              DropdownMenuItem(value: 30, child: Text('Next 30 days')),
              DropdownMenuItem(value: 90, child: Text('Next 90 days')),
            ],
            onChanged: (value) { if (value != null) setState(() => horizon = value); },
          ),
          const SizedBox(height: 8),
          for (final entry in labels.entries)
            ExpansionTile(
              title: Text('${entry.value} · ${data.where((r) => r.kind == entry.key).length}'),
              children: [
                for (final item in data.where((r) => r.kind == entry.key))
                  ListTile(
                    title: Text('${item.row['product_name'] ?? 'Unknown product'} · ${item.row['sku'] ?? '—'}'),
                    subtitle: Text('Batch: ${item.row['batch_no'] ?? '—'} · '
                      'Quantity: ${item.row['quantity'] ?? '—'} ${item.row['uom'] ?? '(unit unavailable)'}\n'
                      'Custody: ${item.row['custodian_name'] ?? (('${item.row['custodian_key']}' == '0') ? 'Warehouse' : 'Unknown')} · '
                      'Expiry: ${item.row['expires_on'] ?? '—'}'),
                  ),
              ],
            ),
          const Text('Low-stock alerts require approved reorder levels; no threshold has been assumed.'),
        ])),
      ]),
    ));
  }
}
