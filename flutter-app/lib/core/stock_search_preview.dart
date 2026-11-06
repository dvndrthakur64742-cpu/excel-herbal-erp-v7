import 'business_format.dart';
import 'stock_custody_text.dart';

/// Read-only stock search preview. Records remain owned and filtered by
/// the existing inventory API; this never changes branch authority or stock.
class StockSearchPreview {
  const StockSearchPreview._();

  static List<MapEntry<String, dynamic>> fields(
    Map<String, dynamic> stock, {
    required String selectedBranchName,
  }) {
    final branch = selectedBranchName.trim();
    final quantity = BusinessFormat.number(stock['quantity']);
    final quantityAndUnit = quantity == null
        ? 'Not available'
        : '${BusinessFormat.quantity(quantity)} ${StockCustodyText.unit(stock)}';
    return <MapEntry<String, dynamic>>[
      MapEntry('search_branch', branch.isEmpty ? 'Selected branch' : branch),
      MapEntry('search_custodian', StockCustodyText.holder(stock)),
      MapEntry('search_quantity', quantityAndUnit),
    ];
  }
}
