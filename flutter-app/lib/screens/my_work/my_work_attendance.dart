part of 'my_work_screen.dart';

extension _MyWorkAttendance on _MyWorkScreenState {
  Widget _attendance() {
    final api = ref.watch(apiClientProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        AsyncPanel(
          key: ValueKey('att-$refresh'),
          future: api.get(ApiPaths.attendanceToday),
          emptyMessage: 'Aaj attendance pending hai.',
          builder: (context, data) {
            if (data == null) return const SizedBox.shrink();
            final r = Map<String, dynamic>.from(data as Map);
            return Card(
              child: ListTile(
                title: Text('${r['status'] ?? 'present'}'),
                subtitle: Text(
                  'Check-In: ${DateTimeText.local(r['check_in_at'])}\n'
                  'Check-Out: ${DateTimeText.local(r['check_out_at'])}',
                ),
                isThreeLine: true,
              ),
            );
          },
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          _feedbackBanner(message!),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _attendanceAction(true),
              icon: const Icon(Icons.login),
              label: const Text('Check-In'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _attendanceAction(false),
              icon: const Icon(Icons.logout),
              label: const Text('Check-Out'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _attendanceAction(bool checkIn) async {
    final app = ref.read(appStateProvider);
    if (checkIn && app.currentBranchId == null) {
      _setFeatureState(() => message = 'Authorised Branch select karein.');
      return;
    }
    try {
      final p = await _position();
      await ref.read(apiClientProvider).post(
        checkIn ? ApiPaths.checkIn : ApiPaths.checkOut,
        data: {
          if (checkIn) 'branch_id': app.currentBranchId,
          'lat': p.latitude,
          'lng': p.longitude,
        },
      );
      var gpsStarted = !checkIn;
      if (checkIn) {
        try {
          await ref.read(gpsTrackingProvider).start();
          gpsStarted = true;
        } catch (_) {
          gpsStarted = false;
          // Attendance remains successful even if periodic tracking could not
          // start; the ERP Tools screen exposes the tracking status/retry.
        }
      } else {
        ref.read(gpsTrackingProvider).stop();
      }
      if (mounted) {
        _setFeatureState(() {
          refresh++;
          message = checkIn
              ? (gpsStarted
                  ? 'Check-In successful. GPS tracking started.'
                  : 'Check-In successful. GPS tracking could not start; ERP Tools se retry karein.')
              : 'Check-Out successful. GPS tracking stopped.';
        });
      }
    } catch (e) {
      if (mounted) _setFeatureState(() => message = UiError.message(e));
    }
  }

}
