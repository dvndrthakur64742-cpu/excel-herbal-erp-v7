import 'package:flutter/material.dart';

import '../../core/business_format.dart';
import '../../core/prepaid_cart.dart';
import '../../widgets/search_choice_dialog.dart';

class PrepaidCartDialog extends StatefulWidget {
  const PrepaidCartDialog({
    super.key,
    required this.branch,
    required this.branchName,
    required this.stock,
    required this.customers,
    required this.products,
    required this.quote,
  });
  final int branch;
  final String branchName;
  final List<Map<String, dynamic>> stock;
  final List<Map<String, dynamic>> customers;
  final Map<int, Map<String, dynamic>> products;
  final Future<Map<String, dynamic>> Function(int product, int quantity) quote;

  @override
  State<PrepaidCartDialog> createState() => _PrepaidCartDialogState();
}

class _PrepaidCartDialogState extends State<PrepaidCartDialog> {
  String channel = 'b2c';
  int? customer;
  final quantities = <int, TextEditingController>{};
  final discount = TextEditingController(text: '0.00');
  final reason = TextEditingController();
  String? error;
  bool reviewing = false;
  Map<String, dynamic>? payload;
  List<int> totals = [];
  int net = 0;

  @override
  void dispose() {
    for (final c in quantities.values) { c.dispose(); }
    discount.dispose();
    reason.dispose();
    super.dispose();
  }

  String productName(int i) => '${widget.stock[i]['product_name']}';
  String contextLabel(int i) {
    final row = widget.stock[i];
    return "Batch ${row['batch_no'] ?? 'None'} | Expiry ${row['expires_on'] ?? 'Not recorded'} | Available ${row['quantity']} ${row['uom'] ?? ''}";
  }
  String get customerName {
    for (final row in widget.customers) {
      if (PrepaidCart.id(row['id']) == customer) return '${row['name']}';
    }
    return 'Walk-in / no customer';
  }

