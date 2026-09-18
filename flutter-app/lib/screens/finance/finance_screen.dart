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

part 'finance_bank.dart';
part 'finance_books.dart';
part 'finance_expenses.dart';
part 'finance_closing.dart';
part 'finance_periods.dart';

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

  void _setFinanceState(VoidCallback update) => setState(update);

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
              if (app.can('finance.bra
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
      (data as List).map((e) => Map<String, dy Head',
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





  Future<void> _closePeriod() async {
    final app = ref.read(appStateProvider);
    final from = TextEditingController(text: app.businessMonthStart);
    final to = TextEditingController(text: app.businessDate);
    final ok = await showDia