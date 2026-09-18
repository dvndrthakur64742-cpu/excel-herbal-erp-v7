part of 'organization_screen.dart';

extension _OrganizationProductsFeature on _OrganizationScreenState {
  Widget _productsTab(AppState app, dynamic api) {
    return Column(
      children: [
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
            future: api.get(ApiPaths.products),
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
        'sku': sku.text.trim(),
        'name': name.text.trim(),
        'uom': uom.text.trim(),
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
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Commercial History'),
              onTap: () => _productHistory(id),
            ),
            if (app.can('catalog.product.manage'))
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('New Commercial Revision'),
                onTap: () => _commercialRevision(product),
              ),
          ],
        ),
      ),
    );
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
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Commercial Revision · ${product['name']}'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _moneyPair(mrp, 'MRP', sale, 'Sale Price'),
                  const SizedBox(height: 10),
                  _moneyPair(ho, 'HO Amount', bm, 'BM Profit'),
                  const SizedBox(height: 10),
                  _moneyPair(salary, 'Salary Fund', office, 'Office Expense'),
                  const SizedBox(height: 10),
                  _moneyPair(points, 'Points', purchaseCost, 'Purchase Cost'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: effectiveDate,
                    decoration: const InputDecoration(
                      labelText: 'Effective Date YYYY-MM-DD',
                      helperText: 'Default ERP business date',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reason,
                    minLines: 2,
                    maxLines: 4,
                    decoration:
                        const InputDecoration(labelText: 'Change Reason'),
                  ),
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'Rule: Sale Price ≤ MRP and HO + BM + Salary Fund + Office Expense = Sale Price.'),
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
                reason.text.trim().length >= 5 &&
                    CommercialIntegrity.validBusinessDate(effectiveDate.text),
              ),
              child: const Text('Save Revision'),
            ),
          ],
        ),
      );
      if (ok != true) {
        _disposeControllers(controllers);
        return;
      }
      try {
        if (!CommercialIntegrity.validBusinessDate(effectiveDate.text)) {
          throw Exception(
              'Effective Date valid YYYY-MM-DD format me honi chahiye.');
        }
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
