import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../theme/excel_brand.dart';

class EmployeeDesignationsScreen extends ConsumerStatefulWidget {
  const EmployeeDesignationsScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  final int employeeId;
  final String employeeName;

  @override
  ConsumerState<EmployeeDesignationsScreen> createState() =>
      _EmployeeDesignationsScreenState();
}

class _EmployeeDesignationsScreenState
    extends ConsumerState<EmployeeDesignationsScreen> {
  int refresh = 0;
  String? message;

  static const reportingCategories = <String, String>{
    '': 'Automatic from primary designation',
    'FIELD_EXECUTIVE': 'Field Executive',
    'ASM': 'ASM',
    'SM': 'SM',
    'BRANCH_MANAGER': 'Branch Manager',
    'REGIONAL': 'Regional',
    'SENIOR_MANAGEMENT': 'Senior Management',
    'SYSTEM_ADMIN': 'System Admin',
  };

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final canManage = app.can('organization.employee.manage');

    return Scaffold(
      appBar: AppBar(title: const Text('Designation & Reporting')),
      body: FutureBuilder<List<dynamic>>(
        key: ValueKey(refresh),
        future: _load(canManage),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              message: UiError.message(snapshot.error!),
              onRetry: () => setState(() => refresh++),
            );
          }

          final data = snapshot.data ?? const [];
          final detail = data.isNotEmpty && data[0] is Map
              ? Map<String, dynamic>.from(data[0] as Map)
              : <String, dynamic>{};
          final master = data.length > 1 && data[1] is List
              ? (data[1] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList(growable: false)
              : <Map<String, dynamic>>[];
          final assignmentRows = ((detail['additional_designations'] as List?) ??
                  const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(growable: false);
          final names = <String, String>{
            for (final d in master)
              '${d['code'] ?? ''}': '${d['name'] ?? d['code'] ?? ''}',
          };
          final primary = '${detail['primary_designation_code'] ?? '—'}';
          final explicitReporting =
              '${detail['reporting_designation_code'] ?? ''}'.trim();
          final effectiveReporting =
              '${detail['reporting_category'] ?? ''}'.trim();

          return RefreshIndicator(
            onRefresh: () async => setState(() => refresh++),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.employeeName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Primary authority, reporting grouping and extra responsibilities are kept separate.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: ExcelBrand.muted),
                ),
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
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
                ],
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: const Text('Primary Designation'),
                        subtitle: Text(
                          _designationLabel(primary, names[primary]),
                        ),
                        trailing: const Chip(label: Text('AUTHORITY')),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.account_tree_outlined),
                        title: const Text('Reporting Category'),
                        subtitle: Text(
                          reportingCategories[effectiveReporting] ??
                              effectiveReporting,
                        ),
                        trailing: canManage
                            ? IconButton(
                                tooltip: 'Change reporting category',
                                onPressed: () => _changeReportingCategory(
                                  explicitReporting,
                                ),
                                icon: const Icon(Icons.edit_outlined),
                              )
                            : null,
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Text(
                          'Reporting Category is a reporting/dashboard grouping only. It does not grant role permissions or branch authority.',
                          style: TextStyle(color: ExcelBrand.muted),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Additional / Temporary Designations',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (canManage)
                      FilledButton.tonalIcon(
                        onPressed: () => _addAssignment(master, primary),
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Same primary designation or overlapping duplicate date ranges are blocked by the server.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: ExcelBrand.muted),
                ),
                const SizedBox(height: 10),
                if (assignmentRows.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: Text('No additional designation assignments.'),
                      ),
                    ),
                  )
                else
                  for (final row in assignmentRows)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          '${row['assignment_type']}' == 'temporary'
                              ? Icons.schedule_outlined
                              : Icons.add_moderator_outlined,
                        ),
                        title: Text(
                          _designationLabel(
                            '${row['designation_code'] ?? ''}',
                            names['${row['designation_code'] ?? ''}'],
                          ),
                        ),
                        subtitle: Text(
                          '${_typeLabel('${row['assignment_type'] ?? ''}')} · ${_period(row)}',
                        ),
                        trailing: (canManage && row['active'] != 0)
                            ? IconButton(
                                tooltip: 'Deactivate assignment',
                                onPressed: () => _deactivate(row),
                                icon: const Icon(Icons.block_outlined),
                              )
                            : Chip(
                                label: Text(
                                  row['active'] == 0 ? 'INACTIVE' : 'ACTIVE',
                                ),
                              ),
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<List<dynamic>> _load(bool canManage) async {
    final api = ref.read(apiClientProvider);
    final detail = await api.get(ApiPaths.employeeDesignations(widget.employeeId));
    dynamic master = const <dynamic>[];
    if (canManage) {
      try {
        master = await api.get(ApiPaths.designations);
      } catch (_) {
        master = const <dynamic>[];
      }
    }
    return [detail, master];
  }

  Future<void> _changeReportingCategory(String current) async {
    var selected = reportingCategories.containsKey(current) ? current : '';
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reporting Category'),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final entry in reportingCategories.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (v) => setDialogState(() => selected = v ?? ''),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (value == null) return;
    await _post(
      ApiPaths.employeeUpdate(widget.employeeId),
      {'reporting_designation_code': value},
      success: 'Reporting category updated without changing authority.',
    );
  }

  Future<void> _addAssignment(
    List<Map<String, dynamic>> master,
    String primary,
  ) async {
    final choices = master
        .where((d) => '${d['code'] ?? ''}'.trim().isNotEmpty)
        .where((d) => '${d['code']}'.toUpperCase() != primary.toUpperCase())
        .toList(growable: false);
    if (choices.isEmpty) {
      setState(() => message = 'No additional designation is available.');
      return;
    }

    var code = '${choices.first['code']}';
    var type = 'additional';
    final from = TextEditingController(
      text: ref.read(appStateProvider).businessDate,
    );
    final to = TextEditingController();

    final payload = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Designation Assignment'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: code,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Designation'),
                  items: [
                    for (final d in choices)
                      DropdownMenuItem(
                        value: '${d['code']}',
                        child: Text(
                          _designationLabel('${d['code']}', '${d['name'] ?? ''}'),
                        ),
                      ),
                  ],
                  onChanged: (v) => setDialogState(() => code = v ?? code),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Assignment type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'additional',
                      child: Text('Additional'),
                    ),
                    DropdownMenuItem(
                      value: 'temporary',
                      child: Text('Temporary'),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => type = v ?? type),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: from,
                  decoration: const InputDecoration(
                    labelText: 'Effective From',
                    hintText: 'YYYY-MM-DD',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: to,
                  decoration: const InputDecoration(
                    labelText: 'Effective To (optional)',
                    hintText: 'YYYY-MM-DD',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'designation_code': code,
                'assignment_type': type,
                'effective_from': from.text.trim(),
                'effective_to': to.text.trim(),
              }),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    from.dispose();
    to.dispose();
    if (payload == null) return;
    await _post(
      ApiPaths.employeeDesignations(widget.employeeId),
      payload,
      success: 'Designation assignment added. Authority remains unchanged.',
    );
  }

  Future<void> _deactivate(Map<String, dynamic> row) async {
    final id = int.tryParse('${row['id'] ?? ''}') ?? 0;
    if (id <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deactivate designation?'),
        content: const Text(
          'This removes the additional/temporary responsibility assignment. Primary role and branch authority are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _post(
      ApiPaths.employeeDesignationDeactivate(widget.employeeId, id),
      const {},
      success: 'Designation assignment deactivated.',
    );
  }

  Future<void> _post(
    String path,
    Map<String, dynamic> payload, {
    required String success,
  }) async {
    try {
      await ref.read(apiClientProvider).post(path, data: payload);
      if (!mounted) return;
      setState(() {
        message = success;
        refresh++;
      });
      final selfId = int.tryParse('${ref.read(appStateProvider).employee['id']}');
      if (selfId == widget.employeeId) {
        await ref.read(appStateProvider.notifier).refreshBootstrap();
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  String _designationLabel(String code, String? name) {
    final cleanName = '${name ?? ''}'.trim();
    if (cleanName.isEmpty || cleanName.toUpperCase() == code.toUpperCase()) {
      return code.isEmpty ? '—' : code;
    }
    return '$cleanName ($code)';
  }

  String _typeLabel(String type) =>
      type == 'temporary' ? 'Temporary' : 'Additional';

  String _period(Map<String, dynamic> row) {
    final from = '${row['effective_from'] ?? ''}'.trim();
    final to = '${row['effective_to'] ?? ''}'.trim();
    if (to.isEmpty || to == 'null') return '$from → ongoing';
    return '$from → $to';
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}
