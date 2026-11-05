class StockAllocationException implements Exception {
  const StockAllocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class StockAllocation {
  static List<Map<String, dynamic>> fefo({
    required Iterable<Map<String, dynamic>> requestLines,
    required Iterable<Map<String, dynamic>> stock,
  }) {
    final stockRows = stock
        .map((row) => Map<String, dynamic>.from(row))
        .where(
          (row) =>
              (int.tryParse('${row['custodian_key']}') ?? 0) == 0 &&
              (double.tryParse('${row['quantity']}') ?? 0) > 0,
        )
        .toList();
    final remainingByIndex = <int, double>{
      for (var i = 0; i < stockRows.length; i++)
        i: double.tryParse('${stockRows[i]['quantity']}') ?? 0,
    };
    final allocations = <Map<String, dynamic>>[];

    for (final request in requestLines) {
      var remaining = double.tryParse('${request['quantity']}') ?? 0;
      if (remaining <= 0) {
        throw StockAllocationException(
          '${request['product_name'] ?? 'Product'} approved issue quantity missing.',
        );
      }
      final productId = int.tryParse('${request['product_id']}');
      final requestLineId = int.tryParse('${request['id']}');
      if (productId == null || requestLineId == null) {
        throw const StockAllocationException(
            'Approved request line invalid hai.');
      }

      final candidateIndexes = <int>[
        for (var i = 0; i < stockRows.length; i++)
          if (int.tryParse('${stockRows[i]['product_id']}') == productId) i,
      ]..sort(
          (a, b) => '${stockRows[a]['expires_on'] ?? '9999-12-31'}'.compareTo(
            '${stockRows[b]['expires_on'] ?? '9999-12-31'}',
          ),
        );

      for (final index in candidateIndexes) {
        if (remaining <= 0.0001) break;
        final available = remainingByIndex[index] ?? 0;
        if (available <= 0) continue;
        final take = available < remaining ? available : remaining;
        final row = stockRows[index];
        final batchKey = int.tryParse('${row['batch_key']}') ?? 0;
        allocations.add({
          'request_line_id': requestLineId,
          'quantity': take,
          if (batchKey > 0) 'batch_id': batchKey,
        });
        remainingByIndex[index] = available - take;
        remaining -= take;
      }

      if (remaining > 0.0001) {
        throw StockAllocationException(
          '${request['product_name'] ?? 'Product'} ka authorised branch stock insufficient hai.',
        );
      }
    }

    return allocations;
  }
}
