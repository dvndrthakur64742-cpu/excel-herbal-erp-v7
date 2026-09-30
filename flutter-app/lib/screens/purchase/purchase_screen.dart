import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/transaction_guardrails.dart';
import '../../core/whole_pcs.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';
import '../../widgets/module_workspace.dart';

class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key, this.initialAction});

  final String? initialAction;

  @override
  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends ConsumerState<PurchaseScreen> {
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
      switch (widget.initialAction) {
        case 'new_bill':
          await _newBill();
          break;
        case 'supplier_payment':
          await _payBill();
          break;
        case 'new_supplier':
          await _createSupplier();
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final actions = <Widget>[
      if (app.can('purchase.create'))
        FilledButton.icon(
          onPressed: app.currentBranchId == null ? null : _newBill,
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: const Text('Purchase Entry'),
        ),
      if (app.can('finance.supplier_payment.create'))
        OutlinedButton.icon(
          onPressed: app.currentBranchId == null ? null : _payBill,
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: const Text('Supplier Payment'),
        ),
      if (app.can('purchase.create'))
        OutlinedButton.icon(
          onPressed: _createSupplier,
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('New Supplier'),
        ),
    ];
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Purchase & Suppliers'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Outstanding'),
              Tab(text: 'Suppliers'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: ModuleWorkspaceHeader(
                  title: 'Procurement Desk',
                  subtitle:
                      'Supplier bills, liabilities, payments and master data.',
                  icon: Icons.local_shipping_outlined,
                  contextLabel: 'Business date · ${app.businessDate}',
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: BranchSelector(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ModuleActionPanel(
                  title: 'Procurement Actions',
                  subtitle:
                      'Post a supplier bill, settle liability or maintain supplier master.',
                  actions: actions,
                ),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ModuleMessageBanner(message: message!),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(12, 12, 12, 7),
                          child: ModuleSectionHeader(
                            title: 'Outstanding Supplier Bills',
                            subtitle:
                                'Open supplier liabilities for the selected branch.',
                          ),
                        ),
                        Expanded(
                          child: app.currentBranchId == null
                              ? const Center(
                                  child: Text('Select an authorised branch.'),
                                )
                              : AsyncPanel(
                                  key: ValueKey(
                                    'bills-${app.currentBranchId}-$refresh',
                                  ),
                                  future: api.get(
                                    ApiPaths.openBills,
                                    query: {
                                      'branch_id': app.currentBranchId,
                                    },
                                  ),
                                  emptyMessage:
                                      'No supplier bills are outstanding.',
                                  builder: (context, data) => RecordsList(
                                    recordType: 'purchase',
                                    rows: (data as List)
                                        .map(
                                          (e) => Map<String, dynamic>.from(
                                            e as Map,
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(12, 12, 12, 7),
                          child: ModuleSectionHeader(
                            title: 'Supplier Master',
                            subtitle:
                                'Registered suppliers available for procurement.',
                          ),
                        ),
                        Expanded(
                          child: AsyncPanel(
                            key: ValueKey('suppliers-$refresh'),
                            future: api.get(ApiPaths.suppliers),
                            emptyMessage: 'No suppliers are registered.',
                            builder: (context, data) => RecordsList(
                              recordType: 'supplier',
                              rows: (data as List)
                                  .map(
                                    (e) => Map<String, dynamic>.from(e as Map),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createSupplier() async {
    final name = TextEditingController();
    final mobile = TextEditingController();
    final gstin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Supplier'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Supplier Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: mobile,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: gstin,
                decoration: const InputDecoration(
                  labelText: 'GSTIN (optional)',
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
            onPressed: () =>
                Navigator.pop(context, name.text.trim().isNotEmpty),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    final payload = {
      'name': name.text.trim(),
      'mobile': mobile.text.trim(),
      'gstin': gstin.text.trim(),
    };
    name.dispose();
    mobile.dispose();
    gstin.dispose();
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).post(ApiPaths.suppliers, data: payload);
      if (mounted)
        setState(() {
          refresh++;
          message = 'Supplier create ho gaya.';
        });
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _newBill() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    try {
      final suppliers = (await api.get(ApiPaths.suppliers) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final products = (await api.get(ApiPaths.products) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      int? supplierId;
      final billNo = TextEditingController();
      final qty = <int, TextEditingController>{};
      final cost = <int, TextEditingController>{};
      final batchNo = <int, TextEditingController>{};
      for (final p in products) {
        final id = int.parse('${p['id']}');
        qty[id] = TextEditingController();
        cost[id] = TextEditingController();
        batchNo[id] = TextEditingController();
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Direct Supplier Bill'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: supplierId,
                      decoration: const InputDecoration(labelText: 'Supplier'),
                      items: suppliers
                          .map(
                            (s) => DropdownMenuItem(
                              value: int.parse('${s['id']}'),
                              child: Text('${s['name']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setLocal(() => supplierId = v),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: billNo,
                      decoration: const InputDecoration(
                        labelText: 'Supplier Bill No.',
                      ),
                    ),
                    const SizedBox(height: 14),
                    ...products.map((p) {
                      final id = int.parse('${p['id']}');
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${p['name']} · Batch ${p['batch_tracking']}',
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: qty[id],
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        WholePcs.positiveFormatter,
                                      ],
                                      decoration: const InputDecoration(
                                        labelText: 'Qty',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: cost[id],
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'Unit Cost',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: batchNo[id],
                                decoration: const InputDecoration(
                                  labelText:
                                      'Batch No. (optional / required by product)',
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
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
                onPressed: () => Navigator.pop(
                  context,
                  supplierId != null && billNo.text.trim().isNotEmpty,
                ),
                child: const Text('Post Purchase'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        final lines = <Map<String, dynamic>>[];
        for (final p in products) {
          final id = int.parse('${p['id']}');
          final q = WholePcs.parseOrZero(qty[id]!.text);
          if (q <= 0) continue;
          final rawCost = cost[id]!.text.trim();
          final unitCost = double.tryParse(rawCost);
          if (unitCost == null) {
            throw Exception(
              '${p['name']} requires a valid unit cost. Enter 0 explicitly for a zero-cost item.',
            );
          }
          final batch = batchNo[id]!.text.trim();
          final guardError = TransactionGuardrails.purchaseLine(
            quantity: q,
            unitCost: unitCost,
            batchRequired: '${p['batch_tracking']}' == 'required',
            batchNo: batch,
          );
          if (guardError != null) throw Exception('${p['name']}: $guardError');
          lines.add({
            'product_id': id,
            'quantity': q,
            'unit_cost': unitCost,
            if (batch.isNotEmpty) 'batch_no': batch,
          });
        }
        if (lines.isEmpty) throw Exception('Product line required.');
        final r = await api.post(
          ApiPaths.purchaseBills,
          data: {
            'branch_id': app.currentBranchId,
            'supplier_id': supplierId,
            'bill_no': billNo.text.trim(),
            'bill_date': app.businessDate,
            'lines': lines,
          },
        );
        if (mounted)
          setState(
            () => message = 'Purchase bill ${(r as Map)['bill_no']} posted.',
          );
      }
      billNo.dispose();
      for (final c in [...qty.values, ...cost.values, ...batchNo.values])
        c.dispose();
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _payBill() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    try {
      final bills = (await api.get(
        ApiPaths.openBills,
        query: {'branch_id': app.currentBranchId},
      ) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final finance = Map<String, dynamic>.from(
        await api.get(ApiPaths.financeBootstrap) as Map,
      );
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
      int? billId;
      int? accountId;
      final amount = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Supplier Payment'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: billId,
                    decoration: const InputDecoration(
                      labelText: 'Outstanding Bill',
                    ),
                    items: bills
                        .map(
                          (b) => DropdownMenuItem(
                            value: int.parse('${b['id']}'),
                            child: Text(
                              '${b['supplier_name']} · ${b['bill_no']} · ₹${b['outstanding_amount']}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setLocal(() => billId = v);
                      if (v != null) {
                        final selected = bills.firstWhere(
                          (bill) => int.tryParse('${bill['id']}') == v,
                        );
                        amount.text = '${selected['outstanding_amount']}';
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: accountId,
                    decoration: const InputDecoration(
                      labelText: 'Payment Account',
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
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Amount'),
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
                    Navigator.pop(context, billId != null && accountId != null),
                child: const Text('Post Payment'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        final selected = bills.firstWhere(
          (bill) => int.tryParse('${bill['id']}') == billId,
        );
        final outstanding =
            double.tryParse('${selected['outstanding_amount']}') ?? 0;
        final paymentAmount = double.tryParse(amount.text.trim());
        if (paymentAmount == null) {
          throw Exception(
            'Enter a valid supplier payment amount.',
          );
        }
        final guardError = TransactionGuardrails.supplierPayment(
          billId: billId,
          paymentAccountId: accountId,
          amount: paymentAmount,
          outstanding: outstanding,
        );
        if (guardError != null) throw Exception(guardError);
        await api.post(
          ApiPaths.supplierPayments,
          data: {
            'purchase_bill_id': billId,
            'amount': paymentAmount,
            'payment_account_id': accountId,
          },
        );
        if (mounted)
          setState(() {
            message = 'Supplier payment posted.';
            refresh++;
          });
      }
      amount.dispose();
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }
}
