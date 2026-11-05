import 'package:flutter/material.dart';

/// Explicit maker confirmation before a draft is saved and submitted.
/// Returns false on Review Quantities/back navigation; does not write data.
Future<bool> confirmEveningClosingSubmission(BuildContext context) async {
  final decision = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Confirm Evening Submission'),
      content: const Text(
        'Please verify Return and Wholesale Qty for every issued product. '
        'All remaining PCS will be recorded as Retail Sold. '
        'After submission you cannot edit this closing. '
        'A separate authorised reviewer must complete Final Post. Continue?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Review Quantities'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Confirm & Submit'),
        ),
      ],
    ),
  );
  return decision == true;
}
