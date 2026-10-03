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
          ApiPaths.dailyTargetEmployees,
          query: {'branch_id': app.currentBranchId},
        ) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (!employees.any(
              (e) => int.parse('${e['id']}') == selectedEmployee,
            ) &&
            employees.isNotEmpty) {
          selectedEmployee = int.parse('${employees.first['id']}');
        }
      }

      final qty = <int, TextEditingController>{
        for (final p in products)
          int.parse('${p['id']}'): TextEditingController(),
      };
      final search = TextEditingController();
      String? mode;
      String? formError;
      var saving = false;

      List<Map<String, dynamic>> collectLines() {
        final lines = <Map<String, dynamic>>[];
        for (final product in products) {
          final id = int.parse('${product['id']}');
          final value = WholePcs.parseOrZero(qty[id]!.text);
          if (value > 0) {
            lines.add({'product_id': id, 'quantity': value});
          }
        }
        return lines;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: !saving,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            final query = search.text.trim().toLowerCase();
            final visibleProducts = products.where((product) {
              if (query.isEmpty) return true;
              final name = '${product['name'] ?? ''}'.toLowerCase();
              final sku = '${product['sku'] ?? ''}'.toLowerCase();
              return name.contains(query) || sku.contains(query);
            }).toList();
            final selectedLines = collectLines();
            final selectedQty = selectedLines.fold<num>(
              0,
              (sum, line) => sum + (line['quantity'] as num),
            );

            Future<void> persist(String targetMode) async {
              final lines = collectLines();
              if (lines.isEmpty) {
                setLocalState(
                  () => formError =
                      'Kam se kam ek product ki quantity enter karein.',
                );
                return;
              }

              setLocalState(() {
                saving = true;
                formError = null;
              });
              try {
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
                if (targetMode == 'submit') {
                  await api.post(
                    ApiPaths.dailySubmit(int.parse('${created['id']}')),
                    data: const {},
                  );
                }
                mode = targetMode;
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (e) {
                if (dialogContext.mounted) {
                  setLocalState(() {
                    formError = UiError.message(e);
                    saving = false;
                  });
                }
              }
            }

            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              title: Row(
                children: [
                  const Expanded(child: Text('Create Daily Order')),
                  IconButton(
                    tooltip: 'Close',
                    onPressed:
                        saving ? null : () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              content: SizedBox(
                width: 700,
                height: MediaQuery.sizeOf(dialogContext).height * .68,
                child: Column(
                  children: [
                    if (employees.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        menuMaxHeight: 360,
                        initialValue: selectedEmployee,
                        decoration: const InputDecoration(
                          labelText: 'Order For Employee',
                          prefixIcon: Icon(Icons.person_outline_rounded),
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
                        onChanged: saving
                            ? null
                            : (v) {
                                if (v != null) {
                                  setLocalState(() => selectedEmployee = v);
                                }
                              },
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: search,
                      enabled: !saving,
                      onChanged: (_) => setLocalState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Search Product',
                        hintText: 'Name or SKU',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  search.clear();
                                  setLocalState(() {});
                                },
                                icon: const Icon(Icons.clear_rounded),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(dialogContext)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        selectedLines.isEmpty
                            ? 'No product selected'
                            : '${selectedLines.length} products selected · ${BusinessFormat.quantity(selectedQty)} PCS',
                        style: Theme.of(dialogContext)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: visibleProducts.isEmpty
                          ? const Center(
                              child: Text('Matching product nahi mila.'),
                            )
                          : ListView.separated(
                              itemCount: visibleProducts.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final product = visibleProducts[index];
                                final id = int.parse('${product['id']}');
                                final currentQty =
                                    WholePcs.parseOrZero(qty[id]!.text);
                                final price = product['sale_price'] == null
                                    ? ''
                                    : '₹${product['sale_price']}';
                                final points = product['points'] == null
                                    ? ''
                                    : '${product['points']} pts';
                                final meta = [
                                  if ('${product['sku'] ?? ''}'.trim().isNotEmpty)
                                    'SKU ${product['sku']}',
                                  price,
                                  points,
                                ].where((value) => value.isNotEmpty).join(' · ');
                                return Container(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 9, 10, 9),
                                  decoration: BoxDecoration(
                                    color: currentQty > 0
                                        ? ExcelBrand.primarySoft
                                        : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: currentQty > 0
                                          ? ExcelBrand.primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .outlineVariant,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${product['name']}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
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
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        width: 108,
                                        child: TextField(
                                          controller: qty[id],
                                          enabled: !saving,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            WholePcs.positiveFormatter,
                                          ],
                                          textAlign: TextAlign.right,
                                          onChanged: (_) =>
                                              setLocalState(() {}),
                                          decoration: const InputDecoration(
                                            hintText: '0',
                                            suffixText: 'PCS',
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formError!,
                          style: TextStyle(
                            color:
                                Theme.of(dialogContext).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton.tonalIcon(
                  onPressed: saving ? null : () => persist('draft'),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Draft'),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : () => persist('submit'),
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    saving ? 'Saving...' : 'Submit for Approval',
                  ),
                ),
              ],
            );
          },
        ),
      );

      for (final controller in qty.values) {
        controller.dispose();
      }
      search.dispose();

      if (mode == null) {
        if (mounted) _setFeatureState(() => message = null);
        return;
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

    final allocations = <Map<String, dynamic>>[
      for (final line in lines)
        {
          'request_line_id': int.parse('${line['id']}'),
          'quantity': num.parse('${line['quantity']}'),
        },
    ];

    String? issueError;
    var issuing = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => FractionallySizedBox(
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
                      onPressed: issuing
                          ? null
                          : () => Navigator.pop(sheetContext, false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext)
                        .colorScheme
                        .surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Approved quantity branch stock se automatic FEFO allocation ke saath employee custody me issue hogi.',
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
                      child: Row(
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
                              'Issue ${BusinessFormat.quantity(l['quantity'])}',
                              style: const TextStyle(
                                color: ExcelBrand.primaryDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (issueError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      issueError!,
                      style: TextStyle(
                        color: Theme.of(sheetContext).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                          onPressed: issuing
                              ? null
                              : () => Navigator.pop(sheetContext, false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: issuing
                              ? null
                              : () async {
                                  setSheetState(() {
                                    issuing = true;
                                    issueError = null;
                                  });
                                  try {
                                    await api.post(
                                      ApiPaths.dailyIssue(
                                        int.parse('${r['id']}'),
                                      ),
                                      data: {'allocations': allocations},
                                    );
                                    if (sheetContext.mounted) {
                                      Navigator.pop(sheetContext, true);
                                    }
                                  } catch (e) {
                                    if (sheetContext.mounted) {
                                      setSheetState(() {
                                        issueError = UiError.message(e);
                                        issuing = false;
                                      });
                                    }
                                  }
                                },
                          icon: issuing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.inventory_2_outlined),
                          label: Text(
                            issuing ? 'Issuing...' : 'Issue Stock',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok == true && mounted) {
      _setFeatureState(() {
        refresh++;
        message = 'Stock issued successfully. Evening Closing is pending.';
      });
    }
  }

}
