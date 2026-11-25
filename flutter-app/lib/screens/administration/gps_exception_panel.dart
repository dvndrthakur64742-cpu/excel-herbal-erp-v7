import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../widgets/async_panel.dart';

class GpsExceptionPanel extends ConsumerStatefulWidget {
  const GpsExceptionPanel({super.key, required this.branchId});
  final int? branchId;

  @override
  ConsumerState<GpsExceptionPanel> createState() => _GpsExceptionPanelState();
}

class _GpsExceptionPanelState extends ConsumerState<GpsExceptionPanel> {
  int _revision = 0;
  bool _busy = false;
  String? _message;

  Future<void> _decide(Map row, String decision) async {
    if (_busy) return;
    final id = int.tryParse('${row['id']}');
    if (id == null || id < 1) return;
    final branch = widget.branchId;
    setState(() { _busy = true; _message = null; });
    final controller = TextEditingController();
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(decision == 'approved' ? 'Approve GPS exception?' : 'Reject GPS exception?'),
          scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${row['full_name']} · ${row['business_date']}'),
            Text('Employee reason: ${row['reason']}'),
            const Text('Approval authorizes only one employee-owned punch for the selected scope and date. It does not verify GPS or permit stock issue.'),
            TextField(controller: controller, maxLines: 3, maxLength: 250,
              decoration: const InputDecoration(labelText: 'Review reason (minimum 10 characters)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(decision == 'approved' ? 'Approve' : 'Reject')),
          ],
        ),
      );
      if (!mounted || reason == null || branch != widget.branchId) return;
      if (reason.length < 10) {
        setState(() => _message = 'Enter a review reason of at least 10 characters.');
        return;
      }
      await ref.read(apiClientProvider).post(ApiPaths.gpsExceptionDecision,
        data: {'id': id, 'decision': decision, 'reason': reason});
      if (mounted) setState(() { _revision++; _message = 'Decision recorded.'; });
    } catch (e) {
      if (mounted) setState(() => _message = UiError.message(e));
    } finally {
      controller.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branch = widget.branchId;
    if (branch == null) return const Center(child: Text('Select an authorised branch.'));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Expanded(child: Text('Pending GPS exceptions. Review the reason before deciding.')),
          IconButton(tooltip: 'Refresh requests', onPressed: _busy ? null : () => setState(() => _revision++),
            icon: const Icon(Icons.refresh)),
        ]),
      ),
      if (_message != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(_message!)),
      Expanded(child: AsyncPanel(
        key: ValueKey('gps-inbox-$branch-$_revision'),
        loader: () => ref.read(apiClientProvider).get(ApiPaths.gpsExceptionInbox, query: {'branch_id': branch}),
        emptyMessage: 'No pending GPS exceptions in this branch.',
        builder: (context, data) {
          final rows = ((data as List?) ?? const []).whereType<Map>().toList();
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final r = rows[index];
              return Card(child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['full_name']}', style: Theme.of(context).textTheme.titleMedium),
                  Text('${r['business_date']} · ${r['scope'] == 'check_in' ? 'Check-in' : 'Checkout'}'),
                  Text('${r['reason']}'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    if (r['can_approve'] == true) FilledButton(onPressed: _busy ? null : () => _decide(r, 'approved'), child: const Text('Approve')),
                    if (r['can_reject'] == true) OutlinedButton(onPressed: _busy ? null : () => _decide(r, 'rejected'), child: const Text('Reject')),
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
