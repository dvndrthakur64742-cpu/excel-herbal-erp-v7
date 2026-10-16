part of 'organization_screen.dart';

extension _OrganizationProductsFeature on _OrganizationScreenState {
  Widget _productsTab(AppState app, dynamic api) {
    return Column(
      children: [
        if (!app.can('catalog.product.manage'))
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'View only · Product edit permission required for changes.',
              ),
            ),
          ),
        if (app.can('catalog.product.manage'))
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _createProduct,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('New Product'),
              ),
            ),
          ),
        Expanded(
          child: AsyncPanel(
            key: ValueKey('products-$refresh'),
            future: api.get(
              ApiPaths.products,
              query: app.can('catalog.product.manage')
                  ? const {'include_inactive': true}
                  : null,
            ),
            emptyMessage: 'Product master empty hai.',
            builder: (context, data) => RecordsList(
              recordType: 'product',
              rows: (data as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
              onTap: _productActions,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createProduct() async {
    final sku = TextEditingController();
    final name = TextEditingController();
    final uom = TextEditingController(text: 'PCS');
    final mrp = TextEditingController(text: '0');
    final sale = TextEditingController(text: '0');
    final ho = TextEditingController(text: '0');
    final bm = TextEditingController(text: '0');
    final salary = TextEditingController(text: '0');
    final office = TextEditingController(text: '0');
    final points = TextEditingController(text: '0');
    final purchaseCost = TextEditingController(text: '0');
    final controllers = [
      sku,
      name,
      uom,
      mrp,
      sale,
      ho,
      bm,
      salary,
      office,
      points,
      purchaseCost,
    ];
    var batchMode = 'optional';
    var expiryTracking = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New Product'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: sku,
                    decoration: const InputDecoration(labelText: 'SKU'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration:
                        const InputDecoration(labelText: 'Product Name'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: uom,
                    decoration: const InputDecoration(labelText: 'UOM'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: batchMode,
                    decoration:
                        const InputDecoration(labelText: 'Batch Tracking'),
                    items: const [
                      DropdownMenuItem(value: 'off', child: Text('Off')),
                      DropdownMenuItem(
                          value: 'optional', child: Text('Optional')),
                      DropdownMenuItem(
                          value: 'required', child: Text('Required')),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => batchMode = v);
                    },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: expiryTracking,
                    title: const Text('Expiry Tracking'),
                    onChanged: (v) =>
                        setLocal(() => expiryTracking = v == true),
                  ),
                  _moneyPair(mrp, 'MRP', sale, 'Sale Price'),
                  const SizedBox(height: 10),
                  _moneyPair(ho, 'HO Amount', bm, 'BM Profit'),
                  const SizedBox(height: 10),
                  _moneyPair(salary, 'Salary Fund', office, 'Office Expense'),
                  const SizedBox(height: 10),
                  _moneyPair(
                      points, 'Points', purchaseCost, 'Initial Purchase Cost'),
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'Rule: Sale Price ≤ MRP and distribution total must equal Sale Price.'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                sku.text.trim().isNotEmpty && name.text.trim().isNotEmpty,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) {
      _disposeControllers(controllers);
      return;
    }
    try {
      final skuValue = sku.text.trim();
      final nameValue = name.text.trim();
      final uomValue = uom.text.trim();
      final validation = TransactionGuardrails.productCreate(
        sku: skuValue,
        name: nameValue,
        uom: uomValue,
        batchMode: batchMode,
        expiryTracking: expiryTracking,
      );
      if (validation != null) throw Exception(validation);
      final commercial = _commercialValues(
        mrp: mrp,
        sale: sale,
        ho: ho,
        bm: bm,
        salary: salary,
        office: office,
        points: points,
        purchaseCost: purchaseCost,
      );
      final payload = {
        'sku': skuValue,
        'name': nameValue,
        'uom': uomValue,
        'batch_tracking': batchMode,
        'expiry_tracking': expiryTracking,
        ...commercial.toPayload(),
      };
      await ref.read(apiClientProvider).post(ApiPaths.products, data: payload);
      if (mounted) {
        _setOrganizationState(() {
          refresh++;
          message = 'Product create ho gaya.';
        });
      }
    } catch (e) {
      if (mounted) _setOrganizationState(() => message = UiError.message(e));
    } finally {
      _disposeControllers(controllers);
    }
  }

  void _productActions(Map<String, dynamic> product) {
    final app = ref.read(appStateProvider);
    final id = int.parse('${product['id']}');
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text('${product['name']} · ${product['sku']}'),
              subtitle: Text(
                'Sale ₹${product['sale_price'] ?? 0} · Batch ${product['batch_tracking']}',
              ),
            ),
            if (app.can('catalog.product.manage'))
              ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: const Text('Edit Product Details'),
                subtitle: const Text('Product name and SKU'),
                onTap: () => _editProduct(product),
              ),
            if (app.can('catalog.product.manage'))
              ListTile(
                leading: const Icon(Icons.currency_rupee_outlined),
                title: const Text('Edit MRP / Sale Price / Distribution'),
                subtitle: const Text(
                  'Creates an audited commercial revision and preserves price history',
                ),
                onTap: () => _commercialRevision(product),
              ),
            if (app.can('catalog.product.manage'))
              ListTile(
                leading: Icon(
                  '${product['status'] ?? 'active'}' == 'active'
                      ? Icons.block_outlined
                      : Icons.check_circle_outline,
                ),
                title: Text(
                  '${product['status'] ?? 'active'}' == 'active'
                      ? 'Deactivate Product'
                      : 'Activate Product',
                ),
                subtitle: Text(
                  '${product['status'] ?? 'active'}' == 'active'
                      ? 'Blocked automatically if stock or open business references exist'
                      : 'Re-enable this product for normal ERP use',
                ),
                onTap: () => _setProductActive(
                  product,
                  '${product['status'] ?? 'active'}' != 'active',
                ),
              ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Commercial History'),
              onTap: () => _productHistory(id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editProduct(Map<String, dynamic> product) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    final id = int.tryParse('${product['id']}') ?? 0;
    if (id < 1) return;

    final name = TextEditingController(text: '${product['name'] ?? ''}');
    final sku = TextEditingController(text: '${product['sku'] ?? ''}');
    String? formError;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text('Edit Product · ${product['sku'] ?? ''}'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Product Name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: sku,
                  decoration: const InputDecoration(labelText: 'SKU'),
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'MRP, Sale Price, HO amount, BM profit, salary fund and office expense are changed from “Edit MRP / Sale Price / Distribution” so every commercial change keeps history.',
                  ),
                ),
                if (formError != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formError!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty || sku.text.trim().isEmpty) {
                  setLocal(
                    () => formError = 'Product name aur SKU required hain.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) {
      name.dispose();
      sku.dispose();
      return;
    }

    try {
      await ref.read(apiClientProvider).post(
        ApiPaths.productUpdate(id),
        data: {
          'name': name.text.trim(),
          'sku': sku.text.trim(),
        },
      );
      if (mounted) {
        _setOrganizationState(() {
          refresh++;
          message = 'Product details update ho gaye.';
        });
      }
    } catch (e) {
      if (mounted) {
        _setOrganizationState(() => message = UiError.message(e));
      }
    } finally {
      name.dispose();
      sku.dispose();
    }
  }

  Future<void> _setProductActive(
    Map<String, dynamic> product,
    bool active,
  ) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    final id = int.tryParse('${product['id']}') ?? 0;
    if (id < 1) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(active ? 'Activate Product?' : 'Deactivate Product?'),
        content: Text(
          active
              ? '${product['name'] ?? 'Product'} ERP me dobara active ho jayega.'
              : '${product['name'] ?? 'Product'} ko deactivate karna hai? Open stock / transfer / daily-order references hue to ERP is action ko automatically block karega.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(active ? 'Activate' : 'Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(apiClientProvider).post(
        ApiPaths.productStatus(id),
        data: {'active': active},
      );
      if (mounted) {
        _setOrganizationState(() {
          refresh++;
          message = active
              ? 'Product activate ho gaya.'
              : 'Product deactivate ho gaya.';
        });
      }
    } catch (e) {
      if (mounted) {
        _setOrganizationState(() => message = UiError.message(e));
      }
    }
  }

  Future<void> _productHistory(int id) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    try {
      final rows = (await ref
              .read(apiClientProvider)
              .get(ApiPaths.productHistory(id)) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Commercial History'),
          content: SizedBox(
            width: 680,
            height: 420,
            child: RecordsList(recordType: 'product_history', rows: rows),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _setOrganizationState(() => message = UiError.message(e));
    }
  }

  Future<void> _commercialRevision(Map<String, dynamic> product) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    final app = ref.read(appStateProvider);
    try {
      final history = (await ref
                  .read(apiClientProvider)
                  .get(ApiPaths.productHistory(int.parse('${product['id']}')))
              as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      final latest = history.isNotEmpty ? history.first : product;
      final mrp = TextEditingController(
          text: '${latest['mrp'] ?? product['mrp'] ?? 0}');
      final sale = TextEditingController(
          text: '${latest['sale_price'] ?? product['sale_price'] ?? 0}');
      final ho = TextEditingController(
          text: '${latest['ho_amount'] ?? product['ho_amount'] ?? 0}');
      final bm = TextEditingController(
          text: '${latest['bm_profit'] ?? product['bm_profit'] ?? 0}');
      final salary = TextEditingController(
          text: '${latest['salary_fund'] ?? product['salary_fund'] ?? 0}');
      final office = TextEditingController(
          text:
              '${latest['office_expense'] ?? product['office_expense'] ?? 0}');
      final points = TextEditingController(
          text: '${latest['points'] ?? product['points'] ?? 0}');
      final purchaseCost = TextEditingController(
          text: '${latest['purchase_cost'] ?? product['purchase_cost'] ?? 0}');
      final effectiveDate = TextEditingController(text: app.businessDate);
      final reason = TextEditingController();
      final controllers = [
        mrp,
        sale,
        ho,
        bm,
        salary,
        office,
        points,
        purchaseCost,
        effectiveDate,
        reason,
      ];
      String? validation;

      final ok = await showModalBottomSheet<bool>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setLocal) => FractionallySizedBox(
            heightFactor: .96,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: ExcelBrand.primarySoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.price_change_outlined,
                          color: ExcelBrand.primaryDark,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Commercial Revision',
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              '${product['name'] ?? 'Product'} · ${product['sku'] ?? ''}',
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
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                    children: [
                      Text(
                        'Selling Price',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      _moneyPair(mrp, 'MRP', sale, 'Sale Price'),
                      const SizedBox(height: 20),
                      Text(
                        'Distribution',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      _moneyPair(ho, 'HO Amount', bm, 'BM Profit'),
                      const SizedBox(height: 10),
                      _moneyPair(salary, 'Salary Fund', office, 'Office Expense'),
                      const SizedBox(height: 10),
                      _moneyPair(points, 'Points', purchaseCost, 'Purchase Cost'),
                      const SizedBox(height: 20),
                      Text(
                        'Effective Date & Audit Reason',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      BusinessDateField(
                        controller: effectiveDate,
                        label: 'Commercial Effective Date',
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: reason,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Change Reason',
                          helperText: 'Minimum 5 characters',
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Theme.of(sheetContext)
                              .colorScheme
                              .surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'Control rule: Sale Price ≤ MRP and HO + BM Profit + Salary Fund + Office Expense = Sale Price. Every saved revision keeps commercial history.',
                        ),
                      ),
                      if (validation != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          validation!,
                          style: TextStyle(
                            color: Theme.of(sheetContext).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: const BoxDecoration(
                      color: ExcelBrand.surface,
                      border: Border(
                        top: BorderSide(color: ExcelBrand.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.pop(sheetContext, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () {
                              final auditReason = reason.text.trim();
                              if (auditReason.length < 5) {
                                setLocal(
                                  () => validation =
                                      'Change reason kam se kam 5 characters ka hona chahiye.',
                                );
                                return;
                              }
                              if (!CommercialIntegrity.validBusinessDate(
                                  effectiveDate.text)) {
                                setLocal(
                                  () => validation =
                                      'Effective Date valid YYYY-MM-DD format me honi chahiye.',
                                );
                                return;
                              }
                              try {
                                _commercialValues(
                                  mrp: mrp,
                                  sale: sale,
                                  ho: ho,
                                  bm: bm,
                                  salary: salary,
                                  office: office,
                                  points: points,
                                  purchaseCost: purchaseCost,
                                );
                              } catch (e) {
                                setLocal(
                                  () => validation = UiError.message(e),
                                );
                                return;
                              }
                              Navigator.pop(sheetContext, true);
                            },
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save Revision'),
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

      if (ok != true) {
        _disposeControllers(controllers);
        return;
      }
      try {
        final commercial = _commercialValues(
          mrp: mrp,
          sale: sale,
          ho: ho,
          bm: bm,
          salary: salary,
          office: office,
          points: points,
          purchaseCost: purchaseCost,
        );
        await ref.read(apiClientProvider).post(
          ApiPaths.productRevision(int.parse('${product['id']}')),
          data: {
            ...commercial.toPayload(),
            if (effectiveDate.text.trim() != app.businessDate)
              'effective_from': '${effectiveDate.text.trim()} 00:00:00',
            'reason': reason.text.trim(),
          },
        );
        if (mounted) {
          _setOrganizationState(() {
            refresh++;
            message = 'Commercial revision saved.';
          });
        }
      } finally {
        _disposeControllers(controllers);
      }
    } catch (e) {
      if (mounted) _setOrganizationState(() => message = UiError.message(e));
    }
  }
}
