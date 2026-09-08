from pathlib import Path

# ERP Tools destructive/admin confirmations.
tools = Path('flutter-app/lib/screens/tools/erp_tools_screen.dart')
text = tools.read_text()

old = """                            onPressed: () =>
                                _post(ApiPaths.holidayDeactivate(id), const {}),
"""
new = """                            onPressed: () async {
                              final ok = await _confirm(
                                'Deactivate holiday?',
                                'Ye holiday active list se deactivate ho jayega. Continue?',
                              );
                              if (ok != true) return;
                              await _post(
                                ApiPaths.holidayDeactivate(id),
                                const {},
                              );
                            },
"""
if old not in text:
    raise SystemExit('holiday deactivate anchor not found')
text = text.replace(old, new, 1)

old = """                    onPressed: () =>
                        _post(ApiPaths.maintenanceCleanup, const {}),
"""
new = """                    onPressed: () async {
                      final ok = await _confirm(
                        'Run backend cleanup?',
                        'Maintenance cleanup backend data housekeeping run karega. Sirf jab diagnostics/maintenance ke liye zaroori ho tab continue karein.',
                      );
                      if (ok != true) return;
                      await _post(ApiPaths.maintenanceCleanup, const {});
                    },
"""
if old not in text:
    raise SystemExit('maintenance cleanup anchor not found')
text = text.replace(old, new, 1)

old = """              onPressed: () async {
                try {
                  await ref
                      .read(apiClientProvider)
                      .post(
                        ApiPaths.employeeRevokeSessions(id),
                        data: const {},
                      );
"""
new = """              onPressed: () async {
                final ok = await _confirm(
                  'Revoke employee sessions?',
                  'Is employee ke sab active app sessions logout ho jayenge. Continue?',
                );
                if (ok != true) return;
                try {
                  await ref
                      .read(apiClientProvider)
                      .post(
                        ApiPaths.employeeRevokeSessions(id),
                        data: const {},
                      );
"""
if old not in text:
    raise SystemExit('employee revoke sessions anchor not found')
text = text.replace(old, new, 1)
tools.write_text(text)

# Finance reversal execution confirmation.
admin = Path('flutter-app/lib/screens/administration/administration_screen.dart')
text = admin.read_text()
old = """                onTap: () => _post(ApiPaths.reversalExecute(id), const {}),
"""
new = """                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Execute approved reversal?'),
                      content: const Text(
                        'Ye stock, outstanding, journal aur audit-linked reversal execute karega. Is action ko sirf approved reversal ke liye continue karein.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Execute Reversal'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await _post(ApiPaths.reversalExecute(id), const {});
                  }
                },
"""
if old not in text:
    raise SystemExit('reversal execute anchor not found')
text = text.replace(old, new, 1)
admin.write_text(text)
