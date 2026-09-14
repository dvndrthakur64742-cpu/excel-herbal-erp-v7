import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../theme/excel_brand.dart';
import '../../widgets/async_panel.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  int refresh = 0;
  int? completingId;
  String? message;

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiClientProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Tasks', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 3),
                Text(
                  'Pending work assigned to you. Open a task to review its context.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ExcelBrand.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                message!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        Expanded(
          child: AsyncPanel(
            key: ValueKey(refresh),
            future: api.get(ApiPaths.communicationSummary),
            builder: (context, data) {
              final d = Map<String, dynamic>.from(data as Map);
              final tasks = ((d['tasks'] as List?) ?? const [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
              if (tasks.isEmpty) {
                return const Center(child: Text('No pending tasks.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: tasks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final task = tasks[i];
                  final id = int.parse('${task['id']}');
                  final busy = completingId == id;
                  final due = task['due_at'] == null
                      ? 'No due date'
                      : BusinessFormat.dateTime(task['due_at']);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: const BoxDecoration(
                              color: ExcelBrand.primarySoft,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.task_alt_outlined,
                              color: ExcelBrand.primaryDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${task['title'] ?? 'Task'}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${BusinessFormat.value('type', task['type'] ?? 'task')} · $due',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Mark complete',
                            onPressed: busy
                                ? null
                                : () => _complete(
                                    id,
                                    '${task['title'] ?? 'Task'}',
                                  ),
                            icon: busy
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _complete(int id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Task?'),
        content: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      completingId = id;
      message = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .post(ApiPaths.taskComplete(id), data: const {});
      if (mounted) {
        setState(() {
          completingId = null;
          message = 'Task completed.';
          refresh++;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          completingId = null;
          message = UiError.message(e);
        });
      }
    }
  }
}
