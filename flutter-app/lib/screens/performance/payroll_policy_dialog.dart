import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';

Future<String?> showPayrollPolicyDialog(
  BuildContext context,
  WidgetRef ref, {
  required bool canManage,
}) async {
  final api = ref.read(apiClientProvider);
  final raw = await api.get(ApiPaths.payrollPolicy);
  final data = Map<String, dynamic>.from(raw as Map);
  final source = Map<String, dynamic>.from(
    (data['leave_types'] as Map?) ?? const {},
  );
  final leaveTypes = <String, bool>{
    for (final entry in source.entries)
      entry.key.toUpperCase(): entry.value == true,
  };
  final reason = TextEditingController();
  String? validation;
  var saving = false;

  if (!context.mounted) return null;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setLocal) {
        Future<void> addLeaveType() async {
          final code = TextEditingController();
          String? localError;
          final value = await showDialog<String>(
            context: dialogContext,
            builder: (context) => StatefulBuilder(
              builder: (context, setCodeState) => AlertDialog(
                title: const Text('Add Leave Type'),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: code,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Leave Type Code',
                          hintText: 'Example: CASUAL_LEAVE',
                        ),
                      ),
                      if (localError != null) ...[
                        const SizedBox(height: 8),
                        Text(localError!),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final clean = code.text
                          .trim()
                          .toUpperCase()
                          .replaceAll(RegExp(r'\s+'), '_');
                      if (clean.isEmpty || clean.length > 50) {
                        setCodeState(
                          () => localError =
                              'Leave type code must contain 1–50 characters.',
                        );
                      } else if (leaveTypes.containsKey(clean)) {
                        setCodeState(
                          () => localError =
                              'This leave type already exists.',
                        );
                      } else {
                        Navigator.pop(context, clean);
                      }
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
            ),
          );
          code.dispose();
          if (value != null) {
            setLocal(() => leaveTypes[value] = false);
          }
        }

        Future<void> save() async {
          if (!canManage || saving) return;
          final why = reason.text.trim();
          if (why.length < 5) {
            setLocal(
              () => validation =
                  'A change reason of at least 5 characters is required.',
            );
            return;
          }
          setLocal(() {
            saving = true;
            validation = null;
          });
          try {
            await api.post(
              ApiPaths.payrollPolicy,
              data: {
                'leave_types': leaveTypes,
                'reason': why,
              },
            );
            if (dialogContext.mounted) {
              Navigator.pop(
                dialogContext,
                'Payroll leave policy updated.',
              );
            }
          } catch (e) {
            setLocal(() {
              saving = false;
              validation = UiError.message(e);
            });
          }
        }

        final entries = leaveTypes.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));

        return AlertDialog(
          title: const Text('Payroll Leave Policy'),
          content: SizedBox(
            width: 640,
            height: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Basis: scheduled working days',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Each leave type must be explicitly classified as paid or unpaid. Payroll calculation uses this server-owned policy.',
                ),
                if (canManage) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: saving ? null : addLeaveType,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Leave Type'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: entries.isEmpty
                      ? const Center(
                          child: Text(
                            'No leave types are configured yet.',
                          ),
                        )
                      : ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return SwitchListTile(
                              value: entry.value,
                              title: Text(
                                entry.key.replaceAll('_', ' '),
                              ),
                              subtitle: Text(
                                entry.value
                                    ? 'Paid leave'
                                    : 'Unpaid leave',
                              ),
                              onChanged: canManage && !saving
                                  ? (value) => setLocal(
                                        () => leaveTypes[entry.key] = value,
                                      )
                                  : null,
                              secondary: canManage
                                  ? IconButton(
                                      tooltip: 'Remove leave type',
                                      onPressed: saving
                                          ? null
                                          : () => setLocal(
                                                () => leaveTypes.remove(
                                                  entry.key,
                                                ),
                                              ),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                      ),
                                    )
                                  : null,
                            );
                          },
                        ),
                ),
                if (canManage) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: reason,
                    enabled: !saving,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Policy Change Reason',
                    ),
                  ),
                ],
                if (validation != null) ...[
                  const SizedBox(height: 8),
                  Text(validation!),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            if (canManage)
              FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Saving…' : 'Save Policy'),
              ),
          ],
        );
      },
    ),
  );
  reason.dispose();
  return result;
}
