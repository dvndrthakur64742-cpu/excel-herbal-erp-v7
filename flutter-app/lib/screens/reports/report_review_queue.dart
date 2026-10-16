import 'package:flutter/material.dart';

typedef ReportReviewDecision = Future<void> Function(
  int id,
  String decision,
  String reason,
);

class ReportReviewQueue extends StatelessWidget {
  const ReportReviewQueue({
    super.key,
    required this.rows,
    required this.busy,
    required this.onDecision,
    required this.onView,
  });

  final List<Map<String, dynamic>> rows;
  final bool busy;
  final ReportReviewDecision onDecision;
  final Future<void> Function(Map<String, dynamic> review) onView;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No Accounts review requests yet. Submit a supported report snapshot first.'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _ReviewCard(
        row: rows[index],
        busy: busy,
        onDecision: onDecision,
        onView: onView,
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.row,
    required this.busy,
    required this.onDecision,
    required this.onView,
  });

  final Map<String, dynamic> row;
  final bool busy;
  final ReportReviewDecision onDecision;
  final Future<void> Function(Map<String, dynamic> review) onView;

  @override
  Widget build(BuildContext context) {
    final status = '${row['status'] ?? 'pending'}';
    final pending = status == 'pending';
    final reportType = _reportLabel('${row['report_type'] ?? ''}');
    final branch = row['branch_id'] == null
        ? 'All authorised branches'
        : 'Branch ${row['branch_id']}';
    final periodFrom = '${row['period_from'] ?? ''}';
    final periodTo = '${row['period_to'] ?? ''}';
    final asOf = '${row['as_of_date'] ?? ''}';
    final period = periodFrom.isNotEmpty
        ? '$periodFrom – $periodTo'
        : asOf.isNotEmpty
            ? 'As of $asOf'
            : 'Current position';
    final hash = '${row['snapshot_hash'] ?? ''}';
    final shortHash = hash.length > 12 ? hash.substring(0, 12) : hash;
    final summary = row['summary'] is Map
        ? Map<String, dynamic>.from(row['summary'] as Map)
        : <String, dynamic>{};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    reportType,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(status.toUpperCase())),
              ],
            ),
            Text('$branch · $period'),
            const SizedBox(height: 4),
            Text(
              'Requested by ${row['requester_name'] ?? 'Employee ${row['requested_by'] ?? ''}'} · ${row['requested_at'] ?? ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Rows ${row['row_count'] ?? 0} · Snapshot $shortHash',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (summary.isNotEmpty) ...[
              const Divider(height: 18),
              ...summary.entries
                  .where((entry) => entry.value is! List && entry.value is! Map)
                  .map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text('${_label(entry.key)}: ${entry.value}'),
                      )),
              if (summary['checks'] is List)
                ...((summary['checks'] as List).whereType<Map>().map((raw) {
                  final check = Map<String, dynamic>.from(raw);
                  return Text(
                    '${check['check_name'] ?? 'Check'}: ${check['status'] ?? ''} · difference ${check['difference'] ?? 0}',
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                })),
              if (summary['exceptions'] is List &&
                  (summary['exceptions'] as List).isNotEmpty)
                Text(
                  'Exceptions: ${(summary['exceptions'] as List).length} listed',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            if ('${row['decision_reason'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Review note: ${row['decision_reason']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (pending) ...[
              const SizedBox(height: 12),
              Text(
                row['can_decide'] == true
                    ? 'Your decision will be recorded with your identity and time. The requester cannot approve their own submission.'
                    : 'This request is visible to you, but only a different authorised reviewer can decide it.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : () => onView(row),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('View report'),
                ),
                if (pending && row['can_decide'] == true) ...[
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _askDecision(context, 'reject'),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Reject'),
                  ),
                  FilledButton.icon(
                    onPressed: busy ? null : () => _askDecision(context, 'approve'),
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Approve'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _askDecision(BuildContext context, String decision) async {
    final controller = TextEditingController();
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(decision == 'approve'
                ? 'Approve Accounts review'
                : 'Reject Accounts review'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Enter a review note (at least 5 characters).'),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Review note',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: controller.text.trim().length < 5
                    ? null
                    : () => Navigator.pop(dialogContext, controller.text.trim()),
                child: Text(decision == 'approve' ? 'Confirm approval' : 'Confirm rejection'),
              ),
            ],
          ),
        ),
      );
      if (reason == null) return;
      await onDecision((row['id'] as num).toInt(), decision, reason);
    } finally {
      controller.dispose();
    }
  }

  static String _reportLabel(String type) => switch (type) {
        'trial_balance' => 'Trial Balance',
        'profit_loss' => 'Profit & Loss',
        'balance_sheet' => 'Balance Sheet',
        'stock_reconciliation' => 'Stock Reconciliation',
        'finance_reconciliation' => 'Finance Reconciliation',
        _ => type.replaceAll('_', ' '),
      };

  static String _label(String key) => key
      .split('_')
      .map((word) => word.isEmpty
          ? word
          : '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
