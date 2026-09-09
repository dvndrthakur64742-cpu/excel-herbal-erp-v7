import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/transaction_guardrails.dart';
import '../../core/overlay_transition.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';
import '../../widgets/module_workspace.dart';

class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({
    super.key,
    this.initialSection = 'books',
    this.initialAction,
  });

  final String initialSection;
  final String? initialAction;

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  int refresh = 0;
  String? message;
  bool _handledInitialAction = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_handledInitialAction || widget.initialAction == null || !mounted)
        return;
      _handledInitialAction = true;
      if (widget.initialAction == 'expense') await _expense();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final tabs = <(String, Widget)>[];
    if (app.canAny(const [
      'finance.view',
      'finance.accounting.view',
      'finance.account.manage',
    ])) tabs.add(('Books', _books(app, api)));
    if (app.canAny(const [
      'finance.view',
      'finance.expense.create',
      'finance.expense.approve',
    ])) tabs.add(('Expenses', _expenses(app, api)));
    if (app.canAny(const ['finance.branch_close', 'finance.branch_reopen']))
      tabs.add(('Closing', _closing(app, api)));
    if (app.can('finance.bank_reconcile')) tabs.add(('Bank', _bank(app, api)));
    if (app.can('finance.period.manage'))
      tabs.add(('Periods', _periods(app, api)));
    if (tabs.isEmpty)
      return const Scaffold(
        body: Center(child: Text('No authorised finance functions.')),
      );
    final preferredLabel = switch (widget.initialSection) {
      'expenses' => 'Expenses',
      'closing' => 'Closing',
      'bank' => 'Bank',
      'periods' => 'Periods',
      _ => 'Books',
    };
    final requestedIndex = tabs.indexWhere((tab) => tab.$1 == preferredLabel);
    final initialIndex = requestedIndex < 0 ? 0 : requestedIndex;
    return DefaultTabController(
      length: tabs.length,
      initialIndex: initialIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Finance'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final tab in tabs) Tab(text: tab.$1)],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: ModuleWorkspaceHeader(
                  title: 'Finance Control Centre',
                  subtitle:
                      'Books, expenses, branch closing, bank reconciliation and periods.',
                  icon: Icons.account_balance_outlined,
                  contextLabel: 'Business date · ${app.businessDate}',
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: BranchSelector(),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ModuleMessageBanner(message: message!),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 7),
                child: ModuleSectionHeader(
                  title: 'Accounting Workspace',
                  subtitle:
                      'Select the finance function required for the current business date.',
                ),
              ),
              Expanded(
                child: TabBarView(children: [for (final tab in tabs) tab.$2]),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
              builder: (context, data) =>
                  RecordsList(recordType: 'trial_balance', rows: _rows(data)),
            ),
          ),
        ],
      );

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
            builder: (context, data) => RecordsList(
              recordType: 'branch_closing',
              rows: _rows(data),
              onTap: _closingAction,
            ),
          ),
        ),
      ],
    );
  }

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
            builder: (context, data) => RecordsList(
              recordType: 'accounting_period',
              rows: _rows(data),
              onTap: _periodAction,
            ),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _rows(dynamic data) =>
      (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _newLedger() async {
    final code = TextEditingController();
    final name = TextEditingController();
    String type = 'asset';
    String subtype = 'bank';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New Ledger'),
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
                  onChanged: (v) => setLocal(() => subtype = v ?? ''),
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
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('New Expense Head'),
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
                    onChanged: (v) => setLocal(() => accountId = v),
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
      if (mounted) setState(() => message = UiError.message(e));
    }
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
          setState(() {
            message = 'Expense approval ke liye submit ho gaya.';
            refresh++;
          });
      }
      amount.dispose();
      desc.dispose();
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
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
      if (mounted) setState(() => message = 'Preflight: $r');
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
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
        setState(() {
          message = 'Closing draft #${(r as Map)['id']} created.';
          refresh++;
        });
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
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
          setState(() {
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
      if (mounted) setState(() => message = UiError.message(e));
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
      if (mounted) setState(() => message = UiError.message(e));
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

  Future<void> _closePeriod() async {
    final app = ref.read(appStateProvider);
    final from = TextEditingController(text: app.businessMonthStart);
    final to = TextEditingController(text: app.businessDate);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close Accounting Period'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: from,
                decoration: const InputDecoration(labelText: 'From YYYY-MM-DD'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: to,
                decoration: const InputDecoration(labelText: 'To YYYY-MM-DD'),
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
            child: const Text('Close Period'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final guardError = TransactionGuardrails.dateRange(
        from.text.trim(),
        to.text.trim(),
      );
      if (guardError != null) throw Exception(guardError);
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

  Future<void> _reasonPost(String path, String title) async {
    final reason = await _askReason(title);
    if (reason == null) return;
    await _post(path, {'reason': reason}, closeSheet: false);
  }

  Future<String?> _askReason(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.length >= 5) Navigator.pop(context, v);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _post(
    String path,
    Map<String, dynamic> data, {
    bool closeSheet = true,
  }) async {
    if (closeSheet) {
      final closed = await OverlayTransition.closeAndSettle(context);
      if (!closed || !mounted) return;
    }
    try {
      final r = await ref.read(apiClientProvider).post(path, data: data);
      if (mounted)
        setState(() {
          message = 'Done: $r';
          refresh++;
        });
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }
}
