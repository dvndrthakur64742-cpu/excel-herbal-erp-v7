import 'package:flutter/material.dart';
import '../core/report_period.dart';
import 'async_panel.dart';
import 'records_list.dart';

/// Uses the existing scoped server search, rather than filtering the last 100
/// cycles. Counts describe the selected server query, not a company-wide total.
class TeamDailyQueue extends StatefulWidget {
  const TeamDailyQueue({super.key, required this.businessDate, required this.load, required this.onOpen});
  final String businessDate;
  final Future<dynamic> Function(String status, int page) load;
  final ValueChanged<Map<String,dynamic>> onOpen;

  @override
  State<TeamDailyQueue> createState() => _TeamDailyQueueState();
}

class _TeamDailyQueueState extends State<TeamDailyQueue> {
  String status = 'open';
  int page = 1;
  int revision = 0;
  static const options = {
    'open':'Open / unresolved',
    '':'All statuses',
    'morning_draft':'Morning draft',
    'stock_requested':'Stock request pending',
    'approved':'Approved',
    'awaiting_receipt':'Awaiting receipt',
    'issued':'Issued / closing not started',
    'evening_draft':'Evening draft',
    'evening_submitted':'Closing review',
    'completed':'Completed',
    'cancelled':'Cancelled',
    'rejected':'Rejected',
  };
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: 260, child: DropdownButtonFormField<String>(
          isExpanded: true, initialValue: status,
          decoration: const InputDecoration(labelText: 'Order stage', isDense: true),
          items: [for (final entry in options.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value, overflow: TextOverflow.ellipsis))],
          onChanged: (value) { if (value != null) setState(() { status = value; page = 1; }); },
        )),
        TextButton.icon(onPressed: () => setState(() { revision++; }),
          icon: const Icon(Icons.refresh), label: const Text('Refresh orders')),
      ])),
    Expanded(child: AsyncPanel(
      key: ValueKey((status,page,revision)),
      loader: () => widget.load(status,page),
      builder: (context, raw) {
        if (raw is! Map || raw['items'] is! List || raw['total'] is! int ||
            raw['page'] != page || raw['page_size'] != 25 || raw['has_more'] is! bool ||
            (raw['items'] as List).any((r) => r is! Map)) {
          return const Center(child: Text('Order queue unavailable. Refresh to retry.'));
        }
        final rows = (raw['items'] as List).map((r) => Map<String,dynamic>.from(r as Map)).toList();
        final today = ReportPeriod.businessDay(widget.businessDate);
        final past = rows.where((r) {
          final date = ReportPeriod.businessDay('${r['business_date'] ?? ''}');
          return today != null && date != null && date.isBefore(today) &&
            !const {'completed','cancelled','rejected'}.contains('${r['status']}');
        }).length;
        final total = raw['total'] as int;
        return Column(children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Wrap(
            spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('$total matching orders · page $page'),
              if (past > 0) Text('$past earlier-date unresolved orders on this page'),
              IconButton(tooltip: 'Previous order page', onPressed: page > 1 ? () => setState(() => page--) : null,
                icon: const Icon(Icons.chevron_left)),
              IconButton(tooltip: 'Next order page', onPressed: raw['has_more'] == true && page < 1000 ? () => setState(() => page++) : null,
                icon: const Icon(Icons.chevron_right)),
            ])),
          Expanded(child: rows.isEmpty
            ? const Center(child: Text('No orders on this page.'))
            : RecordsList(recordType: 'daily_order', rows: rows, onTap: widget.onOpen, serverPaged: true)),
        ]);
      },
    )),
  ]);
}
