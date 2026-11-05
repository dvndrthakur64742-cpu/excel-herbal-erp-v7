/// Read-only frontend guidance for prepaid invoices.
/// Backend enforces the authoritative payment/discount/stock/branch rules.
/// All currency arithmetic is exact integer paise, not floating point.
class PrepaidInvoiceReadiness {
  const PrepaidInvoiceReadiness({
    required this.canPost,
    required this.message,
    this.remainingPaise,
    this.awaitingUpiVerification = false,
  });

  final bool canPost;
  final String message;
  final int? remainingPaise;
  final bool awaitingUpiVerification;

  static int? _money(dynamic value) {
    final text = value?.toString().trim() ?? '';
    final match =
        RegExp(r'^(0|[1-9][0-9]{0,9})(?:\.([0-9]{1,2}))?$')
            .firstMatch(text);
    if (match == null) return null;
    final rupees = int.tryParse(match.group(1)!);
    if (rupees == null) return null;
    final paise = (match.group(2) ?? '').padRight(2, '0');
    return rupees * 100 + int.parse(paise);
  }

  static String format(int paise) =>
      '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

  static PrepaidInvoiceReadiness check({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> payments,
  }) {
    final status = '${order['status']}';
    if (status == 'discount_pending') {
      return const PrepaidInvoiceReadiness(
        canPost: false,
        message: 'Next: discount approval by an authorised reviewer.',
      );
    }
    if (status == 'posted') {
      return const PrepaidInvoiceReadiness(
        canPost: false,
        message: 'Invoice already posted. Review its invoice number below.',
      );
    }
    if (status != 'approved') {
      return const PrepaidInvoiceReadiness(
        canPost: false,
        message: 'Order is not approved for collection or invoicing.',
      );
    }
    final amount = _money(order['net_amount']);
    if (amount == null || amount <= 0) {
      return const PrepaidInvoiceReadiness(
        canPost: false,
        message: 'Unable to verify order amount. Refresh before proceeding.',
      );
    }
    var confirmed = 0;
    var pendingUpi = false;
    for (final payment in payments) {
      final paymentStatus = '${payment['status']}';
      if (paymentStatus == 'pending') {
        pendingUpi = true;
        continue;
      }
      if (paymentStatus != 'confirmed') continue;
      if (!const {'cash', 'upi'}.contains('${payment['method']}')) {
        return const PrepaidInvoiceReadiness(
          canPost: false,
          message: 'Unrecognised payment method. Refresh before proceeding.',
        );
      }
      final paid = _money(payment['amount']);
      if (paid == null || paid <= 0) {
        return const PrepaidInvoiceReadiness(
          canPost: false,
          message: 'Invalid collection details. Refresh before proceeding.',
        );
      }
      confirmed += paid;
      if (confirmed > amount) {
        return const PrepaidInvoiceReadiness(
          canPost: false,
          message: 'Confirmed payments exceed this order. Contact Finance.',
        );
      }
    }
    if (pendingUpi) {
      return PrepaidInvoiceReadiness(
        canPost: false,
        message: 'Next: Finance must independently verify pending UPI payment.',
        remainingPaise: amount - confirmed,
        awaitingUpiVerification: true,
      );
    }
    if (confirmed < amount) {
      final remaining = amount - confirmed;
      return PrepaidInvoiceReadiness(
        canPost: false,
        message:
            'Next: collect and confirm remaining ₹${format(remaining)} before posting.',
        remainingPaise: remaining,
      );
    }
    return const PrepaidInvoiceReadiness(
      canPost: true,
      message:
          '100% Cash / verified UPI recorded. Review invoice and stock before posting.',
      remainingPaise: 0,
    );
  }
}
