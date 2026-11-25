import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_paths.dart';
import '../../core/date_time_text.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../widgets/async_panel.dart';

class AttendanceTimeReviewPanel extends ConsumerStatefulWidget {
  const AttendanceTimeReviewPanel({super.key, this.admin = false, this.branchId});
  final bool admin;
  final int? branchId;
  @override
  ConsumerState<AttendanceTimeReviewPanel> createState() => _AttendanceTimeReviewPanelState();
}

class _AttendanceTimeReviewPanelState extends ConsumerState<AttendanceTimeReviewPanel> {
  int revision = 0;
  bool busy = false;
  String? message;

  Future<void> _change(Map row, {String? decision}) async {
    if (busy) return;
    final id = int.tryParse('${row['id']}');
    if (id == null || id < 1) return;
    final branch = widget.branchId;
    final reason = TextEditingController();
    final start = TextEditingController();
    final end = TextEditingController();
    setState(() { busy = true; message = null; });
    try {
      final payload = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text(decision == null ? 'Request time correction' : 'Review time correction'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${row['business_date']}'),
            const Text('Original punch and GPS evidence stay unchanged. Approval is for the attendance report, not a salary adjustment.'),
            if (decision == null) ...[
              TextField(controller: start, decoration: const InputDecoration(labelText: 'Correct check-in (HH:MM, local time)')),
              TextField(controller: end, decoration: const InputDecoration(labelText: 'Correct checkout (HH:MM, local time)')),
            ] else ...[
              Text('Employee reason: ${row['reason']}'),
              Text('Proposed: ${DateTimeText.local(row['proposed_in_at'])} – ${DateTimeText.local(row['proposed_out_at'])}'),
            ],
            TextField(controller: reason, maxLength: 250, maxLines: 3,
                decoration: const InputDecoration(labelText: 'Reason (minimum 10 characters)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, <String, dynamic>{
              if (decision == null) ...{
                'attendance_id': id, 'check_in_local': start.text.trim(), 'check_out_local': end.text.trim(),
              } else ...{'id': id, 'decision': decision},
              'reason': reason.text.trim(),
            }), child: Text(decision == null ? 'Send request' : decision == 'approved' ? 'Approve' : 'Reject')),
          ],
        ),
      );
      if (payload == null || !mounted || branch != widget.branchId) return;
      if ((payload['reason'] as String).length < 10) {
        setState(() => message = 'Enter a reason of at least 10 characters.');
        return;
      }
      await ref.read(apiClientProvider).post(
        decision == null ? ApiPaths.timeReviewRequest : ApiPaths.timeReviewDecision, data: payload);
      if (mounted) setState(() { revision++; message = 'Saved successfully.'; });
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    } finally {
      reason.dispose(); start.dispose(); end.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branch = widget.branchId;
    if (widget.admin && branch == null) return const Center(child: Text('Select an authorised branch.'));
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text(widget.admin ? 'Pending historical corrections' : 'Recent attendance · request a correction if required')),
        IconButton(tooltip: 'Refresh corrections', onPressed: busy ? null : () => setState(() => revision++), icon: const Icon(Icons.refresh)),
      ])),
      if (message != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(message!)),
      Expanded(child: AsyncPanel(
        key: ValueKey('time-review-${widget.admin}-$branch-$revision'),
        loader: () => widget.admin
          ? ref.read(apiClientProvider).get(ApiPaths.timeReviewInbox, query: {'branch_id': branch})
          : ref.read(apiClientProvider).get(ApiPaths.timeReviewMine),
        emptyMessage: 'No attendance records or pending corrections.',
        builder: (context, data) {
          final rows = ((data as List?) ?? const []).whereType<Map>().toList();
          return ListView.builder(
            padding: const EdgeInsets.all(12), itemCount: rows.length,
            itemBuilder: (context, index) {
              final r = rows[index];
              final originalIn = widget.admin ? r['original_in_at'] : r['check_in_at'];
              final originalOut = widget.admin ? r['original_out_at'] : r['check_out_at'];
              return Card(child: Padding(padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${widget.admin ? '${r['full_name']} · ' : ''}${r['business_date']}', style: Theme.of(context).textTheme.titleMedium),
                  Text('Original: ${DateTimeText.local(originalIn)} – ${DateTimeText.local(originalOut)}'),
                  if (r['proposed_in_at'] != null) Text('Proposed: ${DateTimeText.local(r['proposed_in_at'])} – ${DateTimeText.local(r['proposed_out_at'])}'),
                  if (r['review_status'] != null) Text('Review: ${r['review_status']}'),
                  if (r['reason'] != null) Text('${r['reason']}'),
                  if (r['review_reason'] != null) Text('Decision reason: ${r['review_reason']}'),
                  if (!widget.admin && r['can_request'] == true)
                    TextButton(onPressed: busy ? null : () => _change(r), child: const Text('Request correction')),
                  if (widget.admin && r['can_decide'] == true)
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      FilledButton(onPressed: busy ? null : () => _change(r, decision: 'approved'), child: const Text('Approve')),
                      OutlinedButton(onPressed: busy ? null : () => _change(r, decision: 'rejected'), child: const Text('Reject')),
                    ]),
                ]),
              ));
            },
          );
        },
      )),
    ]);
  }
}
