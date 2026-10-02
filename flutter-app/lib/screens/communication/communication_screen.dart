import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/module_workspace.dart';
import 'tasks_screen.dart';

class CommunicationScreen extends ConsumerStatefulWidget {
  const CommunicationScreen({super.key});

  @override
  ConsumerState<CommunicationScreen> createState() =>
      _CommunicationScreenState();
}

class _CommunicationScreenState extends ConsumerState<CommunicationScreen> {
  int refresh = 0;
  String? message;

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiClientProvider);
    final app = ref.watch(appStateProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Communication'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Tasks'),
              Tab(text: 'Announcements'),
              Tab(text: 'Notifications'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: ModuleWorkspaceHeader(
                  title: 'Communication',
                  subtitle:
                      'Tasks, announcements and notifications in one workspace.',
                  icon: Icons.forum_outlined,
                  contextLabel: 'Business date · ${app.businessDate}',
                ),
              ),
              if (app.can('communication.manage'))
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: BranchSelector(),
                ),
              if (app.can('communication.manage'))
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ModuleActionPanel(
                    title: 'Management Actions',
                    subtitle:
                        'Create team tasks and publish authorised communication from this single workspace.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _createTask,
                        icon: const Icon(Icons.add_task_rounded),
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
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _Message(text: message!),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 7),
                child: ModuleSectionHeader(
                  title: 'Communication Workspace',
                  subtitle:
                      'Review assigned work and stay current with business updates.',
                ),
              ),
              Expanded(
                child: AsyncPanel(
                key: ValueKey(refresh),
                future: api.get(ApiPaths.communicationSummary),
                builder: (context, data) {
                  final summary = Map<String, dynamic>.from(data as Map);
                  final tasks =
                      ((summary['tasks'] as List?) ?? const [])
                          .map((e) => Map<String, dynamic>.from(e as Map))
                          .toList();
                  final announcements =
                      ((summary['announcements'] as List?) ?? const [])
                          .map((e) => Map<String, dynamic>.from(e as Map))
                          .toList();
                  final notifications =
                      ((summary['notifications'] as List?) ?? const [])
                          .map((e) => Map<String, dynamic>.from(e as Map))
                          .toList();
                  return TabBarView(
                    children: [
                      TasksScreen(initialTasks: tasks),
                      _announcements(announcements),
                      _notifications(notifications),
                    ],
                  );
                },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _announcements(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Center(child: Text('No active announcements.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final row = rows[i];
        final acknowledged = '${row['acknowledged_at'] ?? ''}'
            .trim()
            .isNotEmpty;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.campaign_outlined,
                      color: ExcelBrand.primaryDark,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${row['title'] ?? 'Announcement'}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (acknowledged) const Chip(label: Text('Acknowledged')),
                  ],
                ),
                if ('${row['body'] ?? ''}'.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('${row['body']}'),
                ],
                const SizedBox(height: 10),
                Text(
                  row['published_at'] == null
                      ? ''
                      : BusinessFormat.dateTime(row['published_at']),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!acknowledged) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => _acknowledge(int.parse('${row['id']}')),
                      icon: const Icon(Icons.done_rounded),
                      label: const Text('Acknowledge'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _notifications(List<Map<String, dynamic>> rows) {
    final unread = rows
        .where((r) => '${r['read_at'] ?? ''}'.trim().isEmpty)
        .length;
    return Column(
      children: [
        if (unread > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$unread unread',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: _readAll,
                  icon: const Icon(Icons.done_all_rounded),
                  label: const Text('Mark all read'),
                ),
              ],
            ),
          ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No notifications.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final row = rows[i];
                    final read = '${row['read_at'] ?? ''}'.trim().isNotEmpty;
                    return Card(
                      color: read ? null : ExcelBrand.primarySoft,
                      child: ListTile(
                        leading: Icon(
                          read
                              ? Icons.notifications_none
                              : Icons.notifications_active_outlined,
                        ),
                        title: Text('${row['title'] ?? 'Notification'}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ('${row['body'] ?? ''}'.trim().isNotEmpty)
                              Text('${row['body']}'),
                            const SizedBox(height: 3),
                            Text(BusinessFormat.dateTime(row['created_at'])),
                          ],
                        ),
                        trailing: read
                            ? null
                            : IconButton(
                                tooltip: 'Mark read',
                                onPressed: () =>
                                    _readOne(int.parse('${row['id']}')),
                                icon: const Icon(Icons.done_rounded),
                              ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _employeeChoices() async {
    final app = ref.read(appStateProvider);
    final branchId = app.currentBranchId;
    if (branchId == null) return const [];
    final data = await ref.read(apiClientProvider).get(
      ApiPaths.employees,
      query: {
        'branch_id': branchId,
        'status': 'active',
        'limit': 200,
      },
    );
    return ((data as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<void> _createTask() async {
    try {
      final employees = await _employeeChoices();
      if (!mounted) return;
      if (employees.isEmpty) {
        setState(() => message = 'No active employee is available in the selected branch.');
        return;
      }
      var employeeId = int.tryParse('${employees.first['id']}') ?? 0;
      final title = TextEditingController();
      DateTime? dueAt;
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setLocal) => AlertDialog(
            title: const Text('New Task'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: employeeId,
                    isExpanded: true,
                    items: employees
                        .map(
                          (e) => DropdownMenuItem<int>(
                            value: int.tryParse('${e['id']}') ?? 0,
                            child: Text(
                              '${e['full_name']} (${e['employee_code']})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setLocal(() => employeeId = value ?? employeeId),
                    decoration: const InputDecoration(labelText: 'Assign To'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Task Title'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dueAt == null
                              ? 'No due date'
                              : 'Due: ${BusinessFormat.dateTime(dueAt!.toIso8601String())}',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final picked = await _pickDueAt(dueAt);
                          if (picked != null) setLocal(() => dueAt = picked);
                        },
                        icon: const Icon(Icons.event_outlined),
                        label: Text(dueAt == null ? 'Set due' : 'Change'),
                      ),
                      if (dueAt != null)
                        IconButton(
                          tooltip: 'Clear due date',
                          onPressed: () => setLocal(() => dueAt = null),
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (employeeId < 1 || title.text.trim().isEmpty) return;
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      );
      final taskTitle = title.text.trim();
      title.dispose();
      if (ok != true || taskTitle.isEmpty || employeeId < 1) return;
      await _postAdmin(
        ApiPaths.tasks,
        {
          'assigned_employee_id': employeeId,
          'title': taskTitle,
          if (dueAt != null) 'due_at': dueAt!.toUtc().toIso8601String(),
        },
        'Task created.',
      );
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<DateTime?> _pickDueAt(DateTime? current) async {
    final now = DateTime.now();
    final initial = current ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? DateTime(
        date.year,
        date.month,
        date.day,
        18,
      )),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _createAnnouncement(AppState app) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Publish Announcement'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: body,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Message'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty || body.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    final announcementTitle = title.text.trim();
    final announcementBody = body.text.trim();
    title.dispose();
    body.dispose();
    if (ok != true || announcementTitle.isEmpty || announcementBody.isEmpty) return;
    await _postAdmin(
      ApiPaths.announcements,
      {
        if (app.currentBranchId != null) 'branch_id': app.currentBranchId,
        'title': announcementTitle,
        'body': announcementBody,
      },
      'Announcement published.',
    );
  }

  Future<void> _createNotification() async {
    try {
      final employees = await _employeeChoices();
      if (!mounted) return;
      if (employees.isEmpty) {
        setState(() => message = 'No active employee is available in the selected branch.');
        return;
      }
      var employeeId = int.tryParse('${employees.first['id']}') ?? 0;
      final title = TextEditingController();
      final body = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setLocal) => AlertDialog(
            title: const Text('Send Notification'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: employeeId,
                    isExpanded: true,
                    items: employees
                        .map(
                          (e) => DropdownMenuItem<int>(
                            value: int.tryParse('${e['id']}') ?? 0,
                            child: Text(
                              '${e['full_name']} (${e['employee_code']})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setLocal(() => employeeId = value ?? employeeId),
                    decoration: const InputDecoration(labelText: 'Employee'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: body,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (employeeId < 1 || title.text.trim().isEmpty) return;
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Send'),
              ),
            ],
          ),
        ),
      );
      final notificationTitle = title.text.trim();
      final notificationBody = body.text.trim();
      title.dispose();
      body.dispose();
      if (ok != true || notificationTitle.isEmpty || employeeId < 1) return;
      await _postAdmin(
        ApiPaths.notifications,
        {
          'employee_id': employeeId,
          'title': notificationTitle,
          'body': notificationBody,
          'type': 'general',
        },
        'Notification sent.',
      );
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _postAdmin(
    String path,
    Map<String, dynamic> data,
    String success,
  ) async {
    try {
      await ref.read(apiClientProvider).post(path, data: data);
      if (mounted) {
        setState(() {
          message = success;
          refresh++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _acknowledge(int id) =>
      _post(ApiPaths.announcementAcknowledge(id), 'Announcement acknowledged.');

  Future<void> _readOne(int id) =>
      _post(ApiPaths.notificationRead(id), 'Notification marked read.');

  Future<void> _readAll() =>
      _post(ApiPaths.notificationReadAll, 'Notifications marked read.');

  Future<void> _post(String path, String success) async {
    try {
      await ref.read(apiClientProvider).post(path, data: const {});
      if (mounted) {
        setState(() {
          message = success;
          refresh++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: ExcelBrand.primarySoft,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}
