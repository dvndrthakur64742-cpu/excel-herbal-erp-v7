part of 'my_work_screen.dart';

extension _MyWorkAttendance on _MyWorkScreenState {
  Future<void> _selfPunch(Map<String, dynamic> record, bool checkIn, {int? exceptionId}) async {
    if (_attendancePunchBusy) return;
    _setFeatureState(() { _attendancePunchBusy = true; message = null; });
    try {
      final branch = int.tryParse('${record['assigned_branch_id']}');
      if (checkIn && (branch == null || branch < 1)) {
        throw Exception('Assigned branch required.');
      }
      final fix = exceptionId == null ? await _position() : null;
      if (!mounted) return;
      await ref.read(apiClientProvider).post(
        checkIn ? ApiPaths.checkIn : ApiPaths.checkOut,
        data: {
          if (checkIn) 'branch_id': branch,
          if (fix != null) 'lat': fix.latitude,
          if (fix != null) 'lng': fix.longitude,
          if (exceptionId != null) 'gps_exception_id': exceptionId,
        },
      );
      if (!mounted) return;
      if (!checkIn) ref.read(gpsTrackingProvider).stop(status: 'checked_out');
      _setFeatureState(() {
        refresh++;
        message = checkIn ? 'Check-in saved.' : 'Checkout saved.';
      });
      await ref.read(gpsTrackingProvider).sync();
    } catch (e) {
      if (mounted) _setFeatureState(() => message = UiError.message(e));
    } finally {
      if (mounted) _setFeatureState(() => _attendancePunchBusy = false);
    }
  }

