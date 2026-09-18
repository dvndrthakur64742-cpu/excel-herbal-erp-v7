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






  List<Map<String, dynamic>> _rows(dynamic data) =>
      (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();














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
