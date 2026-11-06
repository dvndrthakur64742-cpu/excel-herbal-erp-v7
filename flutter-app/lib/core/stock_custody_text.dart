/// Display-only labels for a branch's stock balances.
/// These labels do not decide which stock can be issued, transferred or sold.
class StockCustodyText {
  const StockCustodyText._();

  static String holder(Map<String, dynamic> stock) {
    final custodianKey = int.tryParse('${stock['custodian_key'] ?? '0'}') ?? 0;
    if (custodianKey == 0) return 'Branch warehouse';
    final name = '${stock['custodian_name'] ?? ''}'.trim();
    return name.isNotEmpty ? 'Employee: $name' : 'Employee #$custodianKey';
  }

  static String unit(Map<String, dynamic> stock) {
    final value = '${stock['uom'] ?? ''}'.trim();
    return value.isEmpty ? 'units' : value;
  }

  static String details(Map<String, dynamic> stock, {String branchName = ''}) {
    final parts = <String>[];
    if (branchName.trim().isNotEmpty) parts.add(branchName.trim());
    final batchName = '${stock['batch_no'] ?? ''}'.trim();
    final batchKey = int.tryParse('${stock['batch_key'] ?? 0}') ?? 0;
    if (batchName.isNotEmpty) {
      parts.add('Batch: $batchName');
    } else if (batchKey > 0) {
      parts.add('Batch #$batchKey');
    }
    final expiry = '${stock['expires_on'] ?? ''}'.trim();
    if (expiry.isNotEmpty && expiry.toLowerCase() != 'null') {
      parts.add('Expiry: $expiry');
    }
    return parts.isEmpty ? 'Selected branch' : parts.join(' · ');
  }
}
