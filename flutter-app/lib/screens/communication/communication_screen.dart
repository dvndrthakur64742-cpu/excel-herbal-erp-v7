import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';
import '../../widgets/async_panel.dart';
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
