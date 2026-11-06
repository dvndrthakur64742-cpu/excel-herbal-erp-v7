import 'business_format.dart';

/// Display-only projection of a branch-scoped stock transfer.
///
/// The backend decides which transfers are visible. Do not use these labels
/// to grant authority, infer a quantity across different units, or mutate
/// original transfer records.
class TransferListPresentation {
  const TransferListPresentation._();

  static Map<String, dynamic> row(
    Map<String, dynamic> transfer,
    List<Map<String, dynamic>> authorisedBranches,
  ) {
    String branchLabel(String nameKey, String idKey) {
      final serverName = '${transfer[nameKey] ?? ''}'.trim();
      if (serverName.isNotEmpty && serverName.toLowerCase() != 'null') {
        return serverName;
      }
      final id = int.tryParse('${transfer[idKey] ?? ''}') ?? 0;
      for (final branch in authorisedBranches) {
        if (id > 0 && int.tryParse('${branch['id'] ?? ''}') == id) {
          final name = '${branch['name'] ?? ''}'.trim();
          if (name.isNotEmpty) return name;
        }
      }
      return id > 0 ? 'Branch #$id' : 'Unknown branch';
    }

    final id = int.tryParse('${transfer['id'] ?? ''}');
    final lines = int.tryParse('${transfer['line_count'] ?? ''}');
    String items = 'View items';
    if (lines == 0) {
      items = 'No items';
    } else if (lines == 1) {
      final quantity = BusinessFormat.number(transfer['single_quantity']);
      final unit = '${transfer['single_uom'] ?? ''}'.trim();
      items = quantity != null && quantity > 0 && unit.isNotEmpty
          ? '${BusinessFormat.quantity(quantity)} $unit'
          : '1 item';
    } else if (lines != null && lines > 1) {
      items = '$lines line items';
    }

    return <String, dynamic>{
      ...transfer,
      'transfer_number': id != null && id > 0
          ? 'Transfer #$id'
          : 'Transfer',
      'source_branch_name': branchLabel('source_branch_name', 'source_branch_id'),
      'destination_branch_name':
          branchLabel('destination_branch_name', 'destination_branch_id'),
      'items_summary': items,
    };
  }
}
