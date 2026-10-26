import 'package:flutter/material.dart';

/// A human confirmation about the meaning of canonical V7 final-post:
/// Cash/UPI are *reported* amounts. Final-post is not independent proof
/// of physical cash handover or bank-confirmed UPI settlement.
abstract final class V8ReportedTenderGuard {
  static bool canConfirm({
    required String cashText,
    required String upiText,
    required bool amountsValid,
    required bool acknowledged,
  }) =>
      cashText.trim().isNotEmpty &&
      upiText.trim().isNotEmpty &&
      amountsValid &&
      acknowledged;
}

class V8ReportedTenderDisclosure extends StatelessWidget {
  const V8ReportedTenderDisclosure({
    super.key,
    required this.acknowledged,
    required this.onChanged,
  });

  final bool acknowledged;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('v8-reported-tender-disclosure'),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(14),
        color: colors.surfaceContainerLow,
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: colors.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cash and UPI are reported payment amounts. '
                  'Final Post records stock, sales and accounting entries; '
                  'it does NOT verify employee-to-cashier physical cash '
                  'handover or independent bank/UPI settlement.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            key: const ValueKey('v8-tender-proof-ack'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            value: acknowledged,
            onChanged: (value) => onChanged(value == true),
            title: const Text(
              'I checked the source amounts and understand that separate '
              'cashier receipt and bank evidence are still required.',
            ),
          ),
        ],
      ),
    );
  }
}