  Future<void> selectCustomer() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => SearchChoiceDialog(
        title: 'Select customer',
        choices: [
          if (channel == 'b2c') const SearchChoice(0, 'Walk-in / no customer', ''),
          for (final c in widget.customers)
            if ((PrepaidCart.id(c['id']) ?? 0) > 0)
              SearchChoice(PrepaidCart.id(c['id'])!, '${c['name']}', '',
                search: [c['phone'], c['code']]),
        ],
      ),
    );
    if (mounted && picked != null) {
      setState(() { customer = picked == 0 ? null : picked; error = null; });
    }
  }

  Future<void> addProduct() async {
    final keys = quantities.keys.map((i) => PrepaidCart.key(widget.stock[i])).toSet();
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => SearchChoiceDialog(
        title: 'Add product or batch',
        choices: [
          for (var i = 0; i < widget.stock.length; i++)
            if (!keys.contains(PrepaidCart.key(widget.stock[i])))
              SearchChoice(i, productName(i), contextLabel(i), search: [
                widget.products[PrepaidCart.id(widget.stock[i]['product_id'])]?['sku'],
              ]),
        ],
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (quantities.length >= 100) {
        error = 'Maximum 100 product lines.';
      } else if (!quantities.containsKey(picked)) {
        quantities[picked] = TextEditingController(text: '1');
        error = null;
      }
    });
  }

  Future<void> review() async {
    if (reviewing) return;
    setState(() { reviewing = true; error = null; });
    try {
      if (channel != 'b2c' && customer == null) {
        throw const FormatException('Registered customer required.');
      }
      final lines = PrepaidCart.lines(
        channel: channel, stock: widget.stock,
        quantities: quantities.map((i, c) => MapEntry(i, c.text)),
      );
      final discountText = discount.text.trim();
      final discountMinor = PrepaidCart.minor(discountText);
      if (discountMinor == null) throw const FormatException('Invalid discount amount.');
      if (discountMinor > 0 && reason.text.trim().length < 5) {
        throw const FormatException('Explain discount (at least 5 characters).');
      }
      final reviewedTotals = <int>[];
      for (final line in lines) {
        final product = line['product_id'] as int;
        final qty = line['quantity'] as String;
        final int? rate;
        if (channel == 'distributor') {
          final quote = await widget.quote(product, int.parse(qty));
          if (!mounted) return;
          rate = PrepaidCart.minor(quote['unit_price']);
          if (rate == null || PrepaidCart.id(quote['quantity']) != int.parse(qty) ||
              PrepaidCart.minor(quote['line_total']) != PrepaidCart.lineMinor(rate, qty)) {
            throw const FormatException('Distributor quote unavailable or invalid.');
          }
        } else {
          rate = PrepaidCart.minor(widget.products[product]?['sale_price']);
          if (rate == null) throw const FormatException('Sale price unavailable.');
        }
        reviewedTotals.add(PrepaidCart.lineMinor(rate, qty));
      }
      final reviewedNet = PrepaidCart.netMinor(reviewedTotals, discountText);
      if (!mounted) return;
      setState(() {
        totals = reviewedTotals; net = reviewedNet;
        payload = {
          'branch_id': widget.branch,
          'channel': channel,
          if (customer != null) 'customer_id': customer,
          'lines': lines,
          'discount_amount': discountText,
          'discount_reason': reason.text.trim(),
        };
      });
    } catch (e) {
      if (mounted) setState(() {
        error = e is FormatException ? e.message : 'Price review failed. Retry before creating the order.';
      });
    } finally {
      if (mounted) setState(() => reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviewed = payload != null;
    final indexes = quantities.keys.toList();
    return AlertDialog(
      title: Text(reviewed ? 'Review prepaid order' : 'Create prepaid order'),
      scrollable: true,
      content: SizedBox(width: 660, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Branch: ${widget.branchName}'),
          const SizedBox(height: 8),
          if (reviewed) ...[
            Text('Channel: ${channel.toUpperCase()}'),
            Text('Customer: $customerName'),
            const Divider(),
            for (var i = 0; i < indexes.length; i++)
              Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(productName(indexes[i]), style: Theme.of(context).textTheme.titleSmall),
                  Text('Qty ${quantities[indexes[i]]!.text} | ${contextLabel(indexes[i])}'),
                  Text(BusinessFormat.money(totals[i] / 100)),
                ],
              ))),
            Text('Estimated gross: ${BusinessFormat.money(totals.fold<int>(0, (a, b) => a + b) / 100)}'),
            Text('Discount: ${BusinessFormat.money(discount.text)}'),
            const Divider(),
            Text('Estimated payable: ${BusinessFormat.money(net / 100)}',
                style: Theme.of(context).textTheme.titleLarge),
            const Text('Server confirms prices when creating the order. Review the saved total before collecting payment.'),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: channel, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sales channel'),
              items: const [
                DropdownMenuItem(value: 'b2c', child: Text('B2C / Walk-in')),
                DropdownMenuItem(value: 'b2b', child: Text('B2B')),
                DropdownMenuItem(value: 'distributor', child: Text('Distributor')),
              ],
              onChanged: reviewing ? null : (v) => setState(() {
                channel = v ?? 'b2c'; customer = null; error = null;
              }),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: reviewing ? null : selectCustomer,
              icon: const Icon(Icons.person_search_outlined),
              label: Text(customer == null && channel != 'b2c'
                  ? 'Select registered customer *' : customerName),
            ),
            const SizedBox(height: 10),
            Text('Products (${quantities.length}/100)', style: Theme.of(context).textTheme.titleMedium),
            for (final i in indexes)
              Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(child: Text(productName(i), style: Theme.of(context).textTheme.titleSmall)),
                    IconButton(
                      tooltip: 'Remove product',
                      onPressed: reviewing ? null : () {
                        final old = quantities[i]!;
                        setState(() { quantities.remove(i); error = null; });
                        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ]),
                  Text(contextLabel(i)),
                  const SizedBox(height: 8),
                  TextField(
                    key: ValueKey('prepaid-qty-$i'),
                    controller: quantities[i],
                    enabled: !reviewing,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Quantity *'),
                  ),
                ],
              ))),
            OutlinedButton.icon(
              onPressed: reviewing || quantities.length >= 100 ? null : addProduct,
              icon: const Icon(Icons.add), label: const Text('Add product'),
            ),
            const SizedBox(height: 12),
            TextField(controller: discount, enabled: !reviewing,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Discount amount (INR)')),
            const SizedBox(height: 8),
            TextField(controller: reason, enabled: !reviewing,
              decoration: const InputDecoration(labelText: 'Discount reason')),
          ],
          if (reviewing) const LinearProgressIndicator(),
          if (error != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          const SizedBox(height: 12),
          const Text('Invoice only after approved discount and 100% confirmed Cash / verified UPI.'),
        ],
      )),
      actions: [
        TextButton(onPressed: reviewing ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        if (reviewed)
          OutlinedButton(onPressed: () => setState(() { payload = null; }), child: const Text('Edit order')),
        FilledButton(
          onPressed: reviewing ? null : reviewed ? () => Navigator.pop(context, payload) : review,
          child: Text(reviewed ? 'Create order' : 'Review order'),
        ),
      ],
    );
  }
}
