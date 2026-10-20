import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/api_paths.dart';

/// Internal reviewer worklist. No real delivery, no provider, no scheduler.
class ManagerNotificationCenterPanel extends StatefulWidget {
  const ManagerNotificationCenterPanel({
    super.key,
    required this.api,
    required this.branchId,
    required this.businessDate,
  });
  final ApiClient api;
  final int branchId;
  final String businessDate;
  @override
  State<ManagerNotificationCenterPanel> createState() => _ManagerNotificationCenterPanelState();
}

class _ManagerNotificationCenterPanelState extends State<ManagerNotificationCenterPanel> {
  late Future<dynamic> _data;
  bool busy = false;
  late String date;

  @override
  void initState() {
    super.initState();
    date = widget.businessDate;
    _data = _fetch();
  }

  @override
  void didUpdateWidget(covariant ManagerNotificationCenterPanel previous) {
    super.didUpdateWidget(previous);
    if (widget.branchId != previous.branchId || widget.businessDate != previous.businessDate) {
      date = widget.businessDate;
      _refresh();
    }
  }

  Future<dynamic> _fetch() => widget.api.get(ApiPaths.reportReminderDrafts,
    query: {'branch_id': widget.branchId, 'date': date});

  void _refresh() {
    if (mounted) setState(() => _data = _fetch());
  }

  String _format(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _perform(Future<dynamic> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await action();
      if (!mounted) return;
      if (result is! Map ||
          result['dispatch_enabled'] != false ||
          (result['notifications_sent'] ?? 0) != 0) {
        throw const ApiException('draft_contract', 'Reminder did not return the draft-only contract.');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Internal draft worklist updated. No notification was sent.')),
      );
      _refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Draft action failed: $error')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _prepare() async {
    final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Prepare internal follow-up drafts?'),
      content: const Text(
        'This checks existing Daily Closing evidence and report deadlines. '
        'It creates deduplicated internal drafts only. No SMS, email, WhatsApp or push is sent.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Prepare drafts')),
      ],
    ));
    if (!mounted || approved != true) return;
    await _perform(() => widget.api.post('${ApiPaths.reportReminderDrafts}/prepare',
      data: {'branch_id': widget.branchId, 'date': date}));
  }

  Future<void> _dismiss(int id) async {
    final controller = TextEditingController();
    try {
      final reason = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Dismiss stale internal draft'),
        content: TextField(
          controller: controller,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Audit reason (at least 12 characters)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Dismiss draft')),
        ],
      ));
      if (!mounted || reason == null) return;
      if (reason.length < 12) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter an audit reason of at least 12 characters.')),
        );
        return;
      }
      await _perform(() => widget.api.post('${ApiPaths.reportReminderDrafts}/$id/dismiss',
        data: {'branch_id': widget.branchId, 'reason': reason}));
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateValue = DateTime.tryParse(date) ?? DateTime.now();
    final maxDate = DateTime.tryParse(widget.businessDate) ?? DateTime.now();
    return Column(children: [
      const Card(child: Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Internal Manager Notification Center. Drafts are not queued, delivered or scheduled. '
          'Reviewer permission is required. Reports remain human attestations; '
          'no Cash/UPI bank, payroll or physical stock verification is implied.',
        ),
      )),
      Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.event_outlined),
          label: Text('Business date: $date'),
          onPressed: busy ? null : () async {
            final next = await showDatePicker(
              context: context, initialDate: dateValue,
              firstDate: maxDate.subtract(const Duration(days: 31)),
              lastDate: maxDate,
            );
            if (next != null && mounted) {
              date = _format(next);
              _refresh();
            }
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('Refresh drafts'),
          onPressed: busy ? null : _refresh,
        ),
        FilledButton.icon(
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('Prepare internal drafts'),
          onPressed: busy ? null : _prepare,
        ),
      ]),
      Expanded(child: FutureBuilder<dynamic>(
        future: _data,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Cannot load authorized internal drafts: ${snap.error}'),
              TextButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ));
          final data = snap.data;
          if (data is! Map ||
              data['read_only'] != true ||
              data['branch_id'] != widget.branchId ||
              data['business_date'] != date ||
              data['dispatch_enabled'] != false ||
              data['evidence'] != 'internal_followup_draft_only_no_delivery' ||
              data['drafts'] is! List) {
            return const Center(child: Text('Internal draft authority/evidence contract mismatch.'));
          }
          final rows = (data['drafts'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          if (rows.length > 2000 || rows.any((row) =>
              row['branch_id'].toString() != widget.branchId.toString() ||
              row['state'] != 'draft' ||
              row['period_date'] != date)) {
            return const Center(child: Text('Untrusted or incomplete draft response.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
            children: [
              Text('Open internal drafts: ${rows.length}',
                style: Theme.of(context).textTheme.titleMedium),
              if (rows.isEmpty)
                const ListTile(title: Text('No open internal follow-up drafts for this date.')),
              for (final row in rows)
                Card(child: ListTile(
                  leading: const Icon(Icons.drafts_outlined),
                  title: Text('${row['report_type']} · ${row['reason']}'),
                  subtitle: Text('Employee ID ${row['target_employee_id']} · '
                      'Created ${row['created_at']}\n'
                      'Draft only — never sent to an employee'),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.archive_outlined),
                    tooltip: 'Dismiss internal draft with audit reason',
                    onPressed: busy ? null : () => _dismiss(int.parse(row['id'].toString())),
                  ),
                )),
            ],
          );
        },
      )),
    ]);
  }
}
