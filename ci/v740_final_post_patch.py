from pathlib import Path

root = Path('flutter-app')
my_work = root / 'lib/screens/my_work/my_work_screen.dart'
text = my_work.read_text()

# Make Evening Closing guidance match the Wholesale Yes/No state.
old_help = """                        Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: ExcelBrand.primarySoft,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.calculate_outlined,
                                color: ExcelBrand.primaryDark,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Return aur Wholesale quantity enter karein. Retail Sold quantity ERP automatically calculate karega.',
                                ),
                              ),
                            ],
                          ),
                        ),
"""
new_help = """                        Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: ExcelBrand.primarySoft,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.calculate_outlined,
                                color: ExcelBrand.primaryDark,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  wholesaleEnabled
                                      ? 'Return, Wholesale Qty aur Wholesale Rate enter karein. Retail Sold ERP automatically calculate karega.'
                                      : 'Sirf Return Qty enter karein. Retail Sold ERP automatically calculate karega.',
                                ),
                              ),
                            ],
                          ),
                        ),
"""
if old_help in text:
    text = text.replace(old_help, new_help, 1)

start = text.index('  Future<void> _finalPost(int id) async {')
end = text.index('  Future<void> _showDaily(int id) async {', start)

new_final = r'''  Future<void> _finalPost(int id) async {
    final api = ref.read(apiClientProvider);
    final d = await _dailyDetail(id);
    final evening = Map<String, dynamic>.from(
      (d['evening'] as Map?) ?? const {},
    );
    final lines = ((evening['lines'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (lines.isEmpty) throw Exception('Evening closing lines not found.');

    final summaries = <Map<String, dynamic>>[];
    var calculatedExpected = 0.0;
    for (final line in lines) {
      final issued = BusinessFormat.number(line['issued_quantity']) ?? 0;
      final returned =
          BusinessFormat.number(
            line['return_quantity'] ?? line['return_qty'],
          ) ??
          0;
      final wholesaleQty =
          BusinessFormat.number(line['wholesale_quantity']) ?? 0;
      final soldRaw = BusinessFormat.number(
        line['sold_quantity'] ?? line['sold_qty'],
      );
      final retailSold = soldRaw?.toDouble() ??
          DailyOrderMath.retailSold(issued, returned, wholesaleQty);
      final retailRate =
          BusinessFormat.number(
            line['retail_rate'] ?? line['sale_price'] ?? line['rate'],
          ) ??
          0;
      final wholesaleRate =
          BusinessFormat.number(line['wholesale_rate']) ?? 0;
      final retailAmount =
          BusinessFormat.number(
            line['retail_amount'] ?? line['sold_amount'],
          )?.toDouble() ??
          retailSold * retailRate.toDouble();
      final wholesaleAmount =
          BusinessFormat.number(line['wholesale_amount'])?.toDouble() ??
          wholesaleQty.toDouble() * wholesaleRate.toDouble();
      final lineTotal =
          BusinessFormat.number(line['total_amount'] ?? line['amount'])
              ?.toDouble() ??
          retailAmount + wholesaleAmount;
      calculatedExpected += lineTotal;
      summaries.add({
        'name': '${line['product_name'] ?? 'Product'}',
        'issued': issued,
        'returned': returned,
        'retail_sold': retailSold,
        'wholesale_qty': wholesaleQty,
        'retail_rate': retailRate,
        'wholesale_rate': wholesaleRate,
        'retail_amount': retailAmount,
        'wholesale_amount': wholesaleAmount,
        'line_total': lineTotal,
      });
    }

    final backendExpected = BusinessFormat.number(
      evening['expected_amount'] ?? evening['total_amount'],
    )?.toDouble();
    final expected = backendExpected ?? calculatedExpected;
    final reconciliationDifference = backendExpected == null
        ? 0.0
        : (backendExpected - calculatedExpected).abs();

    final cash = TextEditingController(text: expected.toStringAsFixed(2));
    final upi = TextEditingController(text: '0');
    bool? confirmed;

    try {
      if (!mounted) return;
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocal) {
            final cashValue = BusinessFormat.number(cash.text)?.toDouble() ?? 0;
            final upiValue = BusinessFormat.number(upi.text)?.toDouble() ?? 0;
            final deposit = cashValue + upiValue;
            final matched = DailyOrderMath.depositMatches(deposit, expected);

            Widget paymentField({
              required TextEditingController controller,
              required String label,
              required IconData icon,
            }) => TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setLocal(() {}),
              decoration: InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon),
                prefixText: '₹ ',
              ),
            );

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.fact_check_outlined),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Final Post · Daily Order #$id')),
                ],
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 720,
                  maxHeight: MediaQuery.sizeOf(context).height * .72,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sold Products & Amounts',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      ...summaries.map((item) {
                        final wholesaleQty = item['wholesale_qty'] as num;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        BusinessFormat.displayName(
                                          '${item['name']}',
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                    Text(
                                      BusinessFormat.money(item['line_total']),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Retail ${BusinessFormat.quantity(item['retail_sold'])} × ${BusinessFormat.money(item['retail_rate'])} = ${BusinessFormat.money(item['retail_amount'])}',
                                ),
                                if (wholesaleQty > 0) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    'Wholesale ${BusinessFormat.quantity(wholesaleQty)} × ${BusinessFormat.money(item['wholesale_rate'])} = ${BusinessFormat.money(item['wholesale_amount'])}',
                                  ),
                                ],
                                const SizedBox(height: 3),
                                Text(
                                  'Return ${BusinessFormat.quantity(item['returned'])} · Issued ${BusinessFormat.quantity(item['issued'])}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: ExcelBrand.primarySoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Expected Deposit',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Text(
                                  BusinessFormat.money(expected),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: ExcelBrand.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                            if (reconciliationDifference > .01) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Server total ${BusinessFormat.money(backendExpected)} · Product calculation ${BusinessFormat.money(calculatedExpected)}. Posting server expected total ke against verify hoga.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Deposit Breakdown',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 520) {
                            return Column(
                              children: [
                                paymentField(
                                  controller: cash,
                                  label: 'Cash Deposit',
                                  icon: Icons.payments_outlined,
                                ),
                                const SizedBox(height: 10),
                                paymentField(
                                  controller: upi,
                                  label: 'Online / UPI',
                                  icon: Icons.account_balance_outlined,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(
                                child: paymentField(
                                  controller: cash,
                                  label: 'Cash Deposit',
                                  icon: Icons.payments_outlined,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: paymentField(
                                  controller: upi,
                                  label: 'Online / UPI',
                                  icon: Icons.account_balance_outlined,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: matched
                              ? ExcelBrand.primarySoft
                              : const Color(0xFFFFECEC),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              matched
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              color: matched
                                  ? ExcelBrand.primaryDark
                                  : ExcelBrand.danger,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Total Cash Deposit = Cash + Online = ${BusinessFormat.money(deposit)}\nRequired ${BusinessFormat.money(expected)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: matched
                                      ? ExcelBrand.primaryDark
                                      : ExcelBrand.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
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
                FilledButton.icon(
                  onPressed: matched
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  icon: const Icon(Icons.post_add_outlined),
                  label: const Text('Final Post'),
                ),
              ],
            );
          },
        ),
      );

      if (confirmed == true) {
        final c = BusinessFormat.number(cash.text)?.toDouble() ?? 0;
        final u = BusinessFormat.number(upi.text)?.toDouble() ?? 0;
        if (!DailyOrderMath.depositMatches(c + u, expected)) {
          throw Exception(
            'Cash + Online expected amount ke barabar hona chahiye.',
          );
        }
        await api.post(ApiPaths.finalPost(id), data: {'cash': c, 'upi': u});
        if (mounted) {
          setState(() {
            refresh++;
            message = 'Daily Order completed and posted.';
          });
        }
      }
    } finally {
      cash.dispose();
      upi.dispose();
    }
  }

'''

text = text[:start] + new_final + text[end:]
my_work.write_text(text)
