import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../widgets/async_panel.dart';

class AttendancePolicyPanel extends ConsumerStatefulWidget {
  const AttendancePolicyPanel({super.key});

  @override
  ConsumerState<AttendancePolicyPanel> createState() =>
      _AttendancePolicyPanelState();
}

class _AttendancePolicyPanelState extends ConsumerState<AttendancePolicyPanel> {
  static const labels = {
    'duty_start': 'Official start / Self check-in',
    'gps_start': 'GPS tracking start',
    'gps_stop': 'GPS tracking stop',
    'duty_end': 'Official duty end',
    'auto_checkout': 'Automatic checkout',
  };
  int revision = 0;
  bool saving = false;
  String? message;

  @override
  Widget build(BuildContext context) => AsyncPanel(
    key: ValueKey('attendance-policy-$revision'),
    loader: () => ref.read(apiClientProvider).get(ApiPaths.attendancePolicy),
    builder: (context, data) {
      final policy = Map<String, dynamic>.from(data as Map);
      final current = policy['current'] as Map?;
      final upcoming = (policy['upcoming'] as List?) ?? const [];
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Company attendance policy',
              style: Theme.of(context).textTheme.titleLarge),
          const Text('A new schedule takes effect on a future business date. '
              'Existing attendance keeps its original timing and evidence. '
              'GPS stops separately from checkout. Salary deductions are not changed.'),
          const SizedBox(height: 12),
          if (current == null)
            const Card(child: ListTile(
              title: Text('Self attendance not active'),
              subtitle: Text('Schedule an effective date to replace legacy automatic duty.'),
            ))
          else
            _scheduleCard('Current schedule', current),
          for (final item in upcoming.whereType<Map>())
            _scheduleCard('Scheduled change', item),
          if (message != null) Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(message!),
          ),
          FilledButton.icon(
            onPressed: saving ? null : () => _edit(policy),
            icon: const Icon(Icons.edit_calendar_outlined),
            label: Text(saving ? 'Saving…' : 'Schedule policy'),
          ),
        ],
      );
    },
  );

  Widget _scheduleCard(String label, Map schedule) {
    final times = Map<String, dynamic>.from(schedule['times'] as Map);
    return Card(child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label · ${schedule['effective_from']}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        for (final entry in labels.entries)
          Text('${entry.value}: ${times[entry.key]}'),
      ]),
    ));
  }

  Future<void> _edit(Map<String,dynamic> policy) async {
    final today = DateTime.tryParse('${policy['business_date']}');
    if (today == null) {
      setState(() => message = 'Server business date unavailable.');
      return;
    }
    final tomorrow = today.add(const Duration(days: 1));
    final day = TextEditingController(text: tomorrow.toIso8601String().substring(0,10));
    final reason = TextEditingController();
    final current = policy['current'] as Map?;
    final defaults = Map<String,dynamic>.from((current?['times'] ?? policy['defaults']) as Map);
    final fields = {for (final key in labels.keys)
      key: TextEditingController(text: '${defaults[key]}'.substring(0,5))};
    Map<String,dynamic>? payload;
    try {
      payload = await showDialog<Map<String,dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Schedule attendance policy'),
          scrollable: true,
          content: SizedBox(width: 420,child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: day,decoration: const InputDecoration(
                labelText: 'Effective date (YYYY-MM-DD)')),
              for (final entry in labels.entries)
                TextField(controller: fields[entry.key],decoration: InputDecoration(
                  labelText: '${entry.value} (HH:MM, 24-hour)')),
              TextField(controller: reason,decoration: const InputDecoration(
                labelText: 'Reason for audited policy change'),maxLength: 250),
              const Text('A new effective date never rewrites earlier attendance.'),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context,{
              'effective_from':day.text.trim(),
              'times':{for (final entry in fields.entries)
                entry.key:'${entry.value.text.trim()}:00'},
              'reason':reason.text.trim(),
            }),child: const Text('Confirm schedule')),
          ],
        ),
      );
    } finally {
      day.dispose();reason.dispose();
      for (final c in fields.values) {c.dispose();}
    }
    if (payload == null || !mounted) return;
    setState(() {saving=true;message=null;});
    try {
      await ref.read(apiClientProvider).post(ApiPaths.attendancePolicy,data:payload);
      if (mounted) setState(() {revision++;message='Schedule saved.';});
    } catch (e) {
      if (mounted) setState(() => message=UiError.message(e));
    } finally {
      if (mounted) setState(() => saving=false);
    }
  }
}
