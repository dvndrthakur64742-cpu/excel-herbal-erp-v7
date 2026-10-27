import 'package:flutter/material.dart';

import '../core/whole_pcs.dart';
import '../theme/excel_brand.dart';

/// Original server-stock line used by the Counter Sale dialog.
/// Responsive presentation only; quantity and price are validated by caller.
class V8SaleStockLine extends StatelessWidget {
  const V8SaleStockLine({
    super.key,
    required this.productName,
    required this.batchLabel,
    required this.availableText,
    required this.salePriceText,
    required this.batchModeText,
    required this.quantityController,
  });

  final String productName;
  final String batchLabel;
  final String availableText;
  final String salePriceText;
  final String batchModeText;
  final TextEditingController quantityController;

  @override
  Widget build(BuildContext context) {
    final styles = Theme.of(context).textTheme;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(productName,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: styles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text('$batchLabel · Available $availableText',
          style: styles.bodySmall),
        const SizedBox(height: 4),
        Text('Sale ₹$salePriceText · Batch mode $batchModeText',
          style: styles.bodySmall?.copyWith(
            color: ExcelBrand.primaryDark, fontWeight: FontWeight.w600)),
      ],
    );
    final quantity = SizedBox(
      width: 115,
      child: TextField(
        controller: quantityController,
        keyboardType: TextInputType.number,
        inputFormatters: [WholePcs.positiveFormatter],
        decoration: const InputDecoration(labelText: 'Qty'),
      ),
    );
    return Card(
      key: const ValueKey('v8-sale-stock-line'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < 380) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: 10),
                quantity,
              ],
            );
          }
          return Row(children: [
            Expanded(child: details),
            const SizedBox(width: 12),
            quantity,
          ]);
        }),
      ),
    );
  }
}
