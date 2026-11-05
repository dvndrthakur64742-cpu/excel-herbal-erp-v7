
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../core/prepaid_invoice_readiness.dart';
import '../../state/app_state.dart';
import 'prepaid_returns_screen.dart';

/// Review-first prepaid sales. All money and stock authority remains server-side.
class PrepaidOrdersScreen extends ConsumerStatefulWidget {
  const PrepaidOrdersScreen({super.key});

  @override
  ConsumerState<PrepaidOrdersScreen> createState() => _PrepaidOrdersScreenState();
}

class _PrepaidOrdersScreenState extends ConsumerState<PrepaidOrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  Map<String, dynamic>? _detail;
  int? _branch;
  int? _orderId;
  bool _busy = false;
  String? _error;

  int? _id(dynamic value) => int.tryParse(value.toString());
  Map<String, dynamic> _map(dynamic value) =>
      Map<String, dynamic>.from(value as Map);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload({int? id}) async {
    final branch = ref.read(appStateProvider).currentBranchId;
    if (branch == null) {
      if (!mounted) return;
      setState(() {
        _branch = null;
        _orders = [];
        _orderId = null;
        _detail = null;
        _busy = false;
        _error = null;
      });
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final rows = await api.get(ApiPaths.prepaidOrders,
          query: {'branch_id': branch});
      final selected = id ?? (branch == _branch ? _orderId : null);
      final details = selected == null
          ? null : _map(await api.get(ApiPaths.prepaidOrder(selected)));
      // Discard an old branch's async response after the selected branch moves.
      if (!mounted ||
          ref.read(appStateProvider).currentBranchId != branch) return;
      setState(() {
        _branch = branch;
        _orders = (rows as List).map(_map).toList();
        _orderId = selected;
        _detail = details;
      });
    } catch (e) {
      if (mounted) setState(() => _error = UiError.message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit(Future<dynamic> Function() action, {int? id}) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await action();
      if (!mounted) return;
      setState(() => _busy = false);
      await _reload(id: id);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = UiError.message(e); });
    }
  }

  Future<void> _create() async {
    final branch = ref.read(appStateProvider).currentBranchId;
    if (branch == null) return;
    try {
      final api = ref.read(apiClientProvider);
      final fetched = await Future.wait([
        api.get(ApiPaths.availableStock, query: {'branch_id': branch}),
        api.get(ApiPaths.customers, query: {'branch_id': branch}),
      ]);
      final stock = (fetched[0] as List).map(_map)
          .where((r) => (_id(r['custodian_key']) ?? 0) == 0 &&
              (double.tryParse(r['quantity'].toString()) ?? 0) > 0).toList();
      final customers = (fetched[1] as List).map(_map).toList();
      if (!mounted) return;
      if (stock.isEmpty) {
        setState(() => _error = 'No saleable branch stock.');
        return;
      }
      String channel = 'b2c';
      int? customerId;
      int? stockIndex;
      final quantity = TextEditingController(text: '1');
      final discount = TextEditingController(text: '0.00');
      final reason = TextEditingController();
      final form = GlobalKey<FormState>();
      final payload = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, change) => AlertDialog(
            title: const Text('Create prepaid order'),
            scrollable: true,
            content: SizedBox(width: 540, child: Form(
              key: form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: channel,
                  decoration: const InputDecoration(labelText: 'Sales channel'),
                  items: const [
                    DropdownMenuItem(value: 'b2c', child: Text('B2C / Walk-in')),
                    DropdownMenuItem(value: 'b2b', child: Text('B2B')),
                    DropdownMenuItem(value: 'distributor', child: Text('Distributor')),
                  ],
                  onChanged: (v) => change(() { channel = v ?? 'b2c'; customerId = null; }),
                ),
                DropdownButtonFormField<int>(
                  initialValue: customerId,
                  decoration: InputDecoration(labelText: channel == 'b2c'
                      ? 'Customer (optional)' : 'Registered customer *'),
                  items: customers.map((c) => DropdownMenuItem<int>(
                    value: _id(c['id']), child: Text(c['name'].toString()),
                  )).toList(),
                  onChanged: (v) => change(() => customerId = v),
                  validator: (v) => channel != 'b2c' && v == null
                      ? 'Registered customer required.' : null,
                ),
                DropdownButtonFormField<int>(
                  initialValue: stockIndex,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Product / batch *'),
                  items: List.generate(stock.length, (i) => DropdownMenuItem(
                    value: i,
                    child: Text("${stock[i]['product_name']} · Available ${stock[i]['quantity']}",
                        overflow: TextOverflow.ellipsis),
                  )),
                  onChanged: (v) => change(() => stockIndex = v),
                  validator: (v) => v == null ? 'Select a product.' : null,
                ),
                TextFormField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quantity *'),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (!RegExp(r'^[1-9][0-9]{0,5}(\.[0-9]{1,3})?$').hasMatch(text)) {
                      return 'Enter valid positive quantity.';
                    }
                    if (channel == 'distributor' && !RegExp(r'^[1-9][0-9]*$').hasMatch(text)) {
                      return 'Distributor quantity must be whole PCS.';
                    }
                    if (stockIndex != null &&
                        (double.tryParse(text) ?? 0) >
                        (double.tryParse(stock[stockIndex!]['quantity'].toString()) ?? 0)) {
                      return 'Quantity exceeds branch stock.';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: discount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Discount amount (₹)'),
                  validator: (v) => RegExp(r'^(0|[1-9][0-9]{0,9})(\.[0-9]{1,2})?$')
                      .hasMatch((v ?? '').trim()) ? null : 'Invalid discount amount.',
                ),
                TextFormField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'Discount reason'),
                  validator: (_) => (double.tryParse(discount.text) ?? 0) > 0 &&
                      reason.text.trim().length < 5 ? 'Explain discount.' : null,
                ),
                const SizedBox(height: 12),
                const Text('Order first. Invoice only after approved discount and 100% confirmed Cash / verified UPI.'),
              ]),
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  if (!form.currentState!.validate() || stockIndex == null) return;
                  final item = stock[stockIndex!];
                  final batch = _id(item['batch_key']) ?? 0;
                  Navigator.pop(ctx, {
                    'branch_id': branch,
                    'channel': channel,
                    if (customerId != null) 'customer_id': customerId,
                    'lines': [{
                      'product_id': _id(item['product_id']),
                      'quantity': quantity.text.trim(),
                      if (batch > 0) 'batch_id': batch,
                    }],
                    'discount_amount': discount.text.trim(),
                    'discount_reason': reason.text.trim(),
                  });
                },
                child: const Text('Create order'),
              ),
            ],
          ),
        ),
      );
      quantity.dispose(); discount.dispose(); reason.dispose();
      if (payload == null) return;
      int? createdId;
      await _submit(() async {
        final response = _map(await api.post(ApiPaths.prepaidOrders, data: payload));
        createdId = _id(response['id']);
      });
      if (createdId != null && mounted) await _reload(id: createdId);
    } catch (e) {
      if (mounted) setState(() => _error = UiError.message(e));
    }
  }

  /// This only opens return intake; no payout, stock or journal reversal.
  Future<void> _requestReturn(Map<String, dynamic> order) async {
    final id = _id(order['id']);
    if (id == null || _busy) return;
    final reason = TextEditingController();
    final form = GlobalKey<FormState>();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request full prepaid return'),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('The original invoice stays posted. '
                'Return approval and supporting evidence do NOT issue '
                'a refund or credit note.'),
            TextFormField(
              controller: reason,
              maxLength: 255,
              decoration: const InputDecoration(labelText: 'Return reason'),
              validator: (value) => (value ?? '').trim().length >= 10
                  ? null : 'Please enter at least 10 characters.',
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(ctx, reason.text.trim());
            }
          }, child: const Text('Request return')),
        ],
      ),
    );
    reason.dispose();
    if (input == null || !mounted) return;
    await _submit(
      () => ref.read(apiClientProvider).post(
        ApiPaths.prepaidReturnRequest(id), data: {'reason': input}),
      id: id,
    );
    if (!mounted || _error != null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PrepaidReturnsScreen(),
      ),
    );
  }

  Future<void> _collect(Map<String, dynamic> order, int remainingPaise) async {
    try {
      final api = ref.read(apiClientProvider);
      final branch = ref.read(appStateProvider).currentBranchId;
      if (branch == null) return;
      final accounts = (await api.get(ApiPaths.prepaidPaymentAccounts,
          query: {'branch_id': branch}) as List).map(_map).toList();
      if (!mounted) return;
      int? accountId;
      final amount = TextEditingController();
      final reference = TextEditingController();
      final form = GlobalKey<FormState>();
      final payload = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, change) {
          final account = accounts.where((a) => _id(a['id']) == accountId).toList();
          final isUpi = account.isNotEmpty &&
              account.first['subtype'].toString().toLowerCase() == 'upi';
          return AlertDialog(
            title: const Text('Record Cash / UPI collection'),
            content: SizedBox(width: 440, child: Form(key: form, child:
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text("Net payable: ₹${order['net_amount']}"),
                DropdownButtonFormField<int>(
                  initialValue: accountId,
                  decoration: const InputDecoration(labelText: 'Payment account *'),
                  items: accounts.map((a) => DropdownMenuItem<int>(
                    value: _id(a['id']), child: Text(a['name'].toString()),
                  )).toList(),
                  onChanged: (v) => change(() => accountId = v),
                  validator: (v) => v == null ? 'Choose account.' : null,
                ),
                TextFormField(controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Received amount ₹ *'),
                  validator: (v) =>
                      PrepaidInvoiceReadiness.collectionAmountError(
                        (v ?? '').trim(), remainingPaise),
                ),
                if (isUpi) TextFormField(controller: reference,
                  decoration: const InputDecoration(labelText: 'UPI transaction ID *'),
                  validator: (v) => (v ?? '').trim().length >= 6
                      ? null : 'UPI reference required.'),
                const SizedBox(height: 8),
                Text(isUpi ? 'UPI is pending until a different Finance employee verifies bank evidence.'
                    : 'Cash is confirmed; posting still requires total full payment.'),
              ]),
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(onPressed: () {
                if (!form.currentState!.validate()) return;
                Navigator.pop(ctx, {
                  'payment_account_id': accountId,
                  'amount': amount.text.trim(),
                  'method': isUpi ? 'upi' : 'cash',
                  if (isUpi) 'reference': reference.text.trim(),
                });
              }, child: const Text('Record')),
            ],
          );
        }),
      );
      amount.dispose(); reference.dispose();
      if (payload == null) return;
      final id = _id(order['id']);
      if (id != null) await _submit(() => api.post(
          ApiPaths.prepaidOrderPayments(id), data: payload), id: id);
    } catch (e) {
      if (mounted) setState(() => _error = UiError.message(e));
    }
  }

  Future<void> _verify(Map<String, dynamic> payment) async {
    final evidence = TextEditingController();
    final form = GlobalKey<FormState>();
    bool attested = false;
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, change) => AlertDialog(
        title: const Text('Independent UPI verification'),
        content: SizedBox(width: 440, child: Form(key: form, child:
          Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Verify the payment in a bank statement, not only a customer screenshot.'),
            TextFormField(controller: evidence,
              decoration: const InputDecoration(labelText: 'Bank evidence reference'),
              validator: (v) => (v ?? '').trim().length >= 6 ? null : 'Bank reference required.'),
            CheckboxListTile(value: attested,
              title: const Text('I independently checked the bank evidence.'),
              onChanged: (v) => change(() => attested = v ?? false)),
          ]),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: attested ? () {
            if (form.currentState!.validate()) Navigator.pop(ctx, evidence.text.trim());
          } : null, child: const Text('Verify UPI')),
        ],
      )),
    );
    evidence.dispose();
    final id = _id(payment['id']);
    if (id != null && input != null) {
      await _submit(() => ref.read(apiClientProvider).post(
        ApiPaths.prepaidVerifyUpi(id),
        data: {'bank_evidence_ref': input},
      ), id: _orderId);
    }
  }

  Future<void> _confirm(String title, String text, String path, int id) async {
    final accepted = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title), content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm')),
        ],
      ),
    );
    if (accepted != true) return;
    await _submit(() => ref.read(apiClientProvider).post(path), id: id);
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final branch = app.currentBranchId;
    if (branch != _branch && !_busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_busy) _reload();
      });
    }
    // Never display or act on a previous branch's order during a switch.
    final branchReady = branch != null && branch == _branch;
    final order = !branchReady || _detail == null
        ? null : _map(_detail!['order']);
    final payments = !branchReady || _detail == null
        ? <Map<String, dynamic>>[]
        : (_detail!['payments'] as List).map(_map).toList();
    final visibleOrders = branchReady ? _orders : <Map<String, dynamic>>[];
    final invoice = order == null ? null : PrepaidInvoiceReadiness.check(
      order: order,
      payments: payments,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Prepaid Sales Orders'), actions: [
        if (branch != null && app.can('sales.view'))
          IconButton(
            onPressed: _busy ? null : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PrepaidReturnsScreen(),
              ),
            ),
            tooltip: 'Review prepaid returns',
            icon: const Icon(Icons.assignment_return_outlined),
          ),
        IconButton(onPressed: _busy ? null : _reload,
          icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
      ]),
      body: SafeArea(child: Column(children: [
        const Padding(padding: EdgeInsets.all(12),
          child: Text('B2C · B2B · Distributor. No credit. Full verified payment before invoice.')),
        if (app.can('sales.create') && branch != null)
          FilledButton.icon(onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Create prepaid order')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.all(12),
          child: Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (order != null) Card(margin: const EdgeInsets.all(12),
          child: Padding(padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Order ${order['order_no']}",
                style: Theme.of(context).textTheme.titleMedium),
              Text("Status: ${order['status']} · Net ₹${order['net_amount']}"),
              if (invoice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    invoice.message,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              Wrap(spacing: 8, children: [
                if (order['status'] == 'discount_pending' &&
                    (app.can('sales.discount.approve') ||
                     app.can('sales.discount.ho.approve')))
                  OutlinedButton(onPressed: _busy ? null : () =>
                    _confirm('Approve discount',
                      'Only approve within your own authorized branch / Head Office limit.',
                      ApiPaths.prepaidApproveDiscount(_id(order['id'])!), _id(order['id'])!),
                    child: const Text('Approve discount')),
                if (order['status'] == 'approved' &&
                    app.can('sales.receipt.create') &&
                    invoice?.remainingPaise != null &&
                    invoice!.remainingPaise! > 0 &&
                    !invoice.awaitingUpiVerification)
                  OutlinedButton(onPressed: _busy ? null : () =>
                    _collect(order, invoice.remainingPaise!),
                    child: const Text('Record Cash / UPI')),
                if (order['status'] == 'approved' &&
                    app.can('sales.create') && invoice?.canPost == true)
                  FilledButton(onPressed: _busy ? null : () =>
                    _confirm('Post invoice',
                      'This posts inventory and accounts only after 100% confirmed Cash / verified UPI.',
                      ApiPaths.prepaidPost(_id(order['id'])!), _id(order['id'])!),
                    child: const Text('Post fully paid invoice')),
              ]),
              for (final p in payments)
                ListTile(dense: true,
                  title: Text("${p['method']} ₹${p['amount']} · ${p['status']}"),
                  trailing: p['method'] == 'upi' && p['status'] == 'pending' &&
                      app.can('finance.bank_reconcile')
                    ? TextButton(onPressed: _busy ? null : () => _verify(p),
                        child: const Text('Verify bank')) : null),
              if (order['status'] == 'posted') ...[
                Text("Invoice #${order['sale_id']} posted with stock and journal."),
                if (app.can('finance.reversal.create'))
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _requestReturn(order),
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: const Text('Request full-order return'),
                  ),
              ],
            ]),
          )),
        const Divider(),
        Expanded(child: branch == null
          ? const Center(child: Text('Select an authorized branch.'))
          : visibleOrders.isEmpty
            ? Center(child: Text(branchReady
                ? 'No prepaid orders in this branch.'
                : 'Loading authorised branch orders...'))
            : ListView.builder(
                itemCount: visibleOrders.length,
                itemBuilder: (ctx, i) {
                  final o = visibleOrders[i];
                  final id = _id(o['id']);
                  return ListTile(
                    selected: _orderId == id,
                    title: Text("${o['order_no']} · ${o['channel']}"),
                    subtitle: Text("${o['status']} · ₹${o['net_amount']}"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy || id == null ? null : () => _reload(id: id),
                  );
                })),
      ])),
    );
  }
}
