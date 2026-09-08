from pathlib import Path

p = Path('flutter-app/lib/screens/my_work/my_work_screen.dart')
s = p.read_text()

start = s.index('  Future<void> _additionalDaily(int id) async {')
end = s.index('\n\n  Future<void> _issueDaily', start)
replacement = r'''  Future<void> _additionalDaily(int id) async {
    final api = ref.read(apiClientProvider);
    final data = Map<String, dynamic>.from(
      await api.get(ApiPaths.masterData) as Map,
    );
    final products = ((data['products'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (products.isEmpty) throw Exception('Product master empty hai.');

    final qty = <int, TextEditingController>{
      for (final product in products)
        int.parse('${product['id']}'): TextEditingController(),
    };
    final ok = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Additional Requirement',
                          style: Theme.of(sheetContext).textTheme.titleLarge,
                        ),
                        Text(
                          'Order #$id · whole PCS only',
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: const Row(
                children: [
                  Expanded(
                    child: Text(
                      'Product',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  SizedBox(
                    width: 82,
                    child: Text(
                      'Extra Qty',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                itemCount: products.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = products[index];
                  final productId = int.parse('${product['id']}');
                  return SizedBox(
                    height: 54,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            BusinessFormat.displayName('${product['name']}'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 82,
                          child: TextField(
                            controller: qty[productId],
                            keyboardType: TextInputType.number,
                            inputFormatters: [WholePcs.positiveFormatter],
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              hintText: '0',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        child: const Text('Submit Additional'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    try {
      if (ok == true) {
        final lines = <Map<String, dynamic>>[];
        for (final product in products) {
          final productId = int.parse('${product['id']}');
          final value = WholePcs.parseOrZero(qty[productId]!.text);
          if (value > 0) {
            lines.add({'product_id': productId, 'quantity': value});
          }
        }
        if (lines.isEmpty) {
          throw Exception('Kam se kam ek additional product required hai.');
        }
        await api.post(ApiPaths.dailyAdditional(id), data: {'lines': lines});
        if (mounted) {
          setState(() {
            refresh++;
            message = 'Additional requirement submitted for approval.';
          });
        }
      }
    } finally {
      for (final controller in qty.values) controller.dispose();
    }
  }'''
s = s[:start] + replacement + s[end:]

block_start = s.index(
    '                        ...lines.map((l) {',
    s.index('  Future<void> _editEvening'),
)
block_end = s.index('                        const SizedBox(height: 2),', block_start)
compact = r'''                        if (!wholesaleEnabled)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            child: const Row(
                              children: [
                                Expanded(child: Text('Product', style: TextStyle(fontWeight: FontWeight.w800))),
                                SizedBox(width: 48, child: Text('Issue', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800))),
                                SizedBox(width: 48, child: Text('Sold', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800))),
                                SizedBox(width: 76, child: Text('Return', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800))),
                              ],
                            ),
                          )
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: 570,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                child: const Row(
                                  children: [
                                    SizedBox(width: 170, child: Text('Product', style: TextStyle(fontWeight: FontWeight.w800))),
                                    SizedBox(width: 58, child: Text('Issue', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800))),
                                    SizedBox(width: 76, child: Text('Return', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800))),
                                    SizedBox(width: 76, child: Text('W.Qty', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800))),
                                    SizedBox(width: 104, child: Text('W.Rate', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800))),
                                    SizedBox(width: 58, child: Text('Sold', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800))),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const Divider(height: 1),
                        ...lines.map((l) {
                          final key = int.parse('${l['issue_line_id']}');
                          final issued = double.tryParse('${l['issued_quantity']}') ?? 0;
                          final retailRate = double.tryParse('${l['retail_rate']}') ?? 0;
                          final ret = WholePcs.parseOrZero(returns[key]!.text);
                          final wh = wholesaleEnabled
                              ? WholePcs.parseOrZero(wholesale[key]!.text)
                              : 0;
                          final sold = DailyOrderMath.retailSold(issued, ret, wh);
                          final over = ret + wh > issued + .0001;
                          final productName = BusinessFormat.displayName(
                            '${l['product_name'] ?? 'Product'}',
                          );

                          InputDecoration qtyDecoration(String hint) => InputDecoration(
                                hintText: hint,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 9,
                                ),
                              );

                          Widget returnField(double width) => SizedBox(
                                width: width,
                                child: TextField(
                                  controller: returns[key],
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [WholePcs.positiveFormatter],
                                  textAlign: TextAlign.center,
                                  onChanged: (_) => setLocal(() {}),
                                  decoration: qtyDecoration('0'),
                                ),
                              );

                          if (!wholesaleEnabled) {
                            return Container(
                              constraints: const BoxConstraints(minHeight: 54),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: over
                                    ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: .45)
                                    : null,
                                border: const Border(
                                  bottom: BorderSide(color: ExcelBrand.border),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      productName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 48,
                                    child: Text(
                                      BusinessFormat.quantity(issued),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 48,
                                    child: Text(
                                      BusinessFormat.quantity(sold),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: over ? ExcelBrand.danger : ExcelBrand.primaryDark,
                                      ),
                                    ),
                                  ),
                                  returnField(76),
                                ],
                              ),
                            );
                          }

                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: 570,
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 56),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: over
                                      ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: .45)
                                      : null,
                                  border: const Border(
                                    bottom: BorderSide(color: ExcelBrand.border),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 170,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            productName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          Text(
                                            'Retail ₹${retailRate.toStringAsFixed(2)}',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 58,
                                      child: Text(
                                        BusinessFormat.quantity(issued),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    returnField(76),
                                    SizedBox(
                                      width: 76,
                                      child: TextField(
                                        controller: wholesale[key],
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [WholePcs.positiveFormatter],
                                        textAlign: TextAlign.center,
                                        onChanged: (_) => setLocal(() {}),
                                        decoration: qtyDecoration('0'),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 104,
                                      child: TextField(
                                        controller: wholesaleRate[key],
                                        enabled: wh > 0,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        textAlign: TextAlign.center,
                                        decoration: qtyDecoration(wh > 0 ? '₹ rate' : '—'),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 58,
                                      child: Text(
                                        BusinessFormat.quantity(sold),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: over ? ExcelBrand.danger : ExcelBrand.primaryDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
'''
s = s[:block_start] + compact + s[block_end:]
p.write_text(s)
