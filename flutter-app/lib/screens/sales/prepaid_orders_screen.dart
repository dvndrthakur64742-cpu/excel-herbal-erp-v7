
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../core/prepaid_invoice_readiness.dart';
import '../../core/entry_form_scope.dart';
import '../../core/business_format.dart';
import 'prepaid_cart_dialog.dart';
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
  bool _creating = false;
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
    final app = ref.read(appStateProvider);
    final branch = app.currentBranchId;
    if (!mounted || _busy || _creating || branch == null || !app.can('sales.create')) return;
    final api = ref.read(apiClientProvider);
    final scope = EntryFormScope(app, api);
    bool current() => mounted &&
        scope.matches(ref.read(appStateProvider), ref.read(apiClientProvider));
    setState(() { _creating = true; _error = null; });
    try {
      final fetched = await Future.wait([
        api.get(ApiPaths.availableStock, query: {'branch_id': branch}),
        api.get(ApiPaths.customers, query: {'branch_id': branch}),
        api.get(ApiPaths.products),
      ]);
      if (!current()) return;
      final stock = (fetched[0] as List).map(_map)
          .where((r) => (_id(r['custodian_key']) ?? 0) == 0 &&
              (double.tryParse(r['quantity'].toString()) ?? 0) > 0).toList();
      final customers = (fetched[1] as List).map(_map).toList();
      final products = <int, Map<String, dynamic>>{};
      for (final p in (fetched[2] as List).map(_map)) {
        final id = _id(p['id']);
        if (id != null) products[id] = p;
      }
      if (stock.isEmpty) {
        setState(() => _error = 'No saleable branch stock.');
        return;
      }
      final payload = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PrepaidCartDialog(
          branch: branch, branchName: app.currentBranchName,
          stock: stock, customers: customers, products: products,
          quote: (product, quantity) async {
            if (!current()) throw StateError('ERP scope changed.');
            final data = _map(await api.get(ApiPaths.distributorQuote,
              query: {'product_id': product, 'quantity': quantity}));
            if (!current()) throw StateError('ERP scope changed.');
            return data;
          },
        ),
      );
      if (payload == null || !mounted) return;
      if (!current()) {
        setState(() => _error = 'ERP scope changed. Open a new order before submitting.');
        return;
      }
      // One explicit confirmation, one mutation, using the captured authority.
      final created = _map(await api.post(ApiPaths.prepaidOrders, data: payload));
      if (current()) await _reload(id: _id(created['id']));
    } catch (e) {
      if (mounted) setState(() => _error = UiError.message(e));
    } finally {
      if (mounted) setState(() => _creating = false);
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
    if (branch != _branch && !_busy && !_creating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_busy && !_creating) _reload();
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
            onPressed: (_busy || _creating) ? null : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PrepaidReturnsScreen(),
              ),
            ),
            tooltip: 'Review prepaid returns',
            icon: const Icon(Icons.assignment_return_outlined),
          ),
        IconButton(onPressed: (_busy || _creating) ? null : _reload,
          icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
      ]),
      body: SafeArea(child: Column(children: [
        const Padding(padding: EdgeInsets.all(12),
          child: Text('B2C · B2B · Distributor. No credit. Full verified payment before invoice.')),
        if (app.can('sales.create') && branch != null)
          FilledButton.icon(onPressed: (_busy || _creating) ? null : _create,
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Create prepaid order')),
        if (_busy || _creating) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.all(12),
          child: Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (order != null) Card(margin: const EdgeInsets.all(12),
          child: Padding(padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Order ${order['order_no']}",
                style: Theme.of(context).textTheme.titleMedium),
              Text("Status: ${order['status']} · Net ₹${order['net_amount']}"),
              OutlinedButton.icon(
                onPressed: (_busy || _creating) ? null : () {
                  final lines = (_detail?['lines'] as List? ?? const []).map(_map).toList();
                  showDialog<void>(context: context, builder: (ctx) => AlertDialog(
                    title: const Text('Saved order lines'),
                    scrollable: true,
                    content: SizedBox(width: 560, child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final line in lines) ...[
                          Text("Product #${line['product_id']} | Batch #${line['batch_id'] ?? 'None'}"),
                          Text("Qty ${BusinessFormat.quantity(line['quantity'])} | Rate ${BusinessFormat.money(line['list_unit_price'])} | Total ${BusinessFormat.money(line['line_total'])}"),
                          const Divider(),
                        ],
                        if (lines.isEmpty) const Text('No saved lines available.'),
                        Text("Saved payable: ${BusinessFormat.money(order['net_amount'])}"),
                      ],
                    )),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
                  ));
                },
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('View saved order lines'),
              ),
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
                  OutlinedButton(onPressed: (_busy || _creating) ? null : () =>
                    _confirm('Approve discount',
                      'Only approve within your own authorized branch / Head Office limit.',
                      ApiPaths.prepaidApproveDiscount(_id(order['id'])!), _id(order['id'])!),
                    child: const Text('Approve discount')),
                if (order['status'] == 'approved' &&
                    app.can('sales.receipt.create') &&
                    invoice?.remainingPaise != null &&
                    invoice!.remainingPaise! > 0 &&
                    !invoice.awaitingUpiVerification)
                  OutlinedButton(onPressed: (_busy || _creating) ? null : () =>
                    _collect(order, invoice.remainingPaise!),
                    child: const Text('Record Cash / UPI')),
                if (order['status'] == 'approved' &&
                    app.can('sales.create') && invoice?.canPost == true)
                  FilledButton(onPressed: (_busy || _creating) ? null : () =>
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
                    ? TextButton(onPressed: (_busy || _creating) ? null : () => _verify(p),
                        child: const Text('Verify bank')) : null),
              if (order['status'] == 'posted') ...[
                Text("Invoice #${order['sale_id']} posted with stock and journal."),
                if (app.can('finance.reversal.create'))
                  OutlinedButton.icon(
                    onPressed: (_busy || _creating) ? null : () => _requestReturn(order),
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
                    onTap: _busy || _creating || id == null ? null : () => _reload(id: id),
                  );
                })),
      ])),
    );
  }
}
