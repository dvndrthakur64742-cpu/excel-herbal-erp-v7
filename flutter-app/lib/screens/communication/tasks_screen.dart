import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../theme/excel_brand.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key, this.initialTasks});

  final List<Map<String, dynamic>>? initialTasks;

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  int? completingId;
  String? message;
  late List<Map<String, dynamic>> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = _copyTasks(widget.initialTasks);
  }

  @override
  void didUpdateWidget(covariant TasksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initialTasks, widget.initialTasks)) {
      _tasks = _copyTasks(widget.initialTasks);
    }
  }

  static List<Map<String, dynamic>> _copyTasks(
    List<Map<String, dynamic>>? rows,
  ) =>
      (rows ?? const <Map<String, dynamic>>[])
          .map(Map<String, dynamic>.from)
          .toList();

  @override
  Widget build(BuildContext context) {
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
          child: _tasks.isEmpty
              ? const Center(child: Text('No pending tasks.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tasks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final task = _tasks[i];
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
          _tasks.removeWhere((task) => int.tryParse('${task['id']}') == id);
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
