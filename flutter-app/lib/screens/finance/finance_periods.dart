part of 'finance_screen.dart';

extension _FinancePeriodsFeature on _FinanceScreenState {
  Widget _periods(AppState app, dynamic api) {
    if (!app.can('finance.period.manage'))
      return const Center(
        child: Text(
          'Accounting Period control aapke role ke liye authorised nahi hai.',
        ),
      );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _closePeriod,
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Close Accounting Period'),
            ),
          ),
        ),
        Expanded(
          child: AsyncPanel(
            key: ValueKey('periods-$refresh'),
            future: api.get(ApiPaths.periods),
            emptyMessage: 'Koi accounting period record nahi hai.',
            builder: (context, data) => V8RecordWorkspace(
              title: 'Accounting Periods',
              subtitle: 'Company-wide period controls and their status.',
              contextLabel: 'Authorised finance records',
              recordType: 'accounting_period',
              rows: _rows(data),
              onTap: _periodAction,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _closePeriod() async {
    final app = ref.read(appStateProvider);
    final from = TextEditingController(text: app.businessMonthStart);
    final to = TextEditingController(text: app.businessDate);
    String? formError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Close Accounting Period'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BusinessDateField(
                  controller: from,
                  label: 'Period From',
                ),
                const SizedBox(height: 10),
                BusinessDateField(
                  controller: to,
                  label: 'Period To',
                ),
                if (formError != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final error = TransactionGuardrails.dateRange(
                  from.text.trim(),
                  to.text.trim(),
                );
                if (error != null) {
                  setLocal(() => formError = error);
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Close Period'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _post(
          ApiPaths.periodClose,
          {
            'date_from': from.text.trim(),
            'date_to': to.text.trim(),
          },
          closeSheet: false);
    }
    from.dispose();
    to.dispose();
  }

  void _periodAction(Map<String, dynamic> row) {
    if ('${row['status']}' != 'closed') return;
    _reasonPost(
      ApiPaths.periodReopen(int.parse('${row['id']}')),
      'Accounting Period reopen reason',
    );
  }

}
