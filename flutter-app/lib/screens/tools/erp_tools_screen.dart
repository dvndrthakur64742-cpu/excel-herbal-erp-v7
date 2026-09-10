import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/business_format.dart';
import '../../core/ui_error.dart';
import '../../theme/excel_brand.dart';
import '../../state/app_state.dart';

class ErpToolsScreen extends ConsumerStatefulWidget {
  const ErpToolsScreen({super.key});

  @override
  ConsumerState<ErpToolsScreen> createState() => _ErpToolsScreenState();
}

class _ErpToolsScreenState extends ConsumerState<ErpToolsScreen> {
  int refresh = 0;
  String? message;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final tabs = <(String, IconData, Widget)>[
      if (app.can('workforce.attendance.self'))
        ('Duty', Icons.location_on_outlined, _dutyTab(app)),
      ('My Account', Icons.badge_outlined, _accountTab(app)),
      if (app.can('communication.view'))
        ('Communication', Icons.notifications_outlined, _communicationTab(app)),
      if (app.canAny(const [
        'organization.employee.manage',
        'administration.access.manage',
        'administration.audit.view',
      ]))
        ('Admin', Icons.admin_panel_settings_outlined, _adminTab(app)),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Account & Duty'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => setState(() {
                refresh++;
                message = null;
              }),
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              for (final tab in tabs)
                Tab(icon: Icon(tab.$2, size: 19), text: tab.$1),
            ],
          ),
        ),
        body: Column(
          children: [
            if (message != null)
              Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.info_outline),
                  title: Text(message!),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => message = null),
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(children: [for (final tab in tabs) tab.$3]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dutyTab(AppState app) {
    final api = ref.watch(apiClientProvider);
    final tracker = ref.watch(gpsTrackingProvider);
    final now = DateTime.now();
    final from = DateTime(
      now.year,
      now.month,
      now.day,
    ).toUtc().toIso8601String();
    final to = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
    ).toUtc().toIso8601String();

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(gpsTrackingProvider).sync();
        if (mounted) setState(() => refresh++);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color:
                  tracker.active ? ExcelBrand.primarySoft : ExcelBrand.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: tracker.active
                    ? const Color(0xFFB9DFC8)
                    : ExcelBrand.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: tracker.active
                            ? ExcelBrand.primary
                            : const Color(0xFFF0F4F1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        tracker.active
                            ? Icons.location_searching_rounded
                            : Icons.location_off_outlined,
                        color: tracker.active ? Colors.white : ExcelBrand.muted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Duty GPS Tracking',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            BusinessFormat.status(tracker.dutyStatus),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: tracker.active
                                      ? ExcelBrand.primaryDark
                                      : ExcelBrand.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: tracker.active
                            ? const Color(0xFFD4EEDC)
                            : const Color(0xFFF0F2F1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        BusinessFormat.status(tracker.dutyStatus).toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: tracker.active
                              ? ExcelBrand.primaryDark
                              : ExcelBrand.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                if (tracker.lastSentAt != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 19,
                        color: ExcelBrand.primaryDark,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Last synced ${BusinessFormat.dateTime(tracker.lastSentAt!.toIso8601String())}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                if (tracker.lastError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF2F2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 19,
                          color: ExcelBrand.danger,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tracker.lastError!,
                            style: const TextStyle(
                              color: Color(0xFF8C2D2D),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ExcelBrand.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.policy_outlined,
                        size: 19,
                        color: ExcelBrand.primaryDark,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Duty GPS starts automatically from attendance/server policy and stops after checkout or the duty cutoff. There is no manual route Start/Stop.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: tracker.sending
                        ? null
                        : () async {
                            await ref.read(gpsTrackingProvider).sync();
                            if (mounted) {
                              _msg('Duty GPS status refreshed.');
                            }
                          },
                    icon: tracker.sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: const Text('Refresh duty GPS status'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _futureCard(
            title: 'Today’s GPS Route',
            future: api.get(ApiPaths.gpsRoute, query: {'from': from, 'to': to}),
            builder: (data) {
              final rows = _rows(data);
              if (rows.isEmpty) {
                return _emptyInline(
                  Icons.route_outlined,
                  'No route points yet',
                  tracker.active
                      ? 'The first valid duty location will appear here after the automatic sync.'
                      : 'Check in first. Duty route tracking starts automatically inside the server-owned GPS window.',
                );
              }
              return Column(
                children: [
                  for (final r in rows.reversed.take(12)) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: ExcelBrand.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.location_on_outlined,
                          size: 21,
                          color: ExcelBrand.primaryDark,
                        ),
                      ),
                      title: Text(
                        '${r['latitude']}, ${r['longitude']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${BusinessFormat.dateTime(r['recorded_at'])} · accuracy ${r['accuracy_m'] ?? '—'} m',
                      ),
                    ),
                    if (r != rows.reversed.take(12).last)
                      const Divider(height: 1),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _futureCard(
            title: 'Holidays',
            action: app.can('workforce.leave.manage')
                ? IconButton.filledTonal(
                    tooltip: 'New Holiday',
                    onPressed: () => _createHoliday(app),
                    icon: const Icon(Icons.add_rounded),
                  )
                : null,
            future: api.get(
              ApiPaths.holidays,
              query: {
                if (app.currentBranchId != null)
                  'branch_id': app.currentBranchId,
                'from': '${now.year}-01-01',
                'to': '${now.year}-12-31',
              },
            ),
            builder: (data) {
              final rows = _rows(data);
              if (rows.isEmpty) {
                return _emptyInline(
                  Icons.event_available_outlined,
                  'No holidays configured',
                  app.can('workforce.leave.manage')
                      ? 'Use + to add a company or branch holiday.'
                      : 'No holiday has been published for this branch yet.',
                );
              }
              return Column(
                children: rows.map((r) {
                  final id = int.tryParse('${r['id']}') ?? 0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.event_outlined,
                      color: ExcelBrand.primaryDark,
                    ),
                    title: Text(
                      '${r['name'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(BusinessFormat.date(r['holiday_date'])),
                    trailing: app.can('workforce.leave.manage') && id > 0
                        ? IconButton(
                            tooltip: 'Deactivate',
                            icon: const Icon(Icons.more_vert_rounded),
                            onPressed: () async {
                              final ok = await _confirm(
                                'Deactivate holiday?',
                                'This holiday will be removed from the active list. Continue?',
                              );
                              if (ok != true) return;
                              await _post(
                                ApiPaths.holidayDeactivate(id),
                                const {},
                              );
                            },
                          )
                        : null,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _emptyInline(IconData icon, String title, String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F5F2),
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: ExcelBrand.primaryDark, size: 22),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: ExcelBrand.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _accountTab(AppState app) {
    final api = ref.watch(apiClientProvider);
    final employee = Map<String, dynamic>.from(
      (app.me['employee'] as Map?) ?? const <String, dynamic>{},
    );
    final employeeId = int.tryParse('${employee['id'] ?? ''}') ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _futureCard(
          title: 'My Active Devices / Sessions',
          action: TextButton(
            onPressed: () async {
              final ok = await _confirm(
                'Logout all devices?',
                'You will also need to sign in again on this device.',
              );
              if (ok != true) return;
              try {
                await api.post(
                  ApiPaths.logoutAll,
                  data: const {},
                  idempotent: false,
                );
              } catch (_) {}
              await ref.read(appStateProvider.notifier).logout();
            },
            child: const Text('Logout All'),
          ),
          future: api.get(ApiPaths.authSessions),
          builder: (data) {
            final rows = _rows(data);
            if (rows.isEmpty) return const Text('No mobile sessions.');
            return Column(
              children: rows.map((r) {
                final id = int.tryParse('${r['id']}') ?? 0;
                final current = r['current'] == true;
                final active = r['active'] == true;
                return ListTile(
                  leading: Icon(current ? Icons.phone_android : Icons.devices),
                  title: Text('${r['device_name'] ?? 'Mobile device'}'),
                  subtitle: Text(
                    '${active ? 'Active' : 'Inactive'} · ${r['last_used_at'] ?? r['created_at'] ?? ''}',
                  ),
                  trailing: active && !current && id > 0
                      ? IconButton(
                          tooltip: 'Logout device',
                          icon: const Icon(Icons.logout),
                          onPressed: () => _post(
                            ApiPaths.authSessionRevoke(id),
                            const {},
                            idempotent: false,
                          ),
                        )
                      : current
                          ? const Chip(label: Text('This device'))
                          : null,
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 12),
        if (employeeId > 0)
          _futureCard(
            title: 'My Documents',
            action: app.can('organization.employee.manage')
                ? IconButton(
                    tooltip: 'Upload document',
                    onPressed: () => _uploadDocument(employeeId),
                    icon: const Icon(Icons.upload_file_outlined),
                  )
                : null,
            future: api.get(ApiPaths.employeeDocuments(employeeId)),
            builder: (data) {
              final rows = _rows(data);
              if (rows.isEmpty) return const Text('No documents uploaded.');
              return Column(
                children: rows.map((r) {
                  final url = '${r['url'] ?? ''}'.trim();
                  return ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text('${r['title'] ?? r['filename'] ?? 'Document'}'),
                    subtitle: Text('${r['document_type'] ?? ''}'),
                    trailing: url.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Open',
                            onPressed: () async {
                              final uri = Uri.tryParse(url);
                              if (uri != null) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                            icon: const Icon(Icons.open_in_new),
                          ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _communicationTab(AppState app) {
    final api = ref.watch(apiClientProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (app.can('communication.manage'))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _createTask,
                    icon: const Icon(Icons.add_task),
                    label: const Text('New Task'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _createAnnouncement(app),
                    icon: const Icon(Icons.campaign_outlined),
                    label: const Text('Announcement'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _createNotification,
                    icon: const Icon(Icons.notification_add_outlined),
                    label: const Text('Notification'),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        _futureCard(
          title: 'My Communication',
          action: TextButton(
            onPressed: () => _post(ApiPaths.notificationReadAll, const {}),
            child: const Text('Read All'),
          ),
          future: api.get(ApiPaths.communicationSummary),
          builder: (data) {
            final d = Map<String, dynamic>.from((data as Map?) ?? const {});
            final tasks = _rows(d['tasks']);
            final announcements = _rows(d['announcements']);
            final notifications = _rows(d['notifications']);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Tasks (${tasks.length})'),
                if (tasks.isEmpty) const Text('No pending tasks.'),
                ...tasks.map((r) {
                  final id = int.tryParse('${r['id']}') ?? 0;
                  return ListTile(
                    leading: const Icon(Icons.task_alt_outlined),
                    title: Text('${r['title'] ?? 'Task'}'),
                    subtitle: Text('${r['due_at'] ?? ''}'),
                    trailing: id > 0
                        ? IconButton(
                            tooltip: 'Complete',
                            icon: const Icon(Icons.check_circle_outline),
                            onPressed: () =>
                                _post(ApiPaths.taskComplete(id), const {}),
                          )
                        : null,
                  );
                }),
                _sectionTitle('Announcements (${announcements.length})'),
                if (announcements.isEmpty) const Text('No announcements.'),
                ...announcements.map((r) {
                  final id = int.tryParse('${r['id']}') ?? 0;
                  return ListTile(
                    leading: const Icon(Icons.campaign_outlined),
                    title: Text('${r['title'] ?? ''}'),
                    subtitle: Text('${r['body'] ?? ''}'),
                    trailing: id > 0
                        ? TextButton(
                            onPressed: () => _post(
                              ApiPaths.announcementAcknowledge(id),
                              const {},
                            ),
                            child: const Text('Acknowledge'),
                          )
                        : null,
                  );
                }),
                _sectionTitle('Notifications (${notifications.length})'),
                if (notifications.isEmpty) const Text('No notifications.'),
                ...notifications.map((r) {
                  final id = int.tryParse('${r['id']}') ?? 0;
                  final read = '${r['read_at'] ?? ''}'.isNotEmpty;
                  return ListTile(
                    leading: Icon(
                      read
                          ? Icons.notifications_none
                          : Icons.notifications_active_outlined,
                    ),
                    title: Text('${r['title'] ?? ''}'),
                    subtitle: Text('${r['body'] ?? ''}'),
                    trailing: !read && id > 0
                        ? IconButton(
                            tooltip: 'Mark read',
                            onPressed: () =>
                                _post(ApiPaths.notificationRead(id), const {}),
                            icon: const Icon(Icons.done),
                          )
                        : null,
                  );
                }),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _adminTab(AppState app) {
    final api = ref.watch(apiClientProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (app.can('organization.employee.manage'))
          _futureCard(
            title: 'Employee App Login Management',
            future: api.get(
              ApiPaths.employees,
              query: {'status': 'all', 'limit': 200},
            ),
            builder: (data) {
              final rows = _rows(data);
              if (rows.isEmpty) return const Text('No employees.');
              return Column(
                children: rows.map((r) {
                  final id = int.tryParse('${r['id']}') ?? 0;
                  return ListTile(
                    leading: Icon(
                      r['login_enabled'] == '1' ||
                              r['login_enabled'] == 1 ||
                              r['login_enabled'] == true
                          ? Icons.verified_user_outlined
                          : Icons.person_off_outlined,
                    ),
                    title: Text('${r['full_name'] ?? ''}'),
                    subtitle: Text(
                      '${r['employee_code'] ?? ''} · ${r['mobile'] ?? 'No mobile'} · ${r['status'] ?? ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: id > 0 ? () => _employeeLoginDialog(r) : null,
                  );
                }).toList(),
              );
            },
          ),
        const SizedBox(height: 12),
        if (app.canAny(const [
          'administration.access.manage',
          'administration.audit.view',
        ]))
          _futureCard(
            title: 'Backend Diagnostics',
            action: app.can('administration.access.manage')
                ? TextButton.icon(
                    onPressed: () async {
                      final ok = await _confirm(
                        'Run backend cleanup?',
                        'Run maintenance cleanup for backend housekeeping? Continue only when diagnostics or maintenance requires it.',
                      );
                      if (ok != true) return;
                      await _post(ApiPaths.maintenanceCleanup, const {});
                    },
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('Cleanup'),
                  )
                : null,
            future: api.get(ApiPaths.diagnostics),
            builder: (data) => SelectableText(_pretty(data)),
          ),
        if (app.can('administration.access.manage')) ...[
          const SizedBox(height: 12),
          _futureCard(
            title: 'App Version Policy',
            future: _versionPolicy(),
            builder: (data) => SelectableText(_pretty(data)),
          ),
        ],
      ],
    );
  }

  Future<Map<String, dynamic>> _versionPolicy() async {
    final info = await PackageInfo.fromPlatform();
    final build = int.tryParse(info.buildNumber) ?? 0;
    final data = await ref.read(apiClientProvider).get(
          ApiPaths.appVersionPolicy,
          query: {'client_build': build},
          authenticated: false,
        );
    return Map<String, dynamic>.from((data as Map?) ?? const {});
  }

  Widget _futureCard({
    required String title,
    required Future<dynamic> future,
    required Widget Function(dynamic data) builder,
    Widget? action,
  }) {
    return Card(
      key: ValueKey('$title-$refresh'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (action != null) action,
              ],
            ),
            const Divider(),
            FutureBuilder<dynamic>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return _emptyInline(
                    Icons.cloud_off_outlined,
                    'Could not load this section',
                    UiError.message(snapshot.error!),
                  );
                }
                return builder(snapshot.data);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String value) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      );

  Future<void> _createHoliday(AppState app) async {
    final name = TextEditingController();
    final date = TextEditingController(text: _today());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Holiday'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: date,
              decoration: const InputDecoration(labelText: 'Date YYYY-MM-DD'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Holiday Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _post(ApiPaths.holidays, {
        if (app.currentBranchId != null) 'branch_id': app.currentBranchId,
        'holiday_date': date.text.trim(),
        'name': name.text.trim(),
      });
    }
    name.dispose();
    date.dispose();
  }

  Future<void> _uploadDocument(int employeeId) async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: kIsWeb,
    );
    final file = picked?.files.single;
    if (file == null) return;
    if (!kIsWeb && file.path == null) return;
    if (kIsWeb && file.bytes == null) {
      _msg('Browser could not read the selected file. Please select it again.');
      return;
    }
    final type = TextEditingController(text: 'employee_document');
    final title = TextEditingController(text: file.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload Employee Document'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: type,
              decoration: const InputDecoration(labelText: 'Document Type'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        final api = ref.read(apiClientProvider);
        final fields = {
          'document_type': type.text.trim(),
          'title': title.text.trim(),
        };
        if (kIsWeb) {
          await api.uploadBytes(
            ApiPaths.employeeDocumentUpload(employeeId),
            bytes: file.bytes!,
            filename: file.name,
            fields: fields,
          );
        } else {
          await api.uploadFile(
            ApiPaths.employeeDocumentUpload(employeeId),
            filePath: file.path!,
            filename: file.name,
            fields: fields,
          );
        }
        _msg('Document uploaded.');
        if (mounted) setState(() => refresh++);
      } catch (e) {
        _msg(UiError.message(e));
      }
    }
    type.dispose();
    title.dispose();
  }

  Future<List<Map<String, dynamic>>> _employeeChoices() async {
    final app = ref.read(appStateProvider);
    final data = await ref.read(apiClientProvider).get(
      ApiPaths.employees,
      query: {
        if (app.currentBranchId != null) 'branch_id': app.currentBranchId,
        'status': 'active',
        'limit': 200,
      },
    );
    return _rows(data);
  }

  Future<void> _createTask() async {
    try {
      final employees = await _employeeChoices();
      if (!mounted || employees.isEmpty) return;
      var employeeId = int.tryParse('${employees.first['id']}') ?? 0;
      final title = TextEditingController();
      final due = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('New Task'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: employeeId,
                  items: employees
                      .map(
                        (e) => DropdownMenuItem<int>(
                          value: int.tryParse('${e['id']}') ?? 0,
                          child: Text(
                            '${e['full_name']} (${e['employee_code']})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setLocal(() => employeeId = v ?? employeeId),
                  decoration: const InputDecoration(labelText: 'Assign To'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Task Title'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: due,
                  decoration: const InputDecoration(
                    labelText: 'Due At (optional ISO date/time)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        await _post(ApiPaths.tasks, {
          'assigned_employee_id': employeeId,
          'title': title.text.trim(),
          if (due.text.trim().isNotEmpty) 'due_at': due.text.trim(),
        });
      }
      title.dispose();
      due.dispose();
    } catch (e) {
      _msg(UiError.message(e));
    }
  }

  Future<void> _createAnnouncement(AppState app) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish Announcement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: body,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Message'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _post(ApiPaths.announcements, {
        if (app.currentBranchId != null) 'branch_id': app.currentBranchId,
        'title': title.text.trim(),
        'body': body.text.trim(),
      });
    }
    title.dispose();
    body.dispose();
  }

  Future<void> _createNotification() async {
    try {
      final employees = await _employeeChoices();
      if (!mounted || employees.isEmpty) return;
      var employeeId = int.tryParse('${employees.first['id']}') ?? 0;
      final title = TextEditingController();
      final body = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Send Notification'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: employeeId,
                  items: employees
                      .map(
                        (e) => DropdownMenuItem<int>(
                          value: int.tryParse('${e['id']}') ?? 0,
                          child: Text(
                            '${e['full_name']} (${e['employee_code']})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setLocal(() => employeeId = v ?? employeeId),
                  decoration: const InputDecoration(labelText: 'Employee'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: body,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Message'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Send'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        await _post(ApiPaths.notifications, {
          'employee_id': employeeId,
          'title': title.text.trim(),
          'body': body.text.trim(),
          'type': 'general',
        });
      }
      title.dispose();
      body.dispose();
    } catch (e) {
      _msg(UiError.message(e));
    }
  }

  Future<void> _employeeLoginDialog(Map<String, dynamic> employee) async {
    final id = int.tryParse('${employee['id']}') ?? 0;
    if (id < 1) return;
    try {
      final status = Map<String, dynamic>.from(
        await ref.read(apiClientProvider).get(ApiPaths.employeeLoginStatus(id))
            as Map,
      );
      if (!mounted) return;
      final password = TextEditingController();
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${employee['full_name']} · App Login'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Login enabled: ${status['login_enabled'] ?? false}',
                  ),
                  subtitle: Text(
                    'Active sessions: ${status['active_sessions'] ?? 0}',
                  ),
                ),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Set / Reset Password',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Share the password with the employee only through an approved secure channel.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final ok = await _confirm(
                  'Revoke employee sessions?',
                  'All active app sessions for this employee will be signed out. Continue?',
                );
                if (ok != true) return;
                try {
                  await ref.read(apiClientProvider).post(
                    ApiPaths.employeeRevokeSessions(id),
                    data: const {},
                  );
                  if (mounted) Navigator.pop(context);
                  _msg('Employee sessions revoked.');
                } catch (e) {
                  _msg(UiError.message(e));
                }
              },
              child: const Text('Revoke Sessions'),
            ),
            FilledButton(
              onPressed: () async {
                if (password.text.length < 8) {
                  _msg('Password must contain at least 8 characters.');
                  return;
                }
                try {
                  await ref.read(apiClientProvider).post(
                    ApiPaths.employeeCredentials(id),
                    data: {'password': password.text},
                  );
                  if (mounted) Navigator.pop(context);
                  _msg('Login password updated.');
                  setState(() => refresh++);
                } catch (e) {
                  _msg(UiError.message(e));
                }
              },
              child: const Text('Save Password'),
            ),
          ],
        ),
      );
      password.dispose();
    } catch (e) {
      _msg(UiError.message(e));
    }
  }

  Future<void> _post(
    String path,
    Map<String, dynamic> data, {
    bool idempotent = true,
  }) async {
    try {
      await ref
          .read(apiClientProvider)
          .post(path, data: data, idempotent: idempotent);
      _msg('Saved successfully.');
      if (mounted) setState(() => refresh++);
    } catch (e) {
      _msg(UiError.message(e));
    }
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );

  void _msg(String value) {
    if (!mounted) return;
    setState(() => message = value);
  }

  static List<Map<String, dynamic>> _rows(dynamic value) =>
      ((value as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  static String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static String _pretty(dynamic value) {
    if (value is Map) {
      return value.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    }
    if (value is List) return value.map((e) => '$e').join('\n');
    return '$value';
  }
}
