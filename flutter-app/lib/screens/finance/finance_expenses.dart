part of 'finance_screen.dart';

extension _FinanceExpensesFeature on _FinanceScreenState {
  Widget _expenses(AppState app, dynamic api) {
    if (app.currentBranchId == null)
      return const Center(child: Text('Select a branch.'));
    return Column(
      children: [
        if (app.can('finance.expense.create'))
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _expenseInProgress ? null : _expense,
                icon: const Icon(Icons.add_card_outlined),
                label: const Text('New Expense'),
              ),
            ),
          ),
        Expanded(
          child: AsyncPanel(
            key: ValueKey('expenses-${app.currentBranchId}-$refresh'),
            loader: () => api.get(
              ApiPaths.expenses,
              query: {'branch_id': app.currentBranchId},
            ),
            emptyMessage: 'No expense records yet.',
            builder: (context, data) => RecordsList(
              recordType: 'expense',
              rows: _rows(data),
              onTap: _expenseAction,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _expense() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    if (!mounted || _expenseInProgress || !app.can('finance.expense.create') || app.currentBranchId == null) return;
    _setFinanceState(() => _expenseInProgress = true);
    final amount = TextEditingController();
    final desc = TextEditingController();
    try {
      final d = Map<String, dynamic>.from(
        await api.get(ApiPaths.financeBootstrap) as Map,
      );
      final heads = (d['expense_heads'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final accounts = (d['accounts'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where(
            (e) =>
                '${e['type']}' == 'asset' &&
                const {
                  'cash',
                  'bank',
                  'upi',
                }.contains('${e['subtype']}'.toLowerCase()),
          )
          .toList();
      int? head, account;
      if (!mounted || !identical(ref.read(appStateProvider), app)) return;
      String? validation;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Expense Entry'),
            scrollable: true,
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Branch: ${app.currentBranchName} · Date: ${app.businessDate}'),
                  const SizedBox(height: 8),
                  const Text('Submit for approval. This does not approve the expense.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDialog<int>(
                        context: context,
                        builder: (_) => SearchChoiceDialog(
                          title: 'Expense Head',
                          choices: [
                            for (final e in heads)
                              if ((int.tryParse('${e['id']}') ?? 0) > 0)
                                SearchChoice(int.parse('${e['id']}'), '${e['name']}',
                                  '${e['code'] ?? ""}'),
                          ],
                        ),
                      );
                      if (!context.mounted || picked == null) return;
                      setLocal(() { head = picked; validation = null; });
                    },
                    icon: const Icon(Icons.search),
                    label: Text(head == null ? 'Select Expense Head' :
                      heads.firstWhere((e) => int.tryParse('${e['id']}') == head)['name'].toString()),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDialog<int>(
                        context: context,
                        builder: (_) => SearchChoiceDialog(
                          title: 'Payment Account',
                          choices: [
                            for (final e in accounts)
                              if ((int.tryParse('${e['id']}') ?? 0) > 0)
                                SearchChoice(int.parse('${e['id']}'), '${e['name']}',
                                  '${e['code'] ?? ""}'),
                          ],
                        ),
                      );
                      if (!context.mounted || picked == null) return;
                      setLocal(() { account = picked; validation = null; });
                    },
                    icon: const Icon(Icons.search),
                    label: Text(account == null ? 'Select Payment Account' :
                      accounts.firstWhere((e) => int.tryParse('${e['id']}') == account)['name'].toString()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Amount (required)', prefixText: '₹ '),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: desc,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 2,
                  ),
                  if (validation != null) Padding(padding: const EdgeInsets.only(top: 10),
                    child: Text(validation!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
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
                  final parsed = double.tryParse(amount.text.trim());
                  final error = TransactionGuardrails.expense(
                    expenseHeadId: head, paymentAccountId: account,
                    amount: parsed ?? double.nan);
                  if (error != null) {
                    setLocal(() => validation = error);
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('Submit for approval'),
              ),
            ],
          ),
        ),
      );
      if (ok == true && mounted) {
        final latest = ref.read(appStateProvider);
        if (!identical(latest, app) || !identical(ref.read(apiClientProvider), api)) {
          throw StateError('ERP scope changed. Open a new expense entry before submitting.');
        }
        final expenseAmount = double.tryParse(amount.text.trim());
        if (expenseAmount == null) {
          throw Exception('Enter a valid expense amount.');
        }
        final guardError = TransactionGuardrails.expense(
          expenseHeadId: head,
          paymentAccountId: account,
          amount: expenseAmount,
        );
        if (guardError != null) throw Exception(guardError);
        await api.post(
          ApiPaths.expenses,
          data: {
            'branch_id': app.currentBranchId,
            'expense_head_id': head,
            'amount': expenseAmount,
            'payment_account_id': account,
            'expense_date': app.businessDate,
            'description': desc.text.trim(),
          },
        );
        if (mounted)
          _setFinanceState(() {
            message = 'Expense submitted for approval.';
            refresh++;
          });
      }
    } catch (e) {
      if (mounted) _setFinanceState(() => message = UiError.message(e));
    } finally {
      amount.dispose();
      desc.dispose();
      if (mounted) _setFinanceState(() => _expenseInProgress = false);
    }
  }

  void _expenseAction(Map<String, dynamic> row) {
    final app = ref.read(appStateProvider);
    if ('${row['status']}' != 'pending' || !app.can('finance.expense.approve'))
      return;
    final id = int.parse('${row['id']}');
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(title: Text('${row['expense_head']} · ₹${row['amount']}')),
            ListTile(subtitle: Text('${row['description'] ?? ''}')),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Approve'),
              onTap: () =>
                  _post(ApiPaths.expenseDecision(id), {'approve': true}),
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Reject'),
              onTap: () =>
                  _post(ApiPaths.expenseDecision(id), {'approve': false}),
            ),
          ],
        ),
      ),
    );
  }

}
