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
            emptyMessage: 'No leave requests are available.',
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
        if (app.can('workforce.leave.self')) ...[
          const SizedBox(height: 12),
          Text('Holiday Calendar', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          AsyncPanel(
            key: ValueKey('holidays-${app.currentBranchId}-$refresh'),
            future: app.currentBranchId == null
                ? Future.value(const <dynamic>[])
                : api.get(
                    ApiPaths.holidays,
                    query: {
                      'branch_id': app.currentBranchId,
                      'from': '${DateTime.now().year}-01-01',
                      'to': '${DateTime.now().year}-12-31',
                    },
                  ),
            emptyMessage: 'No holidays are published for this branch.',
            builder: (context, data) {
              final rows = ((data as List?) ?? const [])
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              return Column(
                children: [
                  for (final row in rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_available_outlined),
                      title: Text('${row['name'] ?? 'Holiday'}'),
                      subtitle: Text(BusinessFormat.date(row['holiday_date'])),
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
            emptyMessage: 'No active field visit is available.',
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
            'After check-in, the field route is recorded while the app remains open.',
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
    final businessDate = DateTime.tryParse(app.businessDate);
    if (businessDate == null) {
      _setFeatureState(() => message = 'Business date unavailable. Refresh and try again.');
      return;
    }
    final formKey = GlobalKey<FormState>();
    final type = TextEditingController(text: 'Casual Leave');
    final from = TextEditingController(text: app.businessDate);
    final to = TextEditingController(text: app.businessDate);
    final reason = TextEditingController();
    Future<void> pickDate(BuildContext dialogContext,
        TextEditingController controller) async {
      final selected = await showDatePicker(
        context: dialogContext,
        initialDate: DateTime.tryParse(controller.text) ?? businessDate,
        firstDate: DateTime(businessDate.year - 100),
        lastDate: DateTime(businessDate.year + 100, 12, 31),
      );
      if (selected != null && dialogContext.mounted) {
        controller.text = '${selected.year.toString().padLeft(4, '0')}-'
            '${selected.month.toString().padLeft(2, '0')}-'
            '${selected.day.toString().padLeft(2, '0')}';
        formKey.currentState?.validate();
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply Leave'),
        scrollable: true,
        content: SizedBox(
          width: 480,
          child: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: type,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Leave Type *'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter the leave type.' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: from,
                  readOnly: true,
                  onTap: () => pickDate(context, from),
                  decoration: InputDecoration(
                    labelText: 'From date *',
                    suffixIcon: IconButton(
                      tooltip: 'Choose start date',
                      onPressed: () => pickDate(context, from),
                      icon: const Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: to,
                  readOnly: true,
                  onTap: () => pickDate(context, to),
                  decoration: InputDecoration(
                    labelText: 'To date *',
                    suffixIcon: IconButton(
                      tooltip: 'Choose end date',
                      onPressed: () => pickDate(context, to),
                      icon: const Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                  validator: (_) => DateTime.parse(to.text)
                      .isBefore(DateTime.parse(from.text))
                      ? 'End date must be on or after the start date.' : null,
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Submit Leave Request'),
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
          _setFeatureState(() {
            refresh++;
            message = 'Leave request submitted.';
          });
      } catch (e) {
        if (mounted) _setFeatureState(() => message = UiError.message(e));
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
        _setFeatureState(() {
          refresh++;
          message = 'Field Visit #$id completed.';
        });
      }
    } catch (e) {
      if (mounted) _setFeatureState(() => message = UiError.message(e));
    }
  }

  Future<void> _startVisit() async {
    final app = ref.read(appStateProvider);
    if (app.currentBranchId == null) {
      _setFeatureState(() => message = 'Select an authorised branch.');
      return;
    }
    final purpose = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start Field Visit'),
        scrollable: true,
        content: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: TextFormField(
            controller: purpose,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Purpose *'),
            minLines: 2,
            maxLines: 4,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter the purpose of this visit.' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Start Field Visit'),
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
          _setFeatureState(() {
            refresh++;
            message = 'Field Visit #${r['id']} started.';
          });
      } catch (e) {
        if (mounted) _setFeatureState(() => message = UiError.message(e));
      }
    }
    purpose.dispose();
  }

}
