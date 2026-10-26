part of 'my_work_screen.dart';

extension _MyWorkDailyClosingImpl on _MyWorkScreenState {
  Future<void> _editEveningImpl(int id) async {
    final api = ref.read(apiClientProvider);
    final d = await _MyWorkDaily(this)._dailyDetail(id);
    final evening = Map<String, dynamic>.from(
      (d['evening'] as Map?) ?? const {},
    );
    final lines = ((evening['lines'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (lines.isEmpty) throw Exception('Evening lines not found.');

    final returns = <int, TextEditingController>{};
    final wholesale = <int, TextEditingController>{};
    final wholesaleRate = <int, TextEditingController>{};
    for (final l in lines) {
      final key = int.parse('${l['issue_line_id']}');
      returns[key] = TextEditingController(
        text: WholePcs.apiQuantityText(l['return_quantity']),
      );
      wholesale[key] = TextEditingController(
        text: WholePcs.apiQuantityText(l['wholesale_quantity']),
      );
      wholesaleRate[key] = TextEditingController(
        text: '${l['wholesale_rate'] ?? 0}',
      );
    }
    final customer = TextEditingController(
      text: '${evening['wholesale_customer_name'] ?? ''}',
    );
    final note = TextEditingController(text: '${evening['notes'] ?? ''}');
    var wholesaleEnabled = customer.text.trim().isNotEmpty ||
        lines.any(
          (line) =>
              (num.tryParse('${line['wholesale_quantity'] ?? 0}') ?? 0) > 0,
        );
    String? mode;
    String? submitError;
    String? formError;
    var saving = false;
    var allowExit = false;
    var exitPromptOpen = false;
    var submitPromptOpen = false;
    List<String> formSnapshot() => [
      '$wholesaleEnabled',
      for (final c in returns.values) c.text,
      for (final c in wholesale.values) c.text,
      for (final c in wholesaleRate.values) c.text,
      customer.text,
      note.text,
    ];
    final originalSnapshot = formSnapshot();
    bool hasChanges() {
      final current = formSnapshot();
      for (var i = 0; i < current.length; i++) {
        if (current[i] != originalSnapshot[i]) return true;
      }
      return false;
    }

    try {
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setLocal) {
            void closeForm() {
              if (!sheetContext.mounted || allowExit) return;
              setLocal(() => allowExit = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              });
            }

            Future<void> persist(String targetMode) async {
              if (saving || allowExit) return;
              setLocal(() {
                saving = true;
                formError = null;
              });
              try {
                final payload = <Map<String, dynamic>>[];
                var anyWholesale = false;
                for (final l in lines) {
                  final key = int.parse('${l['issue_line_id']}');
                  final ret = WholePcs.parseOrZero(returns[key]!.text);
                  final wh =
                      wholesaleEnabled ? WholePcs.parseOrZero(wholesale[key]!.text) : 0;
                  final issued = double.tryParse('${l['issued_quantity']}') ?? 0;
                  final retailRate = double.tryParse('${l['retail_rate']}') ?? 0;
                  final whRate = wholesaleEnabled
                      ? (double.tryParse(wholesaleRate[key]!.text) ?? 0)
                      : 0;

                  if (ret + wh > issued + 0.0001) {
                    throw Exception(
                      '${l['product_name']}: Return + Wholesale issued quantity se zyada nahi ho sakta.',
                    );
                  }
                  if (wh > 0 && (!whRate.isFinite || whRate <= 0 || whRate > retailRate + .005)) {
                    throw Exception(
                      '${l['product_name']}: Wholesale rate 0 se zyada aur retail rate se kam/equal hona chahiye.',
                    );
                  }
                  if (wh > 0) anyWholesale = true;
                  payload.add({
                    'issue_line_id': key,
                    'return_quantity': ret,
                    'wholesale_quantity': wh,
                    'retail_rate': retailRate,
                    'wholesale_rate': whRate,
                  });
                }

                if (wholesaleEnabled && !anyWholesale) {
                  throw Exception(
                    'Wholesale Yes select kiya hai. Kam se kam ek Wholesale Qty enter karein.',
                  );
                }
                if (wholesaleEnabled && customer.text.trim().isEmpty) {
                  throw Exception('Wholesale customer name required.');
                }

                await api.post(
                  ApiPaths.eveningSave(id),
                  data: {
                    'lines': payload,
                    'wholesale_details': {
                      'wholesale_customer_name':
                          wholesaleEnabled ? customer.text.trim() : '',
                    },
                    'price_reason': note.text.trim(),
                  },
                );
                mode = 'save';
                if (targetMode == 'submit') {
                  try {
                    await api.post(ApiPaths.eveningSubmit(id), data: const {});
                    mode = 'submit';
                  } catch (e) {
                    // The draft is already saved. Refresh the order before
                    // retrying an uncertain submission, rather than saving
                    // over a settlement that may now be submitted.
                    submitError = 'Evening draft saved. Submission could not '
                        'be confirmed: ${UiError.message(e)} '
                        'Check the order status before retrying.';
                  }
                }
                closeForm();
              } catch (e) {
                if (sheetContext.mounted) {
                  setLocal(() {
                    saving = false;
                    formError = UiError.message(e);
                  });
                }
              }
            }

            Future<void> confirmSubmit() async {
              if (saving || allowExit || submitPromptOpen ||
                  !sheetContext.mounted) return;
              submitPromptOpen = true;
              try {
                final confirmed =
                    await confirmEveningClosingSubmission(sheetContext);
                if (confirmed == true && sheetContext.mounted) {
                  await persist('submit');
                }
              } finally {
                submitPromptOpen = false;
              }
            }

            Future<void> requestExit() async {
              if (saving || allowExit || exitPromptOpen) return;
              if (!hasChanges()) {
                closeForm();
                return;
              }
              exitPromptOpen = true;
              final action = await showDialog<String>(
                context: sheetContext,
                barrierDismissible: false,
                builder: (confirmContext) => AlertDialog(
                  title: const Text('Unsaved Evening Closing'),
                  content: const Text(
                    'Save a draft before leaving, or discard your changes.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(confirmContext, 'continue'),
                      child: const Text('Continue Editing'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(confirmContext, 'discard'),
                      child: const Text('Discard'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(confirmContext, 'save'),
                      child: const Text('Save Draft'),
                    ),
                  ],
                ),
              );
              exitPromptOpen = false;
              if (!sheetContext.mounted) return;
              if (action == 'discard') {
                closeForm();
              } else if (action == 'save') {
                await persist('save');
              }
            }

            return PopScope(
              canPop: allowExit,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) requestExit();
              },
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: AbsorbPointer(
                  absorbing: saving,
                  child: DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: .92,
                    minChildSize: .64,
                    maxChildSize: .98,
                    shouldCloseOnMinExtent: false,
                    builder: (context, scrollController) => Material(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: ExcelBrand.primarySoft,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.nightlight_round,
                                    color: ExcelBrand.primaryDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Evening Closing',
                                        style: Theme.of(context).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Daily Order #$id · ${lines.length} products',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Close',
                                  onPressed: saving ? null : requestExit,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(13),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Wholesale sale?',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 8),
                                      SegmentedButton<bool>(
                                        segments: const [
                                          ButtonSegment<bool>(
                                            value: false,
                                            icon: Icon(Icons.close_rounded),
                                            label: Text('No'),
                                          ),
                                          ButtonSegment<bool>(
                                            value: true,
                                            icon: Icon(Icons.storefront_outlined),
                                            label: Text('Yes'),
                                          ),
                                        ],
                                        selected: {wholesaleEnabled},
                                        onSelectionChanged: (selection) {
                                          setLocal(
                                            () => wholesaleEnabled = selection.first,
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        wholesaleEnabled
                                            ? 'Wholesale Qty/Rate enter karein. Discount ka 50% BM Profit aur 50% Salary Fund se ghatega. HO, Office aur Points unchanged rahenge.'
                                            : 'Wholesale No: sirf Return Qty enter karein.',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(13),
                                  decoration: BoxDecoration(
                                    color: ExcelBrand.primarySoft,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.calculate_outlined,
                                        color: ExcelBrand.primaryDark,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          wholesaleEnabled
                                              ? 'Return aur Wholesale enter karein. ERP Retail Sold calculate karega; Wholesale Discount BM Profit aur Salary Fund se 50/50 katega. Limit se zyada discount save nahi hoga.'
                                              : 'Sirf Return Qty enter karein. Retail Sold ERP automatically calculate karega.',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 2, vertical: 6),
                                  child: Text('PRODUCT SETTLEMENT · PCS',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                      letterSpacing: .7,
                                      color: ExcelBrand.primaryDark,
                                    )),
                                ),
                                const SizedBox(height: 7),
                                ...lines.map((l) {
                                  final key = int.parse('${l['issue_line_id']}');
                                  final issued =
                                      double.tryParse('${l['issued_quantity']}') ?? 0;
                                  final retailRate =
                                      double.tryParse('${l['retail_rate']}') ?? 0;
                                  final ret = WholePcs.parseOrZero(returns[key]!.text);
                                  final wh = wholesaleEnabled
                                      ? WholePcs.parseOrZero(wholesale[key]!.text)
                                      : 0;
                                  final sold = DailyOrderMath.retailSold(
                                    issued, ret, wh,
                                  );
                                  final over = ret + wh > issued + .0001;
                                  final productName = BusinessFormat.displayName(
                                    '${l['product_name'] ?? 'Product'}',
                                  );
                                  return V8EveningClosingLine(
                                    key: ValueKey('evening-settlement-$key'),
                                    productName: productName,
                                    issuedLabel: BusinessFormat.quantity(issued),
                                    soldLabel: BusinessFormat.quantity(sold),
                                    retailRateLabel:
                                        retailRate.toStringAsFixed(2),
                                    wholesaleEnabled: wholesaleEnabled,
                                    wholesaleQuantity: wh,
                                    overIssued: over,
                                    returnController: returns[key]!,
                                    wholesaleController: wholesale[key]!,
                                    wholesaleRateController: wholesaleRate[key]!,
                                    onQuantityChanged: () => setLocal(() {}),
                                  );
                                }),
                                const SizedBox(height: 2),
                                if (wholesaleEnabled) ...[
                                  TextField(
                                    controller: customer,
                                    decoration: const InputDecoration(
                                      labelText: 'Wholesale Customer',
                                      hintText: 'Wholesale customer name required',
                                      prefixIcon: Icon(Icons.person_outline_rounded),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                TextField(
                                  controller: note,
                                  minLines: 2,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    labelText: 'Note (optional)',
                                    prefixIcon: Icon(Icons.notes_rounded),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (saving) const LinearProgressIndicator(),
                          if (formError != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  formError!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ),
                          const Divider(height: 1),
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                              child: Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: saving ? null : requestExit,
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: saving ? null : () => persist('save'),
                                    icon: const Icon(Icons.save_outlined),
                                    label: const Text('Save Draft'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: saving ? null : confirmSubmit,
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: const Text('Save & Submit'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

      if (mode == null) return;

      if (mounted) {
        _setFeatureState(() {
          refresh++;
          message = submitError ?? (mode == 'submit'
              ? 'Evening submitted. Final Post pending.'
              : 'Evening draft saved.');
        });
      }
    } finally {
      for (final c in returns.values) c.dispose();
      for (final c in wholesale.values) c.dispose();
      for (final c in wholesaleRate.values) c.dispose();
      customer.dispose();
      note.dispose();
    }
  }

  Future<void> _finalPostImpl(int id) async {
    final api = ref.read(apiClientProvider);
    final d = await _MyWorkDaily(this)._dailyDetail(id);
    final evening = Map<String, dynamic>.from(
      (d['evening'] as Map?) ?? const {},
    );
    final lines = ((evening['lines'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (lines.isEmpty) throw Exception('Evening closing lines not found.');

    final summaries = <Map<String, dynamic>>[];
    var calculatedExpected = 0.0;
    for (final line in lines) {
      final issued = BusinessFormat.number(line['issued_quantity']) ?? 0;
      final returned = BusinessFormat.number(
            line['return_quantity'] ?? line['return_qty'],
          ) ??
          0;
      final wholesaleQty =
          BusinessFormat.number(line['wholesale_quantity']) ?? 0;
      final soldRaw = BusinessFormat.number(
        line['sold_quantity'] ?? line['sold_qty'],
      );
      final retailSold = soldRaw?.toDouble() ??
          DailyOrderMath.retailSold(issued, returned, wholesaleQty);
      final retailRate = BusinessFormat.number(
            line['retail_rate'] ?? line['sale_price'] ?? line['rate'],
          ) ??
          0;
      final wholesaleRate = BusinessFormat.number(line['wholesale_rate']) ?? 0;
      final retailAmount =
          BusinessFormat.number(line['retail_amount'] ?? line['sold_amount'])
                  ?.toDouble() ??
              retailSold * retailRate.toDouble();
      final wholesaleAmount =
          BusinessFormat.number(line['wholesale_amount'])?.toDouble() ??
              wholesaleQty.toDouble() * wholesaleRate.toDouble();
      final lineTotal =
          BusinessFormat.number(line['total_amount'] ?? line['amount'])
                  ?.toDouble() ??
              retailAmount + wholesaleAmount;
      calculatedExpected += lineTotal;
      summaries.add({
        'name': '${line['product_name'] ?? 'Product'}',
        'issued': issued,
        'returned': returned,
        'retail_sold': retailSold,
        'wholesale_qty': wholesaleQty,
        'retail_rate': retailRate,
        'wholesale_rate': wholesaleRate,
        'retail_amount': retailAmount,
        'wholesale_amount': wholesaleAmount,
        'line_total': lineTotal,
      });
    }

    final backendExpected = BusinessFormat.number(
      evening['expected_amount'] ?? evening['total_amount'],
    )?.toDouble();
    final expected = backendExpected ?? calculatedExpected;
    final reconciliationDifference = backendExpected == null
        ? 0.0
        : (backendExpected - calculatedExpected).abs();
    final reconciliationOk = backendExpected == null ||
        DailyOrderMath.reconciliationMatches(
          backendExpected,
          calculatedExpected,
        );

    final cash = TextEditingController(text: expected.toStringAsFixed(2));
    final upi = TextEditingController(text: '0');
    bool? confirmed;

    try {
      if (!mounted) return;
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocal) {
            final cashValue = BusinessFormat.number(cash.text)?.toDouble() ?? 0;
            final upiValue = BusinessFormat.number(upi.text)?.toDouble() ?? 0;
            final deposit = cashValue + upiValue;
            final matched =
                DailyOrderMath.paymentComponentsValid(cashValue, upiValue) &&
                    reconciliationOk &&
                    DailyOrderMath.depositMatches(deposit, expected);

            Widget paymentField({
              required TextEditingController controller,
              required String label,
              required IconData icon,
            }) =>
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setLocal(() {}),
                  decoration: InputDecoration(
                    labelText: label,
                    prefixIcon: Icon(icon),
                    prefixText: '₹ ',
                  ),
                );

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.fact_check_outlined),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Final Post · Daily Order #$id')),
                ],
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 720,
                  maxHeight: MediaQuery.sizeOf(context).height * .72,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sold Products & Amounts',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      ...summaries.map((item) {
                        final wholesaleQty = item['wholesale_qty'] as num;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        BusinessFormat.displayName(
                                          '${item['name']}',
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                    Text(
                                      BusinessFormat.money(item['line_total']),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Retail ${BusinessFormat.quantity(item['retail_sold'])} × ${BusinessFormat.money(item['retail_rate'])} = ${BusinessFormat.money(item['retail_amount'])}',
                                ),
                                if (wholesaleQty > 0) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    'Wholesale ${BusinessFormat.quantity(wholesaleQty)} × ${BusinessFormat.money(item['wholesale_rate'])} = ${BusinessFormat.money(item['wholesale_amount'])}',
                                  ),
                                ],
                                const SizedBox(height: 3),
                                Text(
                                  'Return ${BusinessFormat.quantity(item['returned'])} · Issued ${BusinessFormat.quantity(item['issued'])}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: ExcelBrand.primarySoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Expected Deposit',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Text(
                                  BusinessFormat.money(expected),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: ExcelBrand.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                            if (reconciliationDifference > .01) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Server total ${BusinessFormat.money(backendExpected)} · Product calculation ${BusinessFormat.money(calculatedExpected)}. Final Post blocked hai jab tak dono totals reconcile nahi hote.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Deposit Breakdown',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 520) {
                            return Column(
                              children: [
                                paymentField(
                                  controller: cash,
                                  label: 'Cash Deposit',
                                  icon: Icons.payments_outlined,
                                ),
                                const SizedBox(height: 10),
                                paymentField(
                                  controller: upi,
                                  label: 'Online / UPI',
                                  icon: Icons.account_balance_outlined,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(
                                child: paymentField(
                                  controller: cash,
                                  label: 'Cash Deposit',
                                  icon: Icons.payments_outlined,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: paymentField(
                                  controller: upi,
                                  label: 'Online / UPI',
                                  icon: Icons.account_balance_outlined,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: matched
                              ? ExcelBrand.primarySoft
                              : const Color(0xFFFFECEC),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              matched
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              color: matched
                                  ? ExcelBrand.primaryDark
                                  : ExcelBrand.danger,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Total Cash Deposit = Cash + Online = ${BusinessFormat.money(deposit)}\nRequired ${BusinessFormat.money(expected)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: matched
                                      ? ExcelBrand.primaryDark
                                      : ExcelBrand.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed:
                      matched ? () => Navigator.pop(dialogContext, true) : null,
                  icon: const Icon(Icons.post_add_outlined),
                  label: const Text('Final Post'),
                ),
              ],
            );
          },
        ),
      );

      if (confirmed == true) {
        final c = BusinessFormat.number(cash.text)?.toDouble() ?? 0;
        final u = BusinessFormat.number(upi.text)?.toDouble() ?? 0;
        if (!DailyOrderMath.finalPostAllowed(
          cash: c,
          online: u,
          expected: expected,
          calculatedExpected: calculatedExpected,
          serverExpected: backendExpected,
        )) {
          throw Exception(
            'Final Post blocked: payment components aur product/server reconciliation verify karein.',
          );
        }
        await api.post(ApiPaths.finalPost(id), data: {'cash': c, 'upi': u});
        if (mounted) {
          _setFeatureState(() {
            refresh++;
            message = 'Daily Order completed and posted.';
          });
        }
      }
    } finally {
      cash.dispose();
      upi.dispose();
    }
  }

}

