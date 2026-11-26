import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/providers.dart';
import '../../core/transaction_guardrails.dart';
import '../../core/entry_form_scope.dart';
import '../../core/counter_sale_preview.dart';
import '../../widgets/counter_billing_summary.dart';
import '../../widgets/search_choice_dialog.dart';
import '../../core/whole_pcs.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';
import '../../widgets/module_workspace.dart';
import '../../widgets/guided_action_panel.dart';
import 'prepaid_orders_screen.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key, this.initialAction});

  final String? initialAction;

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  int refresh = 0;
  String? message;
  bool _handledInitialAction = false;
  bool _entryInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_handledInitialAction || widget.initialAction == null || !mounted)
        return;
      _handledInitialAction = true;
      switch (widget.initialAction) {
        case 'counter_sale':
          await _counterSale();
          break;
        case 'new_customer':
          await _createCustomer();
          break;
        case 'receipt':
          await _receipt();
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final branchReady = app.currentBranchId != null;
    final actions = <GuidedAction>[
      if (app.can('sales.create') ||
          app.can('sales.view') ||
          app.can('sales.receipt.create') ||
          app.can('sales.discount.approve') ||
          app.can('sales.discount.ho.approve'))
        GuidedAction(
          id: 'prepaid_orders',
          title: 'Prepaid Orders',
          description:
              'View orders, discount approval and verified payment status.',
          icon: Icons.receipt_long_outlined,
          primary: true,
          enabled: branchReady,
          onOpen: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const PrepaidOrdersScreen(),
            ),
          ),
        ),
      if (app.can('sales.create'))
        GuidedAction(
          id: 'counter_sale',
          title: 'New Counter Sale',
          description: 'Choose available stock and review the sale details.',
          icon: Icons.point_of_sale_outlined,
          primary: true,
          enabled: branchReady,
          onOpen: _counterSale,
        ),
      if (app.can('sales.create'))
        GuidedAction(
          id: 'new_customer',
          title: 'Add Customer',
          description: 'Register a customer for the authorised branch.',
          icon: Icons.person_add_alt_1_outlined,
          enabled: branchReady,
          onOpen: _createCustomer,
        ),
      if (app.can('sales.receipt.create'))
        GuidedAction(
          id: 'receipt',
          title: 'Customer Receipt',
          description: 'Record a payment against an existing customer balance.',
          icon: Icons.payments_outlined,
          enabled: branchReady,
          onOpen: _receipt,
        ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Sales & Collections')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: ModuleWorkspaceHeader(
                title: 'Sales Desk',
                subtitle: 'Full-payment orders, approval and collections.',
                icon: Icons.point_of_sale_outlined,
                contextLabel: 'Business date · ${app.businessDate}',
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: BranchSelector(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: GuidedActionPanel(
                title: 'What would you like to do?',
                subtitle: 'Open one authorised task. Payments and approvals stay in their original workflows.',
                actions: actions,
              ),
            ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ModuleMessageBanner(message: message!),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 7),
              child: ModuleSectionHeader(
                title: 'Customer Accounts',
                subtitle: 'Registered customer master for the selected branch.',
              ),
            ),
            Expanded(
              child: app.currentBranchId == null
                  ? const Center(child: Text('Select an authorised branch.'))
                  : AsyncPanel(
                      key: ValueKey('${app.currentBranchId}-$refresh'),
                      loader: () => api.get(
                        ApiPaths.customers,
                        query: {'branch_id': app.currentBranchId},
                      ),
                      emptyMessage: 'No customer accounts are available.',
                      builder: (context, data) => RecordsList(
                        recordType: 'customer',
                        rows: (data as List)
                            .map((e) => Map<String, dynamic>.from(e as Map))
                            .toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createCustomer() async {
    final app = ref.read(appStateProvider);
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final mobile = TextEditingController();
    final email = TextEditingController();
    final address = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Customer'),
        scrollable: true,
        content: SizedBox(
          width: 520,
          child: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Customer Name *'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter the customer name.' : null,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: mobile,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Mobile'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (value) => value == null || value.trim().isEmpty ||
                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
                      ? null : 'Enter a valid email address.',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: address,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Create Customer'),
          ),
        ],
      ),
    );
    final payload = {
      'branch_id': app.currentBranchId,
      'name': name.text.trim(),
      'mobile': mobile.text.trim(),
      'email': email.text.trim(),
      'address': address.text.trim(),
    };
    name.dispose();
    mobile.dispose();
    email.dispose();
    address.dispose();
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).post(ApiPaths.customers, data: payload);
      if (mounted)
        setState(() {
          refresh++;
          message = 'Customer create ho gaya.';
        });
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _counterSale() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    if (!mounted || _entryInProgress || !app.can('sales.create') || app.currentBranchId == null) return;
    final scope = EntryFormScope(app, api);
    setState(() => _entryInProgress = true);
    final controllers = <TextEditingController>[];
    TextEditingController controller({String? text}) {
      final result = TextEditingController(text: text);
      controllers.add(result);
      return result;
    }
    try {
      final results = await Future.wait([
        api.get(ApiPaths.products),
        api.get(
          ApiPaths.availableStock,
          query: {'branch_id': app.currentBranchId},
        ),
        api.get(ApiPaths.customers, query: {'branch_id': app.currentBranchId}),
        api.get(ApiPaths.financeBootstrap),
      ]);
      final products = (results[0] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final productById = {
        for (final p in products) int.parse('${p['id']}'): p,
      };
      final stock = (results[1] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where(
            (e) =>
                int.tryParse('${e['custodian_key']}') == 0 &&
                (double.tryParse('${e['quantity']}') ?? 0) > 0,
          )
          .toList();
      final customers = (results[2] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final finance = Map<String, dynamic>.from(results[3] as Map);
      final accounts = (finance['accounts'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where(
            (e) =>
                '${e['type']}' == 'asset' &&
                const {
                  'cash',
                }.contains('${e['subtype']}'.toLowerCase()),
          )
          .toList();
      if (stock.isEmpty)
        throw Exception(
          'No stock is available for sale in the selected branch.',
        );

      int? customerId;
      int? accountId;
      final paid = controller(text: '0');
      final qty = <int, TextEditingController>{
        for (var i = 0; i < stock.length; i++) i: controller(),
      };
      String? formError;
      String productFilter = '';
      List<Map<String, dynamic>>? validatedLines;
      double? validatedPaidAmount;
      CounterSalePreview preview() => CounterSalePreview.fromSelection(
        stock: stock,
        products: productById,
        quantities: [for (var i = 0; i < stock.length; i++) qty[i]!.text],
      );
      if (!mounted || !scope.matches(ref.read(appStateProvider), ref.read(apiClientProvider))) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Counter Sale'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Branch: ${app.currentBranchName} · Date: ${app.businessDate}'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final selected = await showDialog<int>(
                          context: context,
                          builder: (_) => SearchChoiceDialog(
                            title: 'Select customer',
                            choices: [
                              const SearchChoice(0, 'Cash / Walk-in', ''),
                              for (final c in customers)
                                if ((int.tryParse('${c['id']}') ?? 0) > 0)
                                  SearchChoice(int.parse('${c['id']}'), '${c['name']}', '',
                                    search: [c['phone'], c['code']]),
                            ],
                          ),
                        );
                        if (!context.mounted || selected == null) return;
                        setLocal(() => customerId = selected == 0 ? null : selected);
                      },
                      icon: const Icon(Icons.person_search_outlined),
                      label: Text(customerId == null ? 'Cash / Walk-in · Select customer' :
                        customers.firstWhere((c) => int.tryParse('${c['id']}') == customerId)['name'].toString()),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      isExpanded: true,
                      initialValue: accountId,
                      decoration: const InputDecoration(
                        labelText: 'Cash Account (legacy counter; UPI via Prepaid Orders)',
                      ),
                      items: accounts
                          .map(
                            (a) => DropdownMenuItem<int?>(
                              value: int.parse('${a['id']}'),
                              child: Text('${a['code']} · ${a['name']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setLocal(() => accountId = v),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: paid,
                      onChanged: (_) => setLocal(() => formError = null),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Full Cash Payment (required)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    CounterBillingSummary(
                      preview: preview(),
                      paid: double.tryParse(paid.text.trim()),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Find product or batch', prefixIcon: Icon(Icons.search)),
                      onChanged: (value) => setLocal(() => productFilter = value),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(stock.length, (i) {
                      final row = stock[i];
                      final pid = int.parse('${row['product_id']}');
                      final p = productById[pid] ?? row;
                      final batchKey = int.tryParse('${row['batch_key']}') ?? 0;
                      final batchLabel = batchKey == 0
                          ? 'No Batch'
                          : '${row['batch_no'] ?? 'Batch'}';
                      if (qty[i]!.text.trim().isEmpty && !EntryFormScope.matchesProduct(productFilter, [row['product_name'], p['sku'], row['batch_no']])) return const SizedBox.shrink();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${row['product_name']}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                    Text(
                                      '$batchLabel · Available ${row['quantity']} ${row['uom'] ?? ''}',
                                    ),
                                    Text(
                                      'Sale ₹${p['sale_price'] ?? 0} · Batch mode ${BusinessFormat.status(p['batch_tracking'] ?? 'optional')}',
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 110,
                                child: TextField(
                                  controller: qty[i],
                                  onChanged: (_) => setLocal(() => formError = null),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [WholePcs.positiveFormatter],
                                  decoration: const InputDecoration(
                                    labelText: 'Qty',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
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
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final review = preview();
                  final lines = review.lines;
                  String? error = review.error;
                  if (error == null && lines.isEmpty) {
                    error = 'Product quantity required.';
                  }
                  final gross = review.gross;
                  final paidAmount = double.tryParse(paid.text.trim());
                  if (error == null && paidAmount == null) {
                    error = 'Enter a valid paid amount.';
                  }
                  if (error == null && paidAmount != null) {
                    error = TransactionGuardrails.counterSale(
                      gross: gross,
                      paid: paidAmount,
                      customerId: customerId,
                      paymentAccountId: accountId,
                    );
                  }
                  if (error != null) {
                    setLocal(() => formError = error);
                    return;
                  }
                  validatedLines = lines;
                  validatedPaidAmount = paidAmount;
                  Navigator.pop(context, true);
                },
                child: const Text('Post Sale'),
              ),
            ],
          ),
        ),
      );
      if (ok == true && mounted) {
        if (!scope.matches(ref.read(appStateProvider), ref.read(apiClientProvider))) {
          throw StateError('ERP scope changed. Open a new entry before submitting.');
        }
        final lines = validatedLines!;
        final paidAmount = validatedPaidAmount!;
        final r = await api.post(
          ApiPaths.counterSale,
          data: {
            'branch_id': app.currentBranchId,
            if (customerId != null) 'customer_id': customerId,
            'paid_amount': paidAmount,
            if (accountId != null) 'payment_account_id': accountId,
            'lines': lines,
          },
        );
        if (mounted)
          setState(() {
            message = 'Sale ${(r as Map)['sale_no']} posted.';
            refresh++;
          });
      }

    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    } finally {
      for (final c in controllers) { c.dispose(); }
      if (mounted) setState(() => _entryInProgress = false);
    }
  }

  Future<void> _receipt() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    final branchId = app.currentBranchId;
    if (branchId == null) return;
    try {
      final results = await Future.wait([
        api.get(ApiPaths.openSales, query: {'branch_id': branchId}),
        api.get(ApiPaths.financeBootstrap),
      ]);
      final openSales = (results[0] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (openSales.isEmpty) {
        if (mounted) {
          setState(
            () => message =
                'No posted outstanding sale is available for customer receipt.',
          );
        }
        return;
      }
      final finance = Map<String, dynamic>.from(results[1] as Map);
      final accounts = (finance['accounts'] as List)
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
      if (!mounted) return;

      int? saleId;
      int? accountId;
      final receiptFormKey = GlobalKey<FormState>();
      final amount = TextEditingController();
      final reference = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setLocal) => AlertDialog(
            title: const Text('Customer Receipt'),
            scrollable: true,
            content: SizedBox(
              width: 520,
              child: Form(
                key: receiptFormKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: saleId,
                      isExpanded: true,
                      validator: (value) => value == null
                          ? 'Select an outstanding sale.' : null,
                      decoration: const InputDecoration(
                        labelText: 'Outstanding Sale *',
                      ),
                      items: openSales.map((sale) {
                        final id = int.parse('${sale['id']}');
                        final label =
                            '${sale['sale_no']} · ${sale['customer_name']} · Due ${sale['outstanding_amount']}';
                        return DropdownMenuItem(value: id, child: Text(label,
                            maxLines: 1, overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (value) {
                        setLocal(() => saleId = value);
                        if (value != null) {
                          final selected = openSales.firstWhere(
                            (sale) => int.parse('${sale['id']}') == value,
                          );
                          amount.text = '${selected['outstanding_amount']}';
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: accountId,
                      isExpanded: true,
                      validator: (value) => value == null
                          ? 'Select a payment account.' : null,
                      decoration: const InputDecoration(
                        labelText: 'Cash / Bank / UPI Account *',
                      ),
                      items: accounts
                          .map(
                            (a) => DropdownMenuItem(
                              value: int.parse('${a['id']}'),
                              child: Text('${a['code']} · ${a['name']}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setLocal(() => accountId = v),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: amount,
                      textInputAction: TextInputAction.next,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Receipt Amount *',
                      ),
                      validator: (text) {
                        final value = double.tryParse(text?.trim() ?? '');
                        if (value == null || !value.isFinite || value <= 0) {
                          return 'Enter an amount greater than zero.';
                        }
                        if (saleId != null) {
                          final selected = openSales.firstWhere(
                              (sale) => int.tryParse('${sale['id']}') == saleId);
                          final due = double.tryParse(
                              '${selected['outstanding_amount']}') ?? 0;
                          if (value > due) return 'Amount exceeds the outstanding balance.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: reference,
                      decoration: const InputDecoration(labelText: 'Reference'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (receiptFormKey.currentState!.validate()) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                child: const Text('Post Receipt'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        final selected = openSales.firstWhere(
          (sale) => int.tryParse('${sale['id']}') == saleId,
        );
        final outstanding =
            double.tryParse('${selected['outstanding_amount']}') ?? 0;
        final receiptAmount = double.tryParse(amount.text.trim());
        if (receiptAmount == null) {
          throw Exception('Enter a valid receipt amount.');
        }
        final guardError = TransactionGuardrails.customerReceipt(
          saleId: saleId,
          paymentAccountId: accountId,
          amount: receiptAmount,
          outstanding: outstanding,
        );
        if (guardError != null) throw Exception(guardError);
        await api.post(
          ApiPaths.customerReceipt,
          data: {
            'branch_id': branchId,
            'sale_id': saleId,
            'amount': receiptAmount,
            'payment_account_id': accountId,
            'reference': reference.text.trim(),
          },
        );
        if (mounted)
          setState(() {
            message = 'Customer receipt selected sale par posted.';
            refresh++;
          });
      }
      amount.dispose();
      reference.dispose();
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }
}