  Future<void> _requestGpsException(bool checkIn) async {
    if (_attendancePunchBusy) return;
    _setFeatureState(() => _attendancePunchBusy = true);
    final controller = TextEditingController();
    String? validation;
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
          title: const Text('Request GPS exception'),
          scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Head Office must approve this request. Approval does not automatically mark attendance or authorize stock issue.'),
            TextField(controller: controller, maxLength: 250, maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'GPS problem (at least 10 characters)',
                  errorText: validation,
                )),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              final text = controller.text.trim();
              if (text.length < 10) {
                setLocal(() => validation = 'Enter at least 10 characters.');
                return;
              }
              Navigator.pop(dialogContext, text);
            }, child: const Text('Send request')),
          ],
        )),
      );
      if (reason == null || !mounted) return;
      if (reason.length < 10) {
        _setFeatureState(() => message = 'Enter a reason of at least 10 characters.');
        return;
      }
      await ref.read(apiClientProvider).post(ApiPaths.gpsExceptionRequest,
        data: {'scope': checkIn ? 'check_in' : 'check_out', 'reason': reason});
      if (mounted) _setFeatureState(() {refresh++; message = 'Sent to Head Office for review.';});
    } catch (e) {
      if (mounted) _setFeatureState(() => message = UiError.message(e));
    } finally {
      controller.dispose();
      if (mounted) _setFeatureState(() => _attendancePunchBusy = false);
    }
  }

  Widget _gpsExceptionPanel(Map<String, dynamic> record, bool checkedIn) {
    final scope = checkedIn ? 'check_out' : 'check_in';
    final canPunch = record[checkedIn ? 'can_check_out' : 'can_check_in'] == true;
    return AsyncPanel(
      key: ValueKey('gps-exception-$refresh-$scope'),
      loader: () => ref.read(apiClientProvider).get(ApiPaths.gpsExceptionMine).then((rows) => {'rows': rows}),
      builder: (context, data) {
        final rows = (((data as Map)['rows'] as List?) ?? const []).whereType<Map>();
        final matching = rows.where((r) =>
            r['business_date'] == record['business_date'] && r['scope'] == scope);
        final request = matching.isEmpty ? null : matching.first;
        final status = request?['status'];
        final id = int.tryParse('${request?['id']}');
        return Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('GPS problem?', style: TextStyle(fontWeight: FontWeight.w700)),
            if (request != null) ...[
              Text('Request: ${BusinessFormat.status(status)}'),
              if (request['review_reason'] != null) Text('${request['review_reason']}'),
            ],
            if (canPunch && request == null)
              TextButton(onPressed: _attendancePunchBusy ? null : () => _requestGpsException(!checkedIn),
                child: const Text('Request Head Office approval')),
            if (canPunch && status == 'approved' && id != null && id > 0)
              OutlinedButton(onPressed: _attendancePunchBusy ? null : () async {
                final confirmed = await showDialog<bool>(context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Use approved GPS exception?'),
                    content: const Text('This records the punch without a verified GPS location. The approval can be used only once.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Confirm punch')),
                    ],
                  ));
                if (confirmed == true && mounted) await _selfPunch(record, !checkedIn, exceptionId: id);
              }, child: Text(checkedIn ? 'Checkout with approval' : 'Check in with approval')),
            TextButton(onPressed: () => _setFeatureState(() => refresh++), child: const Text('Refresh approval')),
          ]),
        ));
      },
    );
  }

  Widget _attendance() {
    final api = ref.watch(apiClientProvider);
    final app = ref.watch(appStateProvider);
    final tracker = ref.watch(gpsTrackingProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        AsyncPanel(
          key: ValueKey('att-$refresh'),
          loader: () => api.get(ApiPaths.attendanceToday),
          emptyMessage: 'Aaj attendance pending hai.',
          builder: (context, data) {
            final r = data is Map
                ? Map<String, dynamic>.from(data)
                : <String, dynamic>{};
            final selfMode = r['attendance_mode'] == 'self';
            final checkedIn =
                '${r['check_in_at'] ?? ''}'.trim().isNotEmpty;
            final checkedOut =
                '${r['check_out_at'] ?? ''}'.trim().isNotEmpty;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          checkedOut
                              ? Icons.verified_outlined
                              : checkedIn
                                  ? Icons.timelapse_rounded
                                  : Icons.schedule_outlined,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AttendanceStatusDisplay.title(
                                  checkedIn: checkedIn,
                                  checkedOut: checkedOut,
                                  blockReason: r['check_in_block_reason'],
                                ),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              if (checkedIn)
                                Text(
                                  'Check-In: ${DateTimeText.business(r['check_in_at'], app.businessTimezone)}',
                                )
                              else
                                Text(selfMode
                                    ? switch (r['check_in_block_reason']) {
                                        'approved_leave' => 'Approved leave today. Check-in is not required.',
                                        'holiday' => 'Today is a holiday. Check-in is not required.',
                                        'inactive_assignment' => 'Active branch assignment required. Contact your administrator.',
                                        _ => 'Check in yourself with your current location.',
                                      }
                                    : 'Duty automatically starts at 10:30 AM; no manual check-in is required.'),
                              if (checkedIn) ...[
                                const SizedBox(height: 2),
                                Text(
                                  checkedOut
                                      ? 'Check-Out: ${DateTimeText.business(r['check_out_at'], app.businessTimezone)}'
                                      : 'Check-Out: pending',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text('ERP business date: ${r['business_date'] ?? app.businessDate} · ${app.businessTimezone}'),
                if (selfMode) ...[
                  Text('Office: ${r['official_start']}–${r['official_end']} · '
                      'GPS: ${r['gps_start_time']}–${r['gps_stop_time']} · '
                      'Auto checkout: ${r['auto_checkout_time']}'),
                  if (r['checkout_mode'] == 'auto')
                    const Text('Automatic checkout · not a verified employee punch'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: !_attendancePunchBusy &&
                            (checkedIn ? r['can_check_out'] == true : r['can_check_in'] == true)
                        ? () => _selfPunch(r, !checkedIn)
                        : null,
                    icon: Icon(checkedIn ? Icons.logout : Icons.login),
                    label: Text(_attendancePunchBusy ? 'Saving…' :
                        checkedOut ? 'Attendance completed' :
                        checkedIn ? 'Check Out' : 'Check In'),
                  ),
                  if (!checkedOut) _gpsExceptionPanel(r, checkedIn),
                  TextButton.icon(
                    onPressed: () => _setFeatureState(() => refresh++),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh attendance'),
                  ),
                ] else
                  const Chip(
                    avatar: Icon(Icons.schedule_outlined, size: 18),
                    label: Text('Duty is automatic · 10:30 AM–5:00 PM'),
                  ),
              ],
            );
          },
        ),
        Card(child: ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Attendance history / correction'),
          subtitle: const Text('Review past records and request Head Office correction.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Attendance history')),
            body: const SafeArea(child: AttendanceTimeReviewPanel()),
          ))),
        )),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: Icon(
              tracker.active
                  ? Icons.location_searching_rounded
                  : Icons.location_off_outlined,
            ),
            title: const Text('Duty GPS'),
            subtitle: Text(
              [
                BusinessFormat.status(tracker.dutyStatus),
                if (tracker.lastSentAt != null)
                  'Last sync ${DateTimeText.business(tracker.lastSentAt!.toUtc().toIso8601String(), app.businessTimezone)}',
                if (tracker.lastError != null) tracker.lastError!,
              ].join(' · '),
            ),
            trailing: IconButton(
              tooltip: 'Refresh duty GPS status',
              onPressed: tracker.sending
                  ? null
                  : () async {
                      await ref.read(gpsTrackingProvider).sync();
                      if (mounted) {
                        _setFeatureState(
                          () => message = 'Duty GPS status refreshed.',
                        );
                      }
                    },
              icon: tracker.sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.route_outlined),
            title: const Text('Today’s GPS Route'),
            subtitle: const Text(
              'View GPS points, route trace and distance recorded during duty.' ,
            ),
            trailing: IconButton(
              tooltip: 'Refresh today’s route',
              onPressed: () => _setFeatureState(() => refresh++),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        ),
        AsyncPanel(
          key: ValueKey('gps-route-$refresh'),
          loader: () => api.get(
            ApiPaths.gpsRoute,
            query: GpsRouteQuery.forBusinessDate(app.businessDate),
          ),
          emptyMessage: 'No GPS route points have been recorded today.',
          builder: (context, data) {
            final points = ((data as List?) ?? const [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(growable: false);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GpsRouteView(points: points),
            );
          },
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          _feedbackBanner(message!),
        ],
      ],
    );
  }

}
