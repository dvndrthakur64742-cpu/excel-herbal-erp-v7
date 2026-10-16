part of 'finance_screen.dart';

extension _FinanceExpensesFeature on _FinanceScreenState {
  Widget _expenses(AppState app, dynamic api) {
    if (app.currentBranchId == null)
      return const Center(child: Text('Branch select karein.'));
    return Column(
      children: [
        if (app.can('finance.expense.create'))
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _expense,
                icon: const Icon(Icons.add_card_outlined),
                label: const Text('New Expense'),
              ),
            ),
          ),
        Expanded(
          child: AsyncPanel(
            key: ValueKey('expenses-${app.currentBranchId}-$refresh'),
            future: api.get(
              ApiPaths.expenses,
              query: {'branch_id': app.currentBranchId},
            ),
            emptyMessage: 'Koi expense record nahi hai.',
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
      final amount = TextEditingController();
      final desc = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Expense Entry'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: head,
                    decoration: const InputDecoration(
                      labelText: 'Expense Head',
                    ),
                    items: heads
                        .map(
                          (e) => DropdownMenuItem(
                            value: int.parse('${e['id']}'),
                            child: Text('${e['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setLocal(() => head = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: account,
                    decoration: const InputDecoration(
                      labelText: 'Payment Account',
                    ),
                    items: accounts
                        .map(
                          (e) => DropdownMenuItem(
                            value: int.parse('${e['id']}'),
                            child: Text('${e['code']} · ${e['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setLocal(() => account = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: desc,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, head != null && account != null),
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        final expenseAmount = double.tryParse(amount.text.trim());
        if (expenseAmount == null) {
          throw Exception('Expense amount valid number me enter karein.');
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
            message = 'Expense approval ke liye submit ho gaya.';
            refresh++;
          });
      }
      amount.dispose();
      desc.dispose();
    } catch (e) {
      if (mounted) _setFinanceState(() => message = UiError.message(e));
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
