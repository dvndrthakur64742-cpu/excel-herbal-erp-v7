/// A client-side review of the existing order contract, never payment clearance.
abstract final class PrepaidCart {
  static int? id(Object? raw) => int.tryParse('$raw');
  static int? minor(Object? raw) {
    final match = RegExp(r'^(0|[1-9][0-9]{0,9})(?:\.([0-9]{1,2}))?$')
        .firstMatch('$raw'.trim());
    if (match == null) return null;
    return int.parse(match[1]!) * 100 +
        int.parse((match[2] ?? '').padRight(2, '0'));
  }

  static String key(Map<String, dynamic> row) =>
      '${id(row['product_id'])}|${id(row['batch_key']) ?? 0}';

  static List<Map<String, dynamic>> lines({
    required String channel,
    required List<Map<String, dynamic>> stock,
    required Map<int, String> quantities,
  }) {
    if (!const {'b2c', 'b2b', 'distributor'}.contains(channel)) {
      throw const FormatException('Select a valid sales channel.');
    }
    if (quantities.isEmpty || quantities.length > 100) {
      throw const FormatException('Select 1 to 100 product lines.');
    }
    final seen = <String>{};
    final distributorProducts = <int>{};
    final result = <Map<String, dynamic>>[];
    for (final entry in quantities.entries) {
      if (entry.key < 0 || entry.key >= stock.length) {
        throw const FormatException('Stock selection changed.');
      }
      final row = stock[entry.key];
      final name = '${row['product_name'] ?? 'Product'}';
      final text = entry.value.trim();
      if (!RegExp(r'^[1-9][0-9]{0,5}(?:\.[0-9]{1,3})?$').hasMatch(text)) {
        throw FormatException('$name: enter a valid positive quantity.');
      }
      if (channel == 'distributor' && !RegExp(r'^[1-9][0-9]*$').hasMatch(text)) {
        throw FormatException('$name: distributor quantity must be whole PCS.');
      }
      final available = double.tryParse('${row['quantity']}');
      if (available == null || !available.isFinite ||
          double.parse(text) > available) {
        throw FormatException('$name: quantity exceeds available stock.');
      }
      final product = id(row['product_id']);
      final batch = id(row['batch_key']);
      if (product == null || product < 1 || batch == null || batch < 0 ||
          !seen.add(key(row))) {
        throw FormatException('$name: invalid or duplicate product/batch.');
      }
      // Current server quotes each distributor line independently. Do not
      // silently choose a cross-batch aggregation policy in this UI.
      if (channel == 'distributor' && !distributorProducts.add(product)) {
        throw FormatException('$name: choose one batch per distributor product.');
      }
      result.add({
        'product_id': product,
        'quantity': text,
        if (batch > 0) 'batch_id': batch,
      });
    }
    return result;
  }

  static int lineMinor(int unitMinor, String quantity) {
    // Positive values only; integer arithmetic matches server half-up rounding
    // without losing paise in a large quantity multiplication on the web.
    final parts = quantity.split('.');
    final milli = BigInt.parse(parts.first) * BigInt.from(1000) +
        BigInt.parse((parts.length == 2 ? parts[1] : '').padRight(3, '0'));
    final amount = (BigInt.from(unitMinor) * milli + BigInt.from(500)) ~/
        BigInt.from(1000);
    if (unitMinor <= 0 || amount < BigInt.one ||
        amount > BigInt.from(999999999999)) {
      throw const FormatException('Sale line amount is invalid or out of range.');
    }
    return amount.toInt();
  }

  static int netMinor(Iterable<int> totals, String discount) {
    final gross = totals.fold<int>(0, (sum, amount) => sum + amount);
    final value = minor(discount);
    if (gross <= 0 || gross > 999999999999 || value == null || value >= gross) {
      throw const FormatException('Discount must be valid and below order total.');
    }
    return gross - value;
  }
}
