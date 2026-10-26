import 'package:flutter/material.dart';

import '../core/whole_pcs.dart';
import '../theme/excel_brand.dart';

/// Pure presentation for one canonical Evening Closing issue line.
/// Quantities, rates, and posting are still validated and written only by
/// the existing parent closing form and authenticated REST API.
class V8EveningClosingLine extends StatelessWidget {
  const V8EveningClosingLine({
    super.key,
    required this.productName,
    required this.issuedLabel,
    required this.soldLabel,
    required this.retailRateLabel,
    required this.wholesaleEnabled,
    required this.wholesaleQuantity,
    required this.overIssued,
    required this.returnController,
    required this.wholesaleController,
    required this.wholesaleRateController,
    required this.onQuantityChanged,
  });

  final String productName;
  final String issuedLabel;
  final String soldLabel;
  final String retailRateLabel;
  final bool wholesaleEnabled;
  final int wholesaleQuantity;
  final bool overIssued;
  final TextEditingController returnController;
  final TextEditingController wholesaleController;
  final TextEditingController wholesaleRateController;
  final VoidCallback onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = theme.textTheme;
    return Card(
      key: const ValueKey('v8-evening-settlement-line'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(productName,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: styles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                _SettlementValue(label: 'Issued', value: '$issuedLabel PCS'),
                _SettlementValue(
                  label: 'Retail sold', value: '$soldLabel PCS',
                  warning: overIssued),
                if (wholesaleEnabled)
                  _SettlementValue(label: 'Retail rate', value: '₹$retailRateLabel'),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, limits) {
                const gap = 10.0;
                final twoColumns = limits.maxWidth >= 305;
                final fieldWidth = twoColumns
                    ? (limits.maxWidth - gap) / 2
                    : limits.maxWidth;
                return Wrap(spacing: gap, runSpacing: 12, children: [
                  SizedBox(
                    width: fieldWidth,
                    child: _pcsInput(
                      label: 'Return Qty',
                      controller: returnController,
                      onChanged: onQuantityChanged,
                    ),
                  ),
                  if (wholesaleEnabled) ...[
                    SizedBox(
                      width: fieldWidth,
                      child: _pcsInput(
                        label: 'Wholesale Qty',
                        controller: wholesaleController,
                        onChanged: onQuantityChanged,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: TextField(
                        controller: wholesaleRateController,
                        enabled: wholesaleQuantity > 0,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => onQuantityChanged(),
                        decoration: InputDecoration(
                          labelText: 'Wholesale Rate ₹',
                          hintText: wholesaleQuantity > 0
                              ? '0.00' : 'Enter wholesale qty first',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ]);
              },
            ),
            if (overIssued) ...[
              const SizedBox(height: 9),
              Semantics(
                liveRegion: true,
                child: Text(
                  'Return + Wholesale Qty issued quantity se zyada nahi ho sakta.',
                  style: styles.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pcsInput({
    required String label,
    required TextEditingController controller,
    required VoidCallback onChanged,
  }) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [WholePcs.positiveFormatter],
    onChanged: (_) => onChanged(),
    decoration: InputDecoration(
      labelText: label,
      hintText: '0',
      isDense: true,
      border: const OutlineInputBorder(),
    ),
  );
}

class _SettlementValue extends StatelessWidget {
  const _SettlementValue({
    required this.label, required this.value, this.warning = false,
  });
  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: warning
          ? Theme.of(context).colorScheme.errorContainer
          : ExcelBrand.primarySoft,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
          style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w900,
          color: warning ? Theme.of(context).colorScheme.error
              : ExcelBrand.primaryDark,
        )),
      ],
    ),
  );
}
