import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/whole_pcs.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';

class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key});
  @override
  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends ConsumerState<PurchaseScreen> {
  int refresh = 0;
  String? message;
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    return Scaffold(
        appBar: AppBar(title: const Text('Purchase & Suppliers')),
        body: Column(children: [
          const Padding(padding: EdgeInsets.all(16), child: BranchSelector()),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (app.can('purchase.create'))
                  FilledButton.icon(
                      onPressed: app.currentBranchId == null ? null : _newBill,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Purchase Entry')),
                if (app.can('finance.supplier_payment.create'))
                  FilledButton.tonalIcon(
                      onPressed: app.currentBranchId == null ? null : _payBill,
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Supplier Payment')),
                if (app.can('purchase.create'))
                  FilledButton.tonalIcon(
                      onPressed: _createSupplier,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('New Supplier'))
              ])),
          if (message != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(message!)),
          Expanded(
              child: app.currentBranchId == null
                  ? const Center(child: Text('Branch select karein.'))
                  : AsyncPanel(
                      key: ValueKey('${app.currentBranchId}-$refresh'),
                      future: api.get(ApiPaths.openBills,
                          query: {'branch_id': app.currentBranchId}),
                      emptyMessage: 'Supplier outstanding bill nahi hai.',
                      builder: (context, data) => RecordsList(
                          recordType: 'purchase',
                          rows: (data as List)
                              .map((e) => Map<String, dynamic>.from(e as Map))
                              .toList())))
        ]));
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
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration: const InputDecoration(
                              labelText: 'Supplier Name')),
                      const SizedBox(height: 10),
                      TextField(
                          controller: mobile,
                          keyboardType: TextInputType.phone,
                          decoration:
                              const InputDecoration(labelText: 'Mobile')),
                      const SizedBox(height: 10),
                      TextField(
                          controller: gstin,
                          decoration: const InputDecoration(
                              labelText: 'GSTIN (optional)'))
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, name.text.trim().isNotEmpty),
                      child: const Text('Create'))
                ]));
    final payload = {
      'name': name.text.trim(),
      'mobile': mobile.text.trim(),
      'gstin': gstin.text.trim()
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
                                    decoration: const InputDecoration(
                                        labelText: 'Supplier'),
                                    items: suppliers
                                        .map((s) => DropdownMenuItem(
                                            value: int.parse('${s['id']}'),
                                            child: Text('${s['name']}')))
                                        .toList(),
                                    onChanged: (v) =>
                                        setLocal(() => supplierId = v)),
                                const SizedBox(height: 10),
                                TextField(
                                    controller: billNo,
                                    decoration: const InputDecoration(
                                        labelText: 'Supplier Bill No.')),
                                const SizedBox(height: 14),
                                ...products.map((p) {
                                  final id = int.parse('${p['id']}');
                                  return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                    '${p['name']} · Batch ${p['batch_tracking']}'),
                                                const SizedBox(height: 8),
                                                Row(children: [
                                                  Expanded(
                                                      child: TextField(
                                                          controller: qty[id],
                                                          keyboardType:
                                                              TextInputType
                                                                  .number,
                                                          inputFormatters: [
                                                            WholePcs
                                                                .positiveFormatter
                                                          ],
                                                          decoration:
                                                              const InputDecoration(
                                                                  labelText:
                                                                      'Qty'))),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                      child: TextField(
                                                          controller: cost[id],
                                                          keyboardType:
                                                              const TextInputType
                                                                  .numberWithOptions(
                                                                  decimal:
                                                                      true),
                                                          decoration:
                                                              const InputDecoration(
                                                                  labelText:
                                                                      'Unit Cost')))
                                                ]),
                                                const SizedBox(height: 8),
                                                TextField(
                                                    controller: batchNo[id],
                                                    decoration:
                                                        const InputDecoration(
                                                            labelText:
                                                                'Batch No. (optional / required by product)'))
                                              ])));
                                })
                              ]))),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel')),
                        FilledButton(
                            onPressed: () => Navigator.pop(
                                context,
                                supplierId != null &&
                                    billNo.text.trim().isNotEmpty),
                            child: const Text('Post Purchase'))
                      ])));
      if (ok == true) {
        final lines = <Map<String, dynamic>>[];
        for (final p in products) {
          final id = int.parse('${p['id']}');
          final q = WholePcs.parseOrZero(qty[id]!.text);
          if (q > 0)
            lines.add({
              'product_id': id,
              'quantity': q,
              'unit_cost': double.tryParse(cost[id]!.text) ?? 0,
              if (batchNo[id]!.text.trim().isNotEmpty)
                'batch_no': batchNo[id]!.text.trim()
            });
        }
        if (lines.isEmpty) throw Exception('Product line required.');
        final r = await api.post(ApiPaths.purchaseBills, data: {
          'branch_id': app.currentBranchId,
          'supplier_id': supplierId,
          'bill_no': billNo.text.trim(),
          'bill_date': _today(),
          'lines': lines
        });
        if (mounted)
          setState(
              () => message = 'Purchase bill ${(r as Map)['bill_no']} posted.');
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
      final bills = (await api.get(ApiPaths.openBills,
              query: {'branch_id': app.currentBranchId}) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final finance = Map<String, dynamic>.from(
          await api.get(ApiPaths.financeBootstrap) as Map);
      final accounts = (finance['accounts'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) =>
              '${e['type']}' == 'asset' &&
              const {'cash', 'bank', 'upi'}
                  .contains('${e['subtype']}'.toLowerCase()))
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
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            DropdownButtonFormField<int>(
                                initialValue: billId,
                                decoration: const InputDecoration(
                                    labelText: 'Outstanding Bill'),
                                items: bills
                                    .map((b) => DropdownMenuItem(
                                        value: int.parse('${b['id']}'),
                                        child: Text(
                                            '${b['supplier_name']} · ${b['bill_no']} · ₹${b['outstanding_amount']}')))
                                    .toList(),
                                onChanged: (v) => setLocal(() => billId = v)),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<int>(
                                initialValue: accountId,
                                decoration: const InputDecoration(
                                    labelText: 'Payment Account'),
                                items: accounts
                                    .map((a) => DropdownMenuItem(
                                        value: int.parse('${a['id']}'),
                                        child: Text(
                                            '${a['code']} · ${a['name']}')))
                                    .toList(),
                                onChanged: (v) =>
                                    setLocal(() => accountId = v)),
                            const SizedBox(height: 10),
                            TextField(
                                controller: amount,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration:
                                    const InputDecoration(labelText: 'Amount'))
                          ])),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel')),
                        FilledButton(
                            onPressed: () => Navigator.pop(
                                context, billId != null && accountId != null),
                            child: const Text('Post Payment'))
                      ])));
      if (ok == true) {
        await api.post(ApiPaths.supplierPayments, data: {
          'purchase_bill_id': billId,
          'amount': double.tryParse(amount.text) ?? 0,
          'payment_account_id': accountId
        });
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

  static String _today() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
