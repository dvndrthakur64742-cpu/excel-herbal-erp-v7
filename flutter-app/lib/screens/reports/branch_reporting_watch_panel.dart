import 'package:flutter/material.dart';

/// Manager reporting agenda / regional exception dashboard.
/// Server does all company/branch/role scoping. This view never sends alerts,
/// schedules a notification or infers proof of submitted weekly reports.
class BranchReportingWatchPanel extends StatelessWidget {
  const BranchReportingWatchPanel({super.key, required this.data});

  final dynamic data;

  static List<Map<String, dynamic>> _records(dynamic value) {
    if (value is! List) return [];
    return value.whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (data is! Map) {
      return const Center(child: Text('Manager reporting data unavailable.'));
    }
    final report = Map<String, dynamic>.from(data as Map);
    final coverage = report['coverage'];
    if (report['read_only'] != true ||
        report['scope'] != 'authenticated_authorized_active_branches_only' ||
        report['delivery_enabled'] != false ||
        report['automatic_notifications_sent'] != 0 ||
        coverage is! Map ||
        coverage['daily_status_from_original_v7_posted_evening'] != true ||
        coverage['weekly_monthly_product_salary_submission_evidence_integrated'] != true ||
        coverage['cashier_handover_verified'] != false ||
        coverage['upi_bank_verified'] != false ||
        report['submission_registry_read_only'] != true ||
        report['reminder_outbox_dispatch_enabled'] != false ||
        report['submission_evidence_summary'] is! Map ||
        report['summary'] is! Map ||
        report['branches'] is! List ||
        report['schedule'] is! List ||
        report['reminder_candidates'] is! List) {
      return const Center(child: Text('Manager reporting security/evidence contract mismatch.'));
    }
    final summary = Map<String, dynamic>.from(report['summary'] as Map);
    final branches = _records(report['branches']);
    final slots = _records(report['schedule']);
    final pending = _records(report['reminder_candidates']);
    final submissions = Map<String, dynamic>.from(report['submission_evidence_summary'] as Map);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Business day ${report['business_date']} · ${report['timezone']}\n'
              'Read-only live-status on refresh. Reminders below are candidates ONLY: '
              'no notifications have been sent. Weekly, product, monthly and salary '
              'receipt states come from manager attestations, NOT verified payment proof.',
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _WatchMetric(label: 'Branches', value: '${summary['branches']}'),
            _WatchMetric(label: 'Eligible FSE', value: '${summary['eligible_field_staff']}'),
            _WatchMetric(label: 'Posted Closings', value: '${summary['posted_evening_closings']}'),
            _WatchMetric(label: 'No Daily Cycle', value: '${summary['missing_daily_cycles']}'),
            _WatchMetric(label: 'Unposted Evening', value: '${summary['unposted_evening_closings']}'),
            _WatchMetric(label: 'Past Due After 7:30 PM', value: '${summary['past_due_unposted_or_missing']}'),
            _WatchMetric(label: 'Attention Branches', value: '${summary['branch_exceptions']}'),
            _WatchMetric(label: 'Reports Submitted', value: '${submissions['submitted']}'),
            _WatchMetric(label: 'Reports Approved', value: '${submissions['approved']}'),
            _WatchMetric(label: 'Reports Rejected', value: '${submissions['rejected']}'),
            _WatchMetric(label: 'Reports Not Submitted', value: '${submissions['not_submitted']}'),
          ],
        ),
        const SizedBox(height: 14),
        Text('Reporting Schedule', style: Theme.of(context).textTheme.titleMedium),
        for (final slot in slots)
          Card(
            child: ListTile(
              title: Text('${slot['label']}'),
              subtitle: Text(
                'Due: ${slot['time'] ?? 'end of day'} · ${slot['due_state']}\n'
                'Evidence: ${slot['submission_state']}' +
                    (slot['time'] == null ? ' · no exact time deadline' : ''),
              ),
              trailing: slot['submission_state'] == 'overdue_evidence'
                  ? Icon(Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error)
                  : const Icon(Icons.schedule_outlined),
            ),
          ),
        const SizedBox(height: 14),
        Text('Branch Daily Closing Exceptions',
            style: Theme.of(context).textTheme.titleMedium),
        if (branches.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No authorized active branches.'),
          ),
        for (final branch in branches)
          Card(
            child: ExpansionTile(
              title: Text('${branch['branch_name']} · #${branch['branch_id']}'),
              subtitle: Text(
                'Posted ${branch['posted_evening_closings']} / '
                '${branch['eligible_field_staff']} · '
                'Past due ${branch['past_due_unposted_or_missing']} · '
                'Pending stock requests ${branch['pending_stock_requests']}',
              ),
              children: [
                for (final obligation in _records(branch['reporting_submissions']))
                  ListTile(
                    title: Text('Report: ${obligation['report_type']}'),
                    subtitle: Text(
                      'Status: ${obligation['submission_state']} · '
                      'Revision: ${obligation['revision'] ?? '—'}',
                    ),
                    trailing: obligation['submission_state'] == 'approved'
                        ? const Icon(Icons.check_circle_outline)
                        : const Icon(Icons.assignment_late_outlined),
                  ),
                for (final employee in _records(branch['employees']))
                  ListTile(
                    title: Text('${employee['employee_name']} · #${employee['employee_id']}'),
                    subtitle: Text('Daily closing: ${employee['closing_state']}'),
                    trailing: employee['closing_state'] == 'posted'
                        ? const Icon(Icons.check_circle_outline)
                        : Icon(Icons.warning_amber_rounded,
                            color: Theme.of(context).colorScheme.error),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text('Undispatched Follow-up Candidates: ${pending.length}',
            style: Theme.of(context).textTheme.titleMedium),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'These are review candidates, NOT sent WhatsApp, email or push reminders. '
            'Delivery and submission tracking need a separately approved integration.',
          ),
        ),
      ],
    );
  }
}

class _WatchMetric extends StatelessWidget {
  const _WatchMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 153,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
