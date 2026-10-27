part of 'finance_screen.dart';

extension _FinanceBooksFeature on _FinanceScreenState {
  Widget _books(AppState app, dynamic api) => Column(
        children: [
          if (app.can('finance.account.manage'))
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _newLedger,
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: const Text('New Ledger'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _newExpenseHead,
                      icon: const Icon(Icons.category_outlined),
                      label: const Text('New Expense Head'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: AsyncPanel(
              key: ValueKey('tb-${app.currentBranchId}-$refresh'),
              future: api.get(
                ApiPaths.trialBalance,
                query: {
                  'to': app.businessDate,
                  if (app.currentBranchId != null)
                    'branch_id': app.currentBranchId,
                },
              ),
              builder: (context, data) => V8RecordWorkspace(
                  title: 'Trial Balance',
                  subtitle: 'Original accounting records through the selected business date.',
                  recordType: 'trial_balance',
                  contextLabel: app.currentBranchName,
                  rows: _rows(data),
                ),
            ),
          ),
        ],
      );

  Future<void> _newLedger() async {
    final code = TextEditingController();
    final name = TextEditingController();
    String type = 'asset';
    String subtype = 'bank';
    String? ledgerFormError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New Ledger'),
          scrollable: true,
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  decoration: const InputDecoration(labelText: 'Ledger Code'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Ledger Name'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Account Type'),
                  items: const [
                    'asset',
                    'liability',
                    'equity',
                    'income',
                    'expense',
                  ]
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(v.toUpperCase()),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() {
                    ledgerFormError = null;
                    type = v ?? 'asset';
                    if (type != 'asset' &&
                        const {'cash', 'bank', 'upi'}.contains(subtype))
                      subtype = '';
                  }),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: subtype.isEmpty ? null : subtype,
                  decoration: const InputDecoration(
                    labelText: 'Subtype (optional)',
                  ),
                  items: const [
                    'cash',
                    'bank',
                    'upi',
                    'receivable',
                    'inventory',
                    'payable',
                    'payroll_payable',
                    'sales',
                    'cogs',
                    'stock_variance',
                    'payroll',
                    'office',
                  ]
                      .map(
                        (v) => DropdownMenuItem(value: v, child: Text(v)),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() {
                    subtype = v ?? '';
                    ledgerFormError = null;
                  }),
                ),
                if (ledgerFormError != null) ...[
                  const SizedBox(height: 10),
                  Text(ledgerFormError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                final codeText = code.text.trim();
                final nameText = name.text.trim();
                if (codeText.isEmpty || nameText.isEmpty) {
                  setLocal(() => ledgerFormError =
                    'Ledger Code aur Ledger Name required hain.');
                  return;
                }
                if (codeText.length > 80 || nameText.length > 190) {
                  setLocal(() => ledgerFormError =
                    'Ledger Code max 80 aur Name max 190 characters rakhein.');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok == true)
      await _post(
          ApiPaths.financeAccounts,
          {
            'code': code.text.trim(),
            'name': name.text.trim(),
            'type': type,
            'subtype': subtype,
          },
          closeSheet: false);
    code.dispose();
    name.dispose();
  }

  Future<void> _newExpenseHead() async {
    try {
      final finance = Map<String, dynamic>.from(
        await ref.read(apiClientProvider).get(ApiPaths.financeBootstrap) as Map,
      );
      final accounts = ((finance['accounts'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => '${e['type']}' == 'expense')
          .toList();
      final code = TextEditingController();
      final name = TextEditingController();
      int? accountId;
      String? headFormError;
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('New Expense Head'),
            scrollable: true,
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: code,
                    decoration: const InputDecoration(labelText: 'Head Code'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Head Name'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: accountId,
                    decoration: const InputDecoration(
                      labelText: 'Expense Ledger',
                    ),
                    items: accounts
                        .map(
                          (a) => DropdownMenuItem(
                            value: int.parse('${a['id']}'),
                            child: Text('${a['code']} · ${a['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setLocal(() {
                      accountId = v;
                      headFormError = null;
                    }),
                  ),
                  if (headFormError != null) ...[
                    const SizedBox(height: 10),
                    Text(headFormError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                  final codeText = code.text.trim();
                  final nameText = name.text.trim();
                  if (codeText.isEmpty || nameText.isEmpty || accountId == null) {
                    setLocal(() => headFormError =
                        'Head Code, Head Name aur Expense Ledger required hain.');
                    return;
                  }
                  if (codeText.length > 80 || nameText.length > 190) {
                    setLocal(() => headFormError =
                        'Head Code max 80 aur Name max 190 characters rakhein.');
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      );
      if (ok == true && accountId != null)
        await _post(
            ApiPaths.expenseHeads,
            {
              'code': code.text.trim(),
              'name': name.text.trim(),
              'expense_account_id': accountId,
            },
            closeSheet: false);
      code.dispose();
      name.dispose();
    } catch (e) {
      if (mounted) _setFinanceState(() => message = UiError.message(e));
    }
  }

}
