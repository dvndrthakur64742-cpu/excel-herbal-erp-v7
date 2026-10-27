part of 'finance_screen.dart';

extension _FinanceClosingFeature on _FinanceScreenState {
  Widget _closing(AppState app, dynamic api) {
    if (app.currentBranchId == null)
      return const Center(child: Text('Branch select karein.'));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (app.can('finance.branch_close'))
                FilledButton.tonalIcon(
                  onPressed: _preflight,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Preflight'),
                ),
              if (app.can('finance.branch_close'))
                FilledButton.icon(
                  onPressed: _closingDraft,
                  icon: const Icon(Icons.lock_clock_outlined),
                  label: const Text('Create Closing Draft'),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncPanel(
            key: ValueKey('closing-${app.currentBranchId}-$refresh'),
            future: api.get(
              ApiPaths.branchClosing,
              query: {'branch_id': app.currentBranchId},
            ),
            emptyMessage: 'Koi Branch Closing record nahi hai.',
            builder: (context, data) => V8RecordWorkspace(
              title: 'Branch Closing Register',
              subtitle: 'Review drafts and closed business dates.',
              contextLabel: app.currentBranchName,
              recordType: 'branch_closing',
              rows: _rows(data),
              onTap: _closingAction,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _preflight() async {
    final app = ref.read(appStateProvider);
    try {
      final r = await ref.read(apiClientProvider).get(
        ApiPaths.closingPreflight,
        query: {
          'branch_id': app.currentBranchId,
          'business_date': app.businessDate,
        },
      );
      if (mounted) _setFinanceState(() => message = 'Preflight: $r');
    } catch (e) {
      if (mounted) _setFinanceState(() => message = UiError.message(e));
    }
  }

  Future<void> _closingDraft() async {
    final app = ref.read(appStateProvider);
    try {
      final r = await ref.read(apiClientProvider).post(
        ApiPaths.branchClosing,
        data: {
          'branch_id': app.currentBranchId,
          'business_date': app.businessDate,
        },
      );
      if (mounted)
        _setFinanceState(() {
          message = 'Closing draft #${(r as Map)['id']} created.';
          refresh++;
        });
    } catch (e) {
      if (mounted) _setFinanceState(() => message = UiError.message(e));
    }
  }

  void _closingAction(Map<String, dynamic> row) {
    final app = ref.read(appStateProvider);
    final id = int.parse('${row['id']}');
    final status = '${row['status']}';
    if (status == 'draft' && app.can('finance.branch_close')) {
      showModalBottomSheet<void>(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(title: Text('Closing #$id · ${row['business_date']}')),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Close Branch Day'),
                onTap: () => _post(ApiPaths.closingClose(id), const {}),
              ),
            ],
          ),
        ),
      );
    } else if (status == 'closed' && app.can('finance.branch_reopen')) {
      _reasonPost(ApiPaths.closingReopen(id), 'Branch reopen reason');
    }
  }

}
