part of 'my_work_screen.dart';

extension _MyWorkLeaveVisit on _MyWorkScreenState {
  Widget _leaveVisit() {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (app.can('workforce.leave.self')) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Leave',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              FilledButton.icon(
                onPressed: _applyLeave,
                icon: const Icon(Icons.add),
                label: const Text('Apply Leave'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AsyncPanel(
            key: ValueKey('leave-mine-$refresh'),
            future: api.get(ApiPaths.leaveMine),
            emptyMessage: 'Abhi koi leave request nahi hai.',
            builder: (context, data) {
              final rows = ((data as List?) ?? const [])
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              return Column(
                children: [
                  for (final row in rows.take(8))
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.event_note_outlined),
                        title: Text('${row['leave_type'] ?? 'Leave'}'),
                        subtitle: Text(
                          '${BusinessFormat.date(row['date_from'])} – ${BusinessFormat.date(row['date_to'])}\n${row['reason'] ?? ''}',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          BusinessFormat.status(row['status']),
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        if (app.can('workforce.leave.self') &&
            app.can('workforce.field_visit.self'))
          const Divider(height: 32),
        if (app.can('workforce.field_visit.self')) ...[
          Text('Field Visit', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          AsyncPanel(
            key: ValueKey('visit-current-$refresh'),
            future: api.get(ApiPaths.fieldVisitCurrent),
            emptyMessage: 'Koi active field visit nahi hai.',
            builder: (context, data) {
              final current = data is Map
                  ? Map<String, dynamic>.from(data)
                  : <String, dynamic>{};
              final id = int.tryParse('${current['id'] ?? ''}');
              if (id == null) return const SizedBox.shrink();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.route_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Visit #$id Running',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('${current['purpose'] ?? 'Field Visit'}'),
                      Text(
                        'Started: ${DateTimeText.local(current['started_at'])}',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => _completeVisit(id),
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Complete Visit'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _startVisit,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Start Field Visit'),
          ),
          const SizedBox(height: 8),
          Text(
            'Periodic GPS tracking backend v7.2 se connected hai. Check-In ke baad app foreground mein route points bhejti hai.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (message != null) ...[
          const SizedBox(height: 12),
          _feedbackBanner(message!),
        ],
      ],
    );
  }

  Future<void> _applyLeave() async {
    final app = ref.read(appStateProvider);
    final type = TextEditingController(text: 'Casual Leave');
    final from = TextEditingController(text: app.businessDate);
    final to = TextEditingController(text: app.businessDate);
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply Leave'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: type,
                decoration: const InputDecoration(labelText: 'Leave Type'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: from,
                decoration: const InputDecoration(labelText: 'From YYYY-MM-DD'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: to,
                decoration: const InputDecoration(labelText: 'To YYYY-MM-DD'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Reason'),
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(apiClientProvider).post(
          ApiPaths.leave,
          data: {
            'leave_type': type.text.trim(),
            'date_from': from.text.trim(),
            'date_to': to.text.trim(),
            'reason': reason.text.trim(),
          },
        );
        if (mounted)
          setState(() {
            refresh++;
            message = 'Leave request submitted.';
          });
      } catch (e) {
        if (mounted) setState(() => message = UiError.message(e));
      }
    }
    type.dispose();
    from.dispose();
    to.dispose();
    reason.dispose();
  }

  Future<void> _completeVisit(int id) async {
    try {
      final p = await _position();
      await ref.read(apiClientProvider).post(
        ApiPaths.visitComplete(id),
        data: {'lat': p.latitude, 'lng': p.longitude},
      );
      if (mounted) {
        setState(() {
          refresh++;
          message = 'Field Visit #$id completed.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _startVisit() async {
    final app = ref.read(appStateProvider);
    if (app.currentBranchId == null) {
      setState(() => message = 'Branch select karein.');
      return;
    }
    final purpose = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start Field Visit'),
        content: TextField(
          controller: purpose,
          decoration: const InputDecoration(labelText: 'Purpose'),
          minLines: 2,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, purpose.text.trim().isNotEmpty),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        final p = await _position();
        final r = Map<String, dynamic>.from(
          await ref.read(apiClientProvider).post(
            ApiPaths.fieldVisitStart,
            data: {
              'branch_id': app.currentBranchId,
              'purpose': purpose.text.trim(),
              'lat': p.latitude,
              'lng': p.longitude,
            },
          ) as Map,
        );
        if (mounted)
          setState(() {
            refresh++;
            message = 'Field Visit #${r['id']} started.';
          });
      } catch (e) {
        if (mounted) setState(() => message = UiError.message(e));
      }
    }
    purpose.dispose();
  }

}
