import 'package:flutter/material.dart';

import '../core/business_format.dart';
import '../core/counter_sale_preview.dart';
import '../core/transaction_guardrails.dart';

class CounterBillingSummary extends StatelessWidget {
  const CounterBillingSummary({
    super.key,
    required this.preview,
    required this.paid,
  });

  final CounterSalePreview preview;
  final double? paid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final validPaid = paid != null && paid!.isFinite && paid! >= 0;
    final validCart = preview.error == null;
    final remaining = validPaid && validCart ? preview.gross - paid! : null;
    final paymentLabel = remaining == null
        ? 'Check payment amount'
        : preview.lines.isEmpty
            ? 'Select products'
            : remaining > TransactionGuardrails.moneyTolerance
                ? 'Remaining cash: ${BusinessFormat.money(remaining)}'
                : remaining < -TransactionGuardrails.moneyTolerance
                    ? 'Excess cash: ${BusinessFormat.money(-remaining)}'
                    : 'Entered cash matches estimated total';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Billing summary', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('${preview.lines.length} selected lines · ${preview.quantity} PCS'),
            const SizedBox(height: 8),
            Text(
              validCart ? BusinessFormat.money(preview.gross) : 'Unavailable',
              style: theme.textTheme.headlineSmall,
            ),
            const Text('Estimated sale total'),
            const Divider(),
            Text(paymentLabel),
            if (preview.error != null)
              Text(preview.error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 4),
            const Text('Server confirms the final price and stock before posting.'),
          ],
        ),
      ),
    );
  }
}
