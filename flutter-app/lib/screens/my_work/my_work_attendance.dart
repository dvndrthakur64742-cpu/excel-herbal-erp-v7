part of 'my_work_screen.dart';

extension _MyWorkAttendance on _MyWorkScreenState {
  Widget _attendance() {
    final api = ref.watch(apiClientProvider);
    final app = ref.watch(appStateProvider);
    final tracker = ref.watch(gpsTrackingProvider);
    final routeDay = DateTime.tryParse(app.businessDate) ?? DateTime.now();
    final routeFrom = DateTime(routeDay.year, routeDay.month, routeDay.day).toUtc();
    final routeTo = DateTime(routeDay.year, routeDay.month, routeDay.day, 23, 59, 59).toUtc();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        AsyncPanel(
          key: ValueKey('att-$refresh'),
          future: api.get(ApiPaths.attendanceToday),
          emptyMessage: 'Aaj attendance pending hai.',
          builder: (context, data) {
            final r = data is Map
                ? Map<String, dynamic>.from(data)
                : <String, dynamic>{};
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
                                checkedOut
                                    ? 'Duty completed for today'
                                    : checkedIn
                                        ? 'Duty in progress'
                                        : 'Attendance pending',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              if (checkedIn)
                                Text(
                                  'Check-In: ${DateTimeText.local(r['check_in_at'])}',
                                )
                              else
                                const Text(
                                  'Duty automatically starts at 10:30 AM; no manual check-in is required.',
                                ),
                              if (checkedIn) ...[
                                const SizedBox(height: 2),
                                Text(
                                  checkedOut
                                      ? 'Check-Out: ${DateTimeText.local(r['check_out_at'])}'
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
                const Chip(
                  avatar: Icon(Icons.schedule_outlined, size: 18),
                  label: Text('Duty is automatic · 10:30 AM–5:00 PM'),
                ),
              ],
            );
          },
        ),
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
                  'Last sync ${BusinessFormat.dateTime(tracker.lastSentAt!.toIso8601String())}',
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
              'Check-in duty ke dauran server par record hue GPS points, route trace aur distance.',
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
          future: api.get(
            ApiPaths.gpsRoute,
            query: {
              'from': routeFrom.toIso8601String(),
              'to': routeTo.toIso8601String(),
            },
          ),
          emptyMessage: 'Aaj abhi koi GPS route point record nahi hua.',
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
