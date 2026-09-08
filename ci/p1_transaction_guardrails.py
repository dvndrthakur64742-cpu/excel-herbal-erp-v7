from pathlib import Path


def swap(path: str, old: str, new: str, expected: int = 1) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    found = text.count(old)
    if found != expected:
        raise RuntimeError(f'{path}: expected {expected} occurrence(s), found {found}: {old[:120]!r}')
    p.write_text(text.replace(old, new, expected), encoding='utf-8')


SALES = 'flutter-app/lib/screens/sales/sales_screen.dart'
swap(
    SALES,
    "import '../../core/providers.dart';\nimport '../../core/whole_pcs.dart';",
    "import '../../core/providers.dart';\nimport '../../core/transaction_guardrails.dart';\nimport '../../core/whole_pcs.dart';",
)
swap(
    SALES,
    """        if (lines.isEmpty) throw Exception('Product quantity required.');
        final paidAmount = double.tryParse(paid.text) ?? 0;
        if (paidAmount > 0 && accountId == null)
          throw Exception(
            'Received amount ke liye Cash / Bank / UPI account select karein.',
          );
        final r = await api.post(""",
    """        if (lines.isEmpty) throw Exception('Product quantity required.');
        var gross = 0.0;
        for (final line in lines) {
          final productId = int.tryParse('${line['product_id']}');
          final product = productId == null ? null : productById[productId];
          final rate = double.tryParse('${product?['sale_price'] ?? 0}') ?? 0;
          if (rate <= 0) {
            throw Exception('${product?['name'] ?? 'Product'} ka valid Sale Price available nahi hai.');
          }
          gross += (line['quantity'] as num).toDouble() * rate;
        }
        final paidAmount = double.tryParse(paid.text.trim());
        if (paidAmount == null) throw Exception('Paid Amount valid number me enter karein.');
        final guardError = TransactionGuardrails.counterSale(
          gross: gross,
          paid: paidAmount,
          customerId: customerId,
          paymentAccountId: accountId,
        );
        if (guardError != null) throw Exception(guardError);
        final r = await api.post(""",
)
swap(
    SALES,
    """      if (ok == true) {
        await api.post(
          ApiPaths.customerReceipt,""",
    """      if (ok == true) {
        final selected = openSales.firstWhere(
          (sale) => int.tryParse('${sale['id']}') == saleId,
        );
        final outstanding =
            double.tryParse('${selected['outstanding_amount']}') ?? 0;
        final receiptAmount = double.tryParse(amount.text.trim());
        if (receiptAmount == null) {
          throw Exception('Receipt Amount valid number me enter karein.');
        }
        final guardError = TransactionGuardrails.customerReceipt(
          saleId: saleId,
          paymentAccountId: accountId,
          amount: receiptAmount,
          outstanding: outstanding,
        );
        if (guardError != null) throw Exception(guardError);
        await api.post(
          ApiPaths.customerReceipt,""",
)
swap(
    SALES,
    "            'amount': double.tryParse(amount.text) ?? 0,",
    "            'amount': receiptAmount,",
)

PURCHASE = 'flutter-app/lib/screens/purchase/purchase_screen.dart'
swap(
    PURCHASE,
    "import '../../core/providers.dart';\nimport '../../core/whole_pcs.dart';",
    "import '../../core/providers.dart';\nimport '../../core/transaction_guardrails.dart';\nimport '../../core/whole_pcs.dart';",
)
swap(
    PURCHASE,
    """          final q = WholePcs.parseOrZero(qty[id]!.text);
          if (q > 0)
            lines.add({
              'product_id': id,
              'quantity': q,
              'unit_cost': double.tryParse(cost[id]!.text) ?? 0,
              if (batchNo[id]!.text.trim().isNotEmpty)
                'batch_no': batchNo[id]!.text.trim(),
            });""",
    """          final q = WholePcs.parseOrZero(qty[id]!.text);
          if (q <= 0) continue;
          final rawCost = cost[id]!.text.trim();
          final unitCost = double.tryParse(rawCost);
          if (unitCost == null) {
            throw Exception('${p['name']} ka Unit Cost valid number me enter karein. Zero-cost item ke liye 0 explicitly enter karein.');
          }
          final batch = batchNo[id]!.text.trim();
          final guardError = TransactionGuardrails.purchaseLine(
            quantity: q,
            unitCost: unitCost,
            batchRequired: '${p['batch_tracking']}' == 'required',
            batchNo: batch,
          );
          if (guardError != null) throw Exception('${p['name']}: $guardError');
          lines.add({
            'product_id': id,
            'quantity': q,
            'unit_cost': unitCost,
            if (batch.isNotEmpty) 'batch_no': batch,
          });""",
)
swap(
    PURCHASE,
    "                    onChanged: (v) => setLocal(() => billId = v),",
    """                    onChanged: (v) {
                      setLocal(() => billId = v);
                      if (v != null) {
                        final selected = bills.firstWhere(
                          (bill) => int.tryParse('${bill['id']}') == v,
                        );
                        amount.text = '${selected['outstanding_amount']}';
                      }
                    },""",
)
swap(
    PURCHASE,
    """      if (ok == true) {
        await api.post(
          ApiPaths.supplierPayments,""",
    """      if (ok == true) {
        final selected = bills.firstWhere(
          (bill) => int.tryParse('${bill['id']}') == billId,
        );
        final outstanding =
            double.tryParse('${selected['outstanding_amount']}') ?? 0;
        final paymentAmount = double.tryParse(amount.text.trim());
        if (paymentAmount == null) {
          throw Exception('Supplier Payment amount valid number me enter karein.');
        }
        final guardError = TransactionGuardrails.supplierPayment(
          billId: billId,
          paymentAccountId: accountId,
          amount: paymentAmount,
          outstanding: outstanding,
        );
        if (guardError != null) throw Exception(guardError);
        await api.post(
          ApiPaths.supplierPayments,""",
)
swap(
    PURCHASE,
    "            'amount': double.tryParse(amount.text) ?? 0,",
    "            'amount': paymentAmount,",
)

