import 'package:flutter/material.dart';

import '../core/whole_pcs.dart';
import '../theme/excel_brand.dart';

/// Presentation-only guide. A draft or submitted request is not labelled as
/// approved or issued until the original backend confirms that transition.
class V8StockRequestSteps extends StatelessWidget {
  const V8StockRequestSteps({super.key});

  static const _steps = [
    '1  Select & submit',
    '2  ASM approval',
    '3  Stock issue',
    '4  Evening closing',
  ];

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('v8-stock-request-steps'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ExcelBrand.surface,
          border: Border.all(color: ExcelBrand.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'STOCK REQUEST WORKFLOW',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .9,
                color: ExcelBrand.primaryDark,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < _steps.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: i == 0
                          ? ExcelBrand.primarySoft
                          : ExcelBrand.canvas,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _steps[i],
                      style: TextStyle(
                        color: i == 0
                            ? ExcelBrand.primaryDark
                            : ExcelBrand.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
}

/// Wraps the selected-only filter beneath the summary on narrow screens.
class V8StockSelectionBar extends StatelessWidget {
  const V8StockSelectionBar({
    super.key,
    required this.summary,
    required this.selectedOnly,
    required this.enabled,
    required this.onSelected,
  });

  final String summary;
  final bool selectedOnly;
  final bool enabled;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('v8-stock-selection-bar'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final label = Text(
              summary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            );
            final filter = FilterChip(
              key: const ValueKey('v8-stock-selected-only'),
              label: const Text('Selected only'),
              selected: selectedOnly,
              onSelected: enabled ? onSelected : null,
            );
            if (constraints.maxWidth < 390) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label,
                  const SizedBox(height: 4),
                  filter,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: label),
                const SizedBox(width: 8),
                filter,
              ],
            );
          },
        ),
      );
}

/// One editable stock line. A narrow card gives the product and whole-PCS
/// quantity their own rows; the wide version keeps the scan-friendly table.
class V8StockRequestProductLine extends StatelessWidget {
  const V8StockRequestProductLine({
    super.key,
    required this.name,
    required this.sku,
    required this.commercial,
    required this.quantity,
    required this.selectedQuantity,
    required this.enabled,
    required this.onChanged,
  });

  final String name;
  final String sku;
  final String commercial;
  final TextEditingController quantity;
  final num selectedQuantity;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          final showCommercial = constraints.maxWidth >= 520;
          final meta = [
            if (sku.isNotEmpty) 'SKU $sku',
            if (!showCommercial && commercial.isNotEmpty) commercial,
          ].join(' · ');
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  meta,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          );
          final input = SizedBox(
            width: compact ? 132 : 108,
            child: TextField(
              controller: quantity,
              enabled: enabled,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [WholePcs.positiveFormatter],
              textAlign: TextAlign.right,
              onChanged: onChanged,
              decoration: const InputDecoration(
                hintText: '0',
                suffixText: 'PCS',
                isDense: true,
              ),
            ),
          );
          return Container(
            key: const ValueKey('v8-stock-product-line'),
            color: selectedQuantity > 0
                ? ExcelBrand.primarySoft
                : Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      details,
                      const SizedBox(height: 8),
                      Row(children: [
                        const Expanded(
                          child: Text(
                            'Qty (PCS)',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        input,
                      ]),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: details),
                      if (showCommercial)
                        SizedBox(
                          width: 138,
                          child: Text(
                            commercial.isEmpty ? '—' : commercial,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      const SizedBox(width: 12),
                      input,
                    ],
                  ),
          );
        },
      );
}
