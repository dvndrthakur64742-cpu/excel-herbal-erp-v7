part of 'finance_screen.dart';

extension _FinanceBankFeature on _FinanceScreenState {
  Widget _bank(AppState app, dynamic api) {
    if (app.currentBranchId == null)
      return const Center(child: Text('Branch select karein.'));
    return Column(
      children: [
        if (app.can('finance.bank_reconcile'))
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _createBankReconciliation,
                icon: const Icon(Icons.account_balance),
                label: const Text('New Bank Reconciliation'),
              ),
            ),
          ),
        Expanded(
          child: AsyncPanel(
            key: ValueKey('bank-${app.currentBranchId}-$refresh'),
            future: api.get(
              ApiPaths.bankReconciliations,
              query: {'branch_id': app.currentBranchId},
            ),
            emptyMessage: 'Koi Bank Reconciliation nahi hai.',
            builder: (context, data) => RecordsList(
              recordType: 'bank_reconciliation',
              rows: _rows(data),
              onTap: (row) => _bankDetail(int.parse('${row['id']}')),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createBankReconciliation() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    try {
      final finance = Map<String, dynamic>.from(
        await api.get(ApiPaths.financeBootstrap) as Map,
      );
      final accounts = (finance['accounts'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where(
            (e) =>
                '${e['type']}' == 'asset' &&
                const {'bank', 'upi'}.contains('${e['subtype']}'.toLowerCase()),
          )
          .toList();
      int? accountId;
      final from = TextEditingController(text: app.businessMonthStart);
      final to = TextEditingController(text: app.businessDate);
      final opening = TextEditingController(text: '0');
      final closing = TextEditingController(text: '0');
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('New Bank Reconciliation'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: accountId,
                    decoration: const InputDecoration(
                      labelText: 'Bank / Asset Account',
                    ),
                    items: accounts
                        .map(
                          (a) => DropdownMenuItem(
                            value: int.parse('${a['id']}'),
                            child: Text('${a['code']} · ${a['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setLocal(() => accountId = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: from,
                    decoration: const InputDecoration(
                      labelText: 'Statement From YYYY-MM-DD',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: to,
                    decoration: const InputDecoration(
                      labelText: 'Statement To YYYY-MM-DD',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: opening,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Opening Balance',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: closing,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Closing Balance',
                    ),
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
                onPressed: () => Navigator.pop(context, accountId != null),
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        final rangeError = TransactionGuardrails.dateRange(
          from.text.trim(),
          to.text.trim(),
        );
        if (rangeError != null) throw Exception(rangeError);
        final openingValue = double.tryParse(opening.text.trim());
        final closingValue = double.tryParse(closing.text.trim());
        if (openingValue == null || closingValue == null) {
          throw Exception(
            'Opening aur Closing Balance valid number me enter karein.',
          );
        }
        final r = await api.post(
          ApiPaths.bankReconciliations,
          data: {
            'branch_id': app.currentBranchId,
            'account_id': accountId,
            'statement_from': from.text.trim(),
            'statement_to': to.text.trim(),
            'opening_balance': openingValue,
            'closing_balance': closingValue,
          },
        );
        if (mounted)
          _setFinanceState(() {
            message =
                'Bank reconciliation #${(r as Map)['id']} created. Statement lines import karein.';
            refresh++;
          });
      }
      from.dispose();
      to.dispose();
      opening.dispose();
      closing.dispose();
    } catch (e) {
      if (mounted) _setFinanceState(() => message = UiError.message(e));
    }
  }

  Future<void> _bankDetail(int id) async {
    try {
      final data = Map<String, dynamic>.from(
        await ref.read(apiClientProvider).get(ApiPaths.bankDetail(id)) as Map,
      );
      if (!mounted) return;
      final r = Map<String, dynamic>.from(data['reconciliation'] as Map);
      final lines = (data['lines'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final candidates = (data['journal_candidates'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .8,
          maxChildSize: .96,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${r['account_code']} · ${r['statement_from']} → ${r['statement_to']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Status ${r['status']} · Opening ${r['opening_balance']} · Closing ${r['closing_balance']}',
              ),
              const SizedBox(height: 12),
              if ('${r['status']}' == 'draft')
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final closed = await OverlayTransition.closeAndSettle(
                      context,
                    );
                    if (!closed || !mounted) return;
                    await _addBankLine(id);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Statement Line'),
                ),
              const SizedBox(height: 12),
              ...lines.map(
                (line) => Card(
                  child: ListTile(
                    title: Text(
                      '${line['txn_date']} · ${line['description'] ?? ''}',
                    ),
                    subtitle: Text(
                      '${line['status']} · Ref ${line['reference'] ?? '-'}',
                    ),
                    trailing: Text(
                      (double.tryParse('${line['debit']}') ?? 0) > 0
                          ? 'Dr ${line['debit']}'
                          : 'Cr ${line['credit']}',
                    ),
                    onTap: '${r['status']}' == 'draft' &&
                            '${line['status']}' == 'unmatched'
                        ? () async {
                            final closed =
                                await OverlayTransition.closeAndSettle(context);
                            if (!closed || !mounted) return;
                            await _resolveBankLine(id, line, candidates);
                          }
                        : null,
                  ),
                ),
              ),
              if ('${r['status']}' == 'draft') ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final closed = await OverlayTransition.closeAndSettle(
                      context,
                    );
                    if (!closed || !mounted) return;
                    await _post(
                      ApiPaths.bankFinalize(id),
                      const {},
                      closeSheet: false,
                    );
                  },
                  child: const Text('Finalize Reconciliation'),
                ),
              ],
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) _setFinanceState(() => message = UiError.message(e));
    }
  }

  Future<void> _addBankLine(int id) async {
    final app = ref.read(appStateProvider);
    final date = TextEditingController(text: app.businessDate);
    final description = TextEditingController();
    final reference = TextEditingController();
    final debit = TextEditingController(text: '0');
    final credit = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Statement Line'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: date,
                decoration: const InputDecoration(
                  labelText: 'Transaction Date YYYY-MM-DD',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reference,
                decoration: const InputDecoration(labelText: 'Reference'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: debit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Debit (or 0)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: credit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Credit (or 0)'),
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
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final debitValue = double.tryParse(debit.text.trim());
      final creditValue = double.tryParse(credit.text.trim());
      if (debitValue == null || creditValue == null) {
        throw Exception('Debit/Credit valid number me enter karein.');
      }
      final guardError = TransactionGuardrails.bankStatementLine(
        date: date.text.trim(),
        debit: debitValue,
        credit: creditValue,
      );
      if (guardError != null) throw Exception(guardError);
      await _post(
          ApiPaths.bankImport(id),
          {
            'lines': [
              {
                'txn_date': date.text.trim(),
                'description': description.text.trim(),
                'reference': reference.text.trim(),
                'debit': debitValue,
                'credit': creditValue,
              },
            ],
          },
          closeSheet: false);
    }
    date.dispose();
    description.dispose();
    reference.dispose();
    debit.dispose();
    credit.dispose();
  }

  Future<void> _resolveBankLine(
    int reconciliationId,
    Map<String, dynamic> line,
    List<Map<String, dynamic>> candidates,
  ) async {
    final statementNet = (double.tryParse('${line['credit']}') ?? 0) -
        (double.tryParse('${line['debit']}') ?? 0);
    final matching = candidates.where((c) {
      final journalNet = (double.tryParse('${c['debit']}') ?? 0) -
          (double.tryParse('${c['credit']}') ?? 0);
      return (statementNet - journalNet).abs() < .005;
    }).toList();
    int? candidateId;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Resolve Bank Line'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${line['txn_date']} · ${line['description']}'),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: candidateId,
                  decoration: const InputDecoration(
                    labelText: 'Matching Journal Line',
                  ),
                  items: matching
                      .map(
                        (c) => DropdownMenuItem(
                          value: int.parse('${c['journal_line_id']}'),
                          child: Text(
                            '${c['entry_no']} · ${c['entry_date']} · Dr ${c['debit']} Cr ${c['credit']}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => candidateId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'exclude'),
              child: const Text('Exclude'),
            ),
            FilledButton(
              onPressed: candidateId == null
                  ? null
                  : () => Navigator.pop(context, 'match'),
              child: const Text('Match'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'match' && candidateId != null)
      await _post(
          ApiPaths.bankMatch(int.parse('${line['id']}')),
          {
            'journal_line_id': candidateId,
          },
          closeSheet: false);
    if (choice == 'exclude') {
      final reason = await _askReason('Bank line exclusion reason');
      if (reason != null)
        await _post(
            ApiPaths.bankExclude(int.parse('${line['id']}')),
            {
              'reason': reason,
            },
            closeSheet: false);
    }
    if (mounted) _bankDetail(reconciliationId);
  }

}
