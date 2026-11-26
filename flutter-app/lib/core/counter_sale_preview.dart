import 'whole_pcs.dart';

/// Local review only. The server remains the price, stock and payment authority.
class CounterSalePreview {
  const CounterSalePreview({
    required this.lines,
    required this.gross,
    required this.quantity,
    this.error,
  });

  final List<Map<String, dynamic>> lines;
  final double gross;
  final int quantity;
  final String? error;

  static CounterSalePreview fromSelection({
    required List<Map<String, dynamic>> stock,
    required Map<int, Map<String, dynamic>> products,
    required List<String> quantities,
  }) {
    final lines = <Map<String, dynamic>>[];
    var gross = 0.0;
    var quantity = 0;
    CounterSalePreview invalid(String message) => CounterSalePreview(
        lines: const [], gross: 0, quantity: 0, error: message);
    if (quantities.length != stock.length) {
      return invalid('Stock selection changed. Reopen the sale.');
    }
    for (var i = 0; i < stock.length; i++) {
      final row = stock[i];
      final name = '${row['product_name'] ?? 'Product'}';
      int q;
      try {
        q = WholePcs.parseOrZero(quantities[i]);
      } on FormatException {
        return invalid('$name: enter a valid whole PCS quantity.');
      }
      if (q <= 0) continue;
      final available = double.tryParse('${row['quantity']}');
      if (available == null || !available.isFinite || q > available + .0001) {
        return invalid('$name: quantity exceeds available stock.');
      }
      final productId = int.tryParse('${row['product_id']}');
      final product = products[productId];
      final rate = double.tryParse('${product?['sale_price'] ?? 0}');
      if (productId == null || rate == null || !rate.isFinite || rate <= 0) {
        return invalid('$name does not have a valid sale price.');
      }
      final batchKey = int.tryParse('${row['batch_key']}') ?? 0;
      lines.add({
        'product_id': row['product_id'],
        'quantity': q,
        if (batchKey > 0) 'batch_id': batchKey,
      });
      quantity += q;
      gross += q * rate;
      if (!gross.isFinite) return invalid('Sale total is invalid.');
    }
    return CounterSalePreview(
      lines: List.unmodifiable(lines),
      gross: gross,
      quantity: quantity,
    );
  }
}
