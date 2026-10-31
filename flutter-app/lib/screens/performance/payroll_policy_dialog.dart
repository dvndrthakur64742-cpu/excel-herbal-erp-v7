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
  final result = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setLocal) {
        Future<void> addLeaveType() async {
          final code = TextEditingController();
          String? localError;
          final value = await showModalBottomSheet<String>(
            context: sheetContext,
            useSafeArea: true,
            isScrollControlled: true,
            builder: (addContext) => StatefulBuilder(
              builder: (context, setCodeState) => Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  MediaQuery.viewInsetsOf(addContext).bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Add Leave Type',
                            style: Theme.of(addContext)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(addContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: code,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Leave Type Code',
                        hintText: 'Example: CASUAL_LEAVE',
                        helperText: 'Spaces will be converted to underscores.',
                      ),
                    ),
                    if (localError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        localError!,
                        style: TextStyle(
                          color: Theme.of(addContext).colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(addContext),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
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
                                Navigator.pop(addContext, clean);
                              }
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Add Leave Type'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
            if (sheetContext.mounted) {
              Navigator.pop(
                sheetContext,
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

        return FractionallySizedBox(
          heightFactor: .94,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 10, 12),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Theme.of(sheetContext)
                            .colorScheme
                            .primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.policy_outlined,
                        color: Theme.of(sheetContext)
                            .colorScheme
                            .onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Payroll Leave Policy',
                            style: Theme.of(sheetContext)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            canManage
                                ? 'Classify leave types and keep an audit reason.'
                                : 'View the server-owned leave classification.',
                            style: Theme.of(sheetContext).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: saving
                          ? null
                          : () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Text(
                      'Policy Basis',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(sheetContext)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'Payroll uses scheduled working days. Every leave type must be explicitly classified as paid or unpaid before payroll calculation.',
                      ),
                    ),
                    if (canManage) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: saving ? null : addLeaveType,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Leave Type'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Leave Types',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    if (entries.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 28,
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'No leave types are configured yet.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ...entries.map(
                        (entry) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: SwitchListTile(
                            value: entry.value,
                            title: Text(
                              entry.key.replaceAll('_', ' '),
                            ),
                            subtitle: Text(
                              entry.value ? 'Paid leave' : 'Unpaid leave',
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
                          ),
                        ),
                      ),
                    if (canManage) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Audit Reason',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: reason,
                        enabled: !saving,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Policy Change Reason',
                          helperText: 'Minimum 5 characters',
                        ),
                      ),
                    ],
                    if (validation != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        validation!,
                        style: TextStyle(
                          color: Theme.of(sheetContext).colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext).colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(sheetContext)
                            .colorScheme
                            .outlineVariant,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(sheetContext),
                          child: const Text('Close'),
                        ),
                      ),
                      if (canManage) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: saving ? null : save,
                            icon: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(
                              saving ? 'Saving…' : 'Save Policy',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  reason.dispose();
  return result;
}
