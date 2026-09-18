part of 'my_work_screen.dart';

extension _MyWorkDailyOrderImpl on _MyWorkScreenState {
  Future<void> _newDailyOrderImpl() async {
    if (_dailyOrderOpening) return;
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    if (app.currentBranchId == null) {
      if (mounted) {
        _setFeatureState(() => message = 'Authorised Branch select karein.');
      }
      return;
    }
    if (!app.can('daily_order.self') && !app.can('daily_order.others')) {
      if (mounted) {
        _setFeatureState(
          () => message =
              'Daily Order create karne ki permission aapke role mein nahi hai.',
        );
      }
      return;
    }
    if (mounted) {
      _setFeatureState(() {
        _dailyOrderOpening = true;
        message = 'Daily Order form load ho raha hai...';
      });
    }
    try {
      final data = Map<String, dynamic>.from(
        await api.get(ApiPaths.masterData) as Map,
      );
      final products = ((data['products'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (products.isEmpty) throw Exception('Product master empty hai.');

      final employeeMap = Map<String, dynamic>.from(app.me['employee'] as Map);
      var selectedEmployee = int.parse('${employeeMap['id']}');
      var employees = <Map<String, dynamic>>[];
      if (app.can('daily_order.others')) {
        employees = (await api.get(
          ApiPaths.employees,
          query: {'branch_id': app.currentBranchId},
        ) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (employees.any((e) => int.parse('${e['id']}') == selectedEmployee) ==
                false &&
            employees.isNotEmpty) {
          selectedEmployee = int.parse('${employees.first['id']}');
        }
      }

      final qty = <int, TextEditingController>{
        for (final p in products)
          int.parse('${p['id']}'): TextEditingController(),
      };
      String? mode;
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: const Text('Create Daily Order'),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (employees.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        menuMaxHeight: 360,
                        initialValue: selectedEmployee,
                        decoration: const InputDecoration(
                          labelText: 'Employee',
                        ),
                        items: employees
                            .map(
                              (e) => DropdownMenuItem<int>(
                                value: int.parse('${e['id']}'),
                                child: Text(
                                  '${e['full_name'] ?? e['name']} · ${e['employee_code'] ?? ''}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null)
                            setLocalState(() => selectedEmployee = v);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    ...products.map((p) {
                      final id = int.parse('${p['id']}');
                      final price =
                          p['sale_price'] == null ? '' : '₹${p['sale_price']}';
                      final points =
                          p['points'] == null ? '' : '${p['points']} pts';
                      final meta = [price, points]
                          .where((value) => value.isNotEmpty)
                          .join(' · ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${p['name']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700),
                                    ),
                                    if (meta.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        meta,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 92,
                                child: TextField(
                                  controller: qty[id],
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [WholePcs.positiveFormatter],
                                  textAlign: TextAlign.right,
                                  decoration: const InputDecoration(
                                    hintText: '0',
                                    suffixText: 'PCS',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton.tonal(
                onPressed: () {
                  mode = 'draft';
                  Navigator.pop(context);
                },
                child: const Text('Draft'),
              ),
              FilledButton(
                onPressed: () {
                  mode = 'submit';
                  Navigator.pop(context);
                },
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      );

      if (mode == null) {
        for (final c in qty.values) c.dispose();
        if (mounted) {
          _setFeatureState(() => message = null);
        }
        return;
      }
      final lines = <Map<String, dynamic>>[];
      for (final p in products) {
        final id = int.parse('${p['id']}');
        final q = WholePcs.parseOrZero(qty[id]!.text);
        if (q > 0) lines.add({'product_id': id, 'quantity': q});
      }
      for (final c in qty.values) c.dispose();
      if (lines.isEmpty)
        throw Exception('Kam se kam ek product quantity required hai.');

      final created = Map<String, dynamic>.from(
        await api.post(
          ApiPaths.dailyCycles,
          data: {
            'branch_id': app.currentBranchId,
            'employee_id': selectedEmployee,
            'business_date': app.businessDate,
            'lines': lines,
          },
        ) as Map,
      );
      if (mode == 'submit') {
        await api.post(
          ApiPaths.dailySubmit(int.parse('${created['id']}')),
          data: const {},
        );
      }
      if (mounted) {
        _setFeatureState(() {
          refresh++;
          message = mode == 'submit'
              ? 'Daily Order submitted for approval.'
              : 'Daily Order draft saved.';
        });
      }
    } catch (e) {
      if (mounted) _setFeatureState(() => message = UiError.message(e));
    } finally {
      if (mounted && _dailyOrderOpening) {
        _setFeatureState(() => _dailyOrderOpening = false);
      }
    }
  }

  Future<Map<String, dynamic>> _dailyDetailImpl(int id) async {
    return Map<String, dynamic>.from(
      await ref.read(apiClientProvider).get(ApiPaths.dailyDetail(id)) as Map,
    );
  }

  Future<void> _dailyActionImpl(int id, String action) async {
    try {
      final api = ref.read(apiClientProvider);
      final app = ref.read(appStateProvider);
      if (action == 'view') {
        await _MyWorkDaily(this)._showDaily(id);
        return;
      }
      if (action == 'submit') {
        await api.post(ApiPaths.dailySubmit(id), data: const {});
        message = 'Daily Order submitted for approval.';
      } else if (action == 'approve') {
        final d = await _MyWorkDaily(this)._dailyDetail(id);
        final r = _requestWithStatus(d, 'submitted');
        if (r == null) throw Exception('Submitted request not found.');
        await api.post(
          ApiPaths.dailyApprove(int.parse('${r['id']}')),
          data: const {},
        );
        message = 'Daily Order approved. Stock issue pending.';
      } else if (action == 'issue') {
        await _MyWorkDaily(this)._issueDaily(id);
        return;
      } else if (action == 'additional') {
        await _MyWorkDaily(this)._additionalDaily(id);
        return;
      } else if (action == 'evening') {
        final detail = await _MyWorkDaily(this)._dailyDetail(id);
        final cycle = Map<String, dynamic>.from(
          (detail['cycle'] as Map?) ?? const {},
        );
        final requests = ((detail['requests'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        final blockReason = DailyOrderWorkflow.eveningBlockReason(
          cycleStatus: '${cycle['status']}',
          requests: requests,
          capabilities: app.capabilities,
        );
        if (blockReason != null) throw Exception(blockReason);
        await api.post(ApiPaths.eveningStart(id), data: const {});
        await _MyWorkDaily(this)._editEvening(id);
        return;
      } else if (action == 'evening_edit') {
        await _MyWorkDaily(this)._editEvening(id);
        return;
      } else if (action == 'final_post') {
        await _MyWorkDaily(this)._finalPost(id);
        return;
      }
      if (mounted) _setFeatureState(() => refresh++);
    } catch (e) {
      if (mounted) _setFeatureState(() => message = UiError.message(e));
    }
  }

  Future<void> _additionalDailyImpl(int id) async {
    final api = ref.read(apiClientProvider);
    final data = Map<String, dynamic>.from(
      await api.get(ApiPaths.masterData) as Map,
    );
    final products = ((data['products'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (products.isEmpty) throw Exception('Product master empty hai.');

    final qty = <int, TextEditingController>{
      for (final product in products)
        int.parse('${product['id']}'): TextEditingController(),
    };
    final ok = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Additional Requirement',
                          style: Theme.of(sheetContext).textTheme.titleLarge,
                        ),
                        Text(
                          'Order #$id · whole PCS only',
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: const Row(
                children: [
                  Expanded(
                    child: Text(
                      'Product',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  SizedBox(
                    width: 82,
                    child: Text(
                      'Extra Qty',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                itemCount: products.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = products[index];
                  final productId = int.parse('${product['id']}');
                  return SizedBox(
                    height: 54,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            BusinessFormat.displayName('${product['name']}'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 82,
                          child: TextField(
                            controller: qty[productId],
                            keyboardType: TextInputType.number,
                            inputFormatters: [WholePcs.positiveFormatter],
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              hintText: '0',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        child: const Text('Submit Additional'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    try {
      if (ok == true) {
        final lines = <Map<String, dynamic>>[];
        for (final product in products) {
          final productId = int.parse('${product['id']}');
          final value = WholePcs.parseOrZero(qty[productId]!.text);
          if (value > 0) {
            lines.add({'product_id': productId, 'quantity': value});
          }
        }
        if (lines.isEmpty) {
          throw Exception('Kam se kam ek additional product required hai.');
        }
        await api.post(ApiPaths.dailyAdditional(id), data: {'lines': lines});
        if (mounted) {
          _setFeatureState(() {
            refresh++;
            message = 'Additional requirement submitted for approval.';
          });
        }
      }
    } finally {
      for (final controller in qty.values) controller.dispose();
    }
  }

  Future<void> _issueDailyImpl(int id) async {
    final api = ref.read(apiClientProvider);
    final d = await _MyWorkDaily(this)._dailyDetail(id);
    final r = _requestWithStatus(d, 'approved');
    if (r == null) throw Exception('Approved request not found.');
    final lines = ((r['lines'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (lines.isEmpty) throw Exception('Approved request lines missing.');
    final cycle = Map<String, dynamic>.from((d['cycle'] as Map?) ?? const {});
    final branchId = int.tryParse('${cycle['branch_id'] ?? ''}');
    if (branchId == null) throw Exception('Daily Order branch missing.');
    final stock = (await api.get(
      ApiPaths.inventoryStock,
      query: {'branch_id': branchId},
    ) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final allocations = StockAllocation.fefo(requestLines: lines, stock: stock);

    final ok = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .92,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: ExcelBrand.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: ExcelBrand.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Issue Stock',
                          style: Theme.of(sheetContext).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Daily Order #$id · ${lines.length} products',
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(sheetContext, false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                itemCount: lines.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final l = lines[index];
                  final name = BusinessFormat.displayName(
                    '${l['product_name'] ?? 'Product'}',
                  );
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: ExcelBrand.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: ExcelBrand.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: ExcelBrand.primarySoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Requested ${BusinessFormat.quantity(l['quantity'])}',
                                style: const TextStyle(
                                  color: ExcelBrand.primaryDark,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Icons.inventory_outlined,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Full approved quantity will be issued using FEFO batches',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(
                  color: ExcelBrand.surface,
                  border: Border(top: BorderSide(color: ExcelBrand.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Verify & Issue'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      await api.post(
        ApiPaths.dailyIssue(int.parse('${r['id']}')),
        data: {'allocations': allocations},
      );
      if (mounted) {
        _setFeatureState(() {
          refresh++;
          message = 'Stock issued successfully. Evening Closing is pending.';
        });
      }
    }
  }

}
