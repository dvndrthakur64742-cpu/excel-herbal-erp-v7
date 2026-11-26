/// Estimate supplier totals using the server's four-place cost and two-place
/// line rounding. This is a review aid, not an accounting authority.
abstract final class PurchaseBillPreview {
  static double? total(Iterable<({String quantity, String unitCost})> lines) {
    var minor = BigInt.zero;
    for (final line in lines) {
      final quantity = line.quantity.trim();
      final cost = line.unitCost.trim();
      final q = int.tryParse(quantity);
      if (!RegExp(r'^\d+$').hasMatch(quantity) ||
          q == null || q <= 0 || q > 9007199254740991 ||
          !RegExp(r'^\d{1,10}(?:\.\d{1,4})?$').hasMatch(cost)) {
        return null;
      }
      final parts = cost.split('.');
      final tenThousandths = BigInt.parse(parts.first) * BigInt.from(10000) +
          BigInt.parse((parts.length == 2 ? parts[1] : '').padRight(4, '0'));
      minor += (tenThousandths * BigInt.from(q) + BigInt.from(50)) ~/ BigInt.from(100);
      if (minor > BigInt.from(99999999999999)) return null;
    }
    return minor.toDouble() / 100;
  }
}