FINANCE = 'flutter-app/lib/screens/finance/finance_screen.dart'
swap(
    FINANCE,
    "import '../../core/providers.dart';\nimport '../../core/overlay_transition.dart';",
    "import '../../core/providers.dart';\nimport '../../core/transaction_guardrails.dart';\nimport '../../core/overlay_transition.dart';",
)
swap(
    FINANCE,
    """      if (ok == true) {
        await api.post(
          ApiPaths.expenses,""",
    """      if (ok == true) {
        final expenseAmount = double.tryParse(amount.text.trim());
        if (expenseAmount == null) {
          throw Exception('Expense amount valid number me enter karein.');
        }
        final guardError = TransactionGuardrails.expense(
          expenseHeadId: head,
          paymentAccountId: account,
          amount: expenseAmount,
        );
        if (guardError != null) throw Exception(guardError);
        await api.post(
          ApiPaths.expenses,""",
)
swap(
    FINANCE,
    "            'amount': double.tryParse(amount.text) ?? 0,",
    "            'amount': expenseAmount,",
)
swap(
    FINANCE,
    """      if (ok == true) {
        final r = await api.post(
          ApiPaths.bankReconciliations,""",
    """      if (ok == true) {
        final rangeError = TransactionGuardrails.dateRange(
          from.text.trim(),
          to.text.trim(),
        );
        if (rangeError != null) throw Exception(rangeError);
        final openingValue = double.tryParse(opening.text.trim());
        final closingValue = double.tryParse(closing.text.trim());
        if (openingValue == null || closingValue == null) {
          throw Exception('Opening aur Closing Balance valid number me enter karein.');
        }
        final r = await api.post(
          ApiPaths.bankReconciliations,""",
)
swap(
    FINANCE,
    "            'opening_balance': double.tryParse(opening.text) ?? 0,\n            'closing_balance': double.tryParse(closing.text) ?? 0,",
    "            'opening_balance': openingValue,\n            'closing_balance': closingValue,",
)
swap(
    FINANCE,
    """    if (ok == true) {
      await _post(ApiPaths.bankImport(id), {
        'lines': [
          {
            'txn_date': date.text.trim(),
            'description': description.text.trim(),
            'reference': reference.text.trim(),
            'debit': double.tryParse(debit.text) ?? 0,
            'credit': double.tryParse(credit.text) ?? 0,
          },
        ],
      }, closeSheet: false);
    }""",
    """    if (ok == true) {
      final debitValue = double.tryParse(debit.text.trim());
      final creditValue = double.tryParse(credit.text.trim());
      if (debitValue == null || creditValue == null) {
        throw Exception('Debit/Credit valid number me enter karein.');
      }
      final guardError = TransactionGuardrails.bankStatementLine(
        date: date.text.trim(),
        debit: debitValue,
        credit: creditValue,
      );
      if (guardError != null) throw Exception(guardError);
      await _post(ApiPaths.bankImport(id), {
        'lines': [
          {
            'txn_date': date.text.trim(),
            'description': description.text.trim(),
            'reference': reference.text.trim(),
            'debit': debitValue,
            'credit': creditValue,
          },
        ],
      }, closeSheet: false);
    }""",
)
swap(
    FINANCE,
    """    if (ok == true)
      await _post(ApiPaths.periodClose, {
        'date_from': from.text.trim(),
        'date_to': to.text.trim(),
      }, closeSheet: false);""",
    """    if (ok == true) {
      final guardError = TransactionGuardrails.dateRange(
        from.text.trim(),
        to.text.trim(),
      );
      if (guardError != null) throw Exception(guardError);
      await _post(ApiPaths.periodClose, {
        'date_from': from.text.trim(),
        'date_to': to.text.trim(),
      }, closeSheet: false);
    }""",
)

print('P1 transaction guardrails patched')
