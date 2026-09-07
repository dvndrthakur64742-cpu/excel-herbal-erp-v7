import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});
  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  int refresh = 0;
  String? message;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sales & Collections')),
      body: Column(children: [
        const Padding(padding: EdgeInsets.all(16), child: BranchSelector()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            if (app.can('sales.create'))
              FilledButton.icon(
                onPressed: app.currentBranchId == null ? null : _counterSale,
                icon: const Icon(Icons.point_of_sale),
                label: const Text('Counter Sale'),
              ),
            if (app.can('sales.create'))
              FilledButton.tonalIcon(
                onPressed: app.currentBranchId == null ? null : _createCustomer,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('New Customer'),
              ),
            if (app.can('sales.receipt.create'))
              FilledButton.tonalIcon(
                onPressed: app.currentBranchId == null ? null : _receipt,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Customer Receipt'),
              ),
          ]),
        ),
        if (message != null) Padding(padding: const EdgeInsets.all(12), child: Text(message!)),
        Expanded(
          child: app.currentBranchId == null
              ? const Center(child: Text('Branch select karein.'))
              : AsyncPanel(
                  key: ValueKey('${app.currentBranchId}-$refresh'),
                  future: api.get(ApiPaths.customers, query: {'branch_id': app.currentBranchId}),
                  emptyMessage: 'Customer master empty hai.',
                  builder: (context, data) => RecordsList(
                    rows: (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
                  ),
                ),
        ),
      ]),
    );
  }


  Future<void> _createCustomer() async {
    final app = ref.read(appStateProvider);
    final name = TextEditingController();
    final mobile = TextEditingController();
    final email = TextEditingController();
    final address = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('New Customer'),
      content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Customer Name')),
        const SizedBox(height: 10), TextField(controller: mobile, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile')),
        const SizedBox(height: 10), TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
        const SizedBox(height: 10), TextField(controller: address, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Address')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, name.text.trim().isNotEmpty), child: const Text('Create'))],
    ));
    final payload = {'branch_id': app.currentBranchId, 'name': name.text.trim(), 'mobile': mobile.text.trim(), 'email': email.text.trim(), 'address': address.text.trim()};
    name.dispose(); mobile.dispose(); email.dispose(); address.dispose();
    if (ok != true) return;
    try { await ref.read(apiClientProvider).post(ApiPaths.customers, data: payload); if (mounted) setState(() { refresh++; message = 'Customer create ho gaya.'; }); }
    catch (e) { if (mounted) setState(() => message = e.toString()); }
  }

  Future<void> _counterSale() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    try {
      final results = await Future.wait([
        api.get(ApiPaths.products),
        api.get(ApiPaths.availableStock, query: {'branch_id': app.currentBranchId}),
        api.get(ApiPaths.customers, query: {'branch_id': app.currentBranchId}),
        api.get(ApiPaths.financeBootstrap),
      ]);
      final products = (results[0] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final productById = {for (final p in products) int.parse('${p['id']}'): p};
      final stock = (results[1] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => int.tryParse('${e['custodian_key']}') == 0 && (double.tryParse('${e['quantity']}') ?? 0) > 0)
          .toList();
      final customers = (results[2] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final finance = Map<String, dynamic>.from(results[3] as Map);
      final accounts = (finance['accounts'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => '${e['type']}' == 'asset' && const {'cash', 'bank', 'upi'}.contains('${e['subtype']}'.toLowerCase()))
          .toList();
      if (stock.isEmpty) throw Exception('Selected branch me sale ke liye available stock nahi hai.');

      int? customerId;
      int? accountId;
      final paid = TextEditingController(text: '0');
      final qty = <int, TextEditingController>{for (var i = 0; i < stock.length; i++) i: TextEditingController()};
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Counter Sale'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<int?>(
                    initialValue: customerId,
                    decoration: const InputDecoration(labelText: 'Customer (required for credit)'),
                    items: <DropdownMenuItem<int?>>[
                      const DropdownMenuItem(value: null, child: Text('Cash / Walk-in')),
                      ...customers.map((c) => DropdownMenuItem(value: int.parse('${c['id']}'), child: Text('${c['name']}'))),
                    ],
                    onChanged: (v) => setLocal(() => customerId = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    initialValue: accountId,
                    decoration: const InputDecoration(labelText: 'Cash / Bank / UPI Account'),
                    items: accounts
                        .map((a) => DropdownMenuItem<int?>(value: int.parse('${a['id']}'), child: Text('${a['code']} · ${a['name']}')))
                        .toList(),
                    onChanged: (v) => setLocal(() => accountId = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: paid,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Paid Amount'),
                  ),
                  const SizedBox(height: 16),
                  ...List.generate(stock.length, (i) {
                    final row = stock[i];
                    final pid = int.parse('${row['product_id']}');
                    final p = productById[pid] ?? row;
                    final batchKey = int.tryParse('${row['batch_key']}') ?? 0;
                    final batchLabel = batchKey == 0 ? 'No Batch' : '${row['batch_no'] ?? 'Batch'}';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${row['product_name']}', style: Theme.of(context).textTheme.titleSmall),
                              Text('$batchLabel · Available ${row['quantity']} ${row['uom'] ?? ''}'),
                              Text('Sale ₹${p['sale_price'] ?? 0} · Batch mode ${p['batch_tracking'] ?? 'optional'}'),
                            ]),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: qty[i],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Qty'),
                            ),
                          ),
                        ]),
                      ),
                    );
                  }),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Post Sale')),
            ],
          ),
        ),
      );
      if (ok == true) {
        final lines = <Map<String, dynamic>>[];
        for (var i = 0; i < stock.length; i++) {
          final q = double.tryParse(qty[i]!.text) ?? 0;
          if (q <= 0) continue;
          final available = double.tryParse('${stock[i]['quantity']}') ?? 0;
          if (q > available + .0001) throw Exception('${stock[i]['product_name']} quantity available stock se zyada hai.');
          final batchKey = int.tryParse('${stock[i]['batch_key']}') ?? 0;
          lines.add({
            'product_id': stock[i]['product_id'],
            'quantity': q,
            if (batchKey > 0) 'batch_id': batchKey,
          });
        }
        if (lines.isEmpty) throw Exception('Product quantity required.');
        final paidAmount = double.tryParse(paid.text) ?? 0;
        if (paidAmount > 0 && accountId == null) throw Exception('Received amount ke liye Cash / Bank / UPI account select karein.');
        final r = await api.post(ApiPaths.counterSale, data: {
          'branch_id': app.currentBranchId,
          if (customerId != null) 'customer_id': customerId,
          'paid_amount': paidAmount,
          if (accountId != null) 'payment_account_id': accountId,
          'lines': lines,
        });
        if (mounted) setState(() { message = 'Sale ${(r as Map)['sale_no']} posted.'; refresh++; });
      }
      paid.dispose();
      for (final c in qty.values) c.dispose();
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
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
          setState(() => message = 'Customer receipt ke liye koi posted outstanding sale nahi hai.');
        }
        return;
      }
      final finance = Map<String, dynamic>.from(results[1] as Map);
      final accounts = (finance['accounts'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => '${e['type']}' == 'asset' && const {'cash', 'bank', 'upi'}.contains('${e['subtype']}'.toLowerCase()))
          .toList();
      if (!mounted) return;

      int? saleId;
      int? accountId;
      final amount = TextEditingController();
      final reference = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setLocal) => AlertDialog(
            title: const Text('Customer Receipt'),
            content: SizedBox(
              width: 520,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<int>(
                  initialValue: saleId,
                  decoration: const InputDecoration(labelText: 'Outstanding Sale'),
                  items: openSales.map((sale) {
                    final id = int.parse('${sale['id']}');
                    final label = '${sale['sale_no']} · ${sale['customer_name']} · Due ${sale['outstanding_amount']}';
                    return DropdownMenuItem(value: id, child: Text(label));
                  }).toList(),
                  onChanged: (value) {
                    setLocal(() => saleId = value);
                    if (value != null) {
                      final selected = openSales.firstWhere((sale) => int.parse('${sale['id']}') == value);
                      amount.text = '${selected['outstanding_amount']}';
                    }
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: accountId,
                  decoration: const InputDecoration(labelText: 'Cash / Bank / UPI Account'),
                  items: accounts.map((a) => DropdownMenuItem(
                    value: int.parse('${a['id']}'),
                    child: Text('${a['code']} · ${a['name']}'),
                  )).toList(),
                  onChanged: (v) => setLocal(() => accountId = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Receipt Amount'),
                ),
                const SizedBox(height: 10),
                TextField(controller: reference, decoration: const InputDecoration(labelText: 'Reference')),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final value = double.tryParse(amount.text) ?? 0;
                  Navigator.pop(dialogContext, saleId != null && accountId != null && value > 0);
                },
                child: const Text('Post Receipt'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        await api.post(ApiPaths.customerReceipt, data: {
          'branch_id': branchId,
          'sale_id': saleId,
          'amount': double.tryParse(amount.text) ?? 0,
          'payment_account_id': accountId,
          'reference': reference.text.trim(),
        });
        if (mounted) setState(() { message = 'Customer receipt selected sale par posted.'; refresh++; });
      }
      amount.dispose();
      reference.dispose();
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    }
  }

}
