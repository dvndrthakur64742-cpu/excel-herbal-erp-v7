import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/entity_relations.dart';
import '../../core/providers.dart';
import '../../state/app_state.dart';

class EntityWorkspaceScreen extends ConsumerStatefulWidget {
  const EntityWorkspaceScreen({
    super.key,
    required this.row,
    required this.title,
    required this.recordType,
  });

  final Map<String, dynamic> row;
  final String title;
  final String recordType;

  static const supportedTypes = <String>{
    'customer',
    'supplier',
    'purchase',
    'product',
    'stock',
    'employee',
    'daily_order',
    'stock_transfer',
  };

  static bool supports(String? recordType) =>
      recordType != null && supportedTypes.contains(recordType);

  @override
  ConsumerState<EntityWorkspaceScreen> createState() =>
      _EntityWorkspaceScreenState();
}

class _EntityWorkspaceScreenState extends ConsumerState<EntityWorkspaceScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _refresh() => setState(() => _future = _load());

  Future<Map<String, dynamic>> _load() async {
    final app = ref.read(appStateProvider);
    return switch (widget.recordType) {
      'customer' => _loadCustomer(app),
      'supplier' => _loadSupplier(app),
      'purchase' => _loadPurchase(app),
      'product' || 'stock' => _loadProduct(app),
      'employee' => _loadEmployee(app),
      'daily_order' => _loadDailyOrder(),
      'stock_transfer' => _loadTransfer(),
      _ => Future.value(const <String, dynamic>{}),
    };
  }

  int? _branchId(AppState app) =>
      EntityRelations.normalizeId(widget.row['branch_id']) ??
      EntityRelations.normalizeId(widget.row['source_branch_id']) ??
      app.currentBranchId;

  Future<Map<String, dynamic>> _loadCustomer(AppState app) async {
    final id = EntityRelations.normalizeId(widget.row['id']);
    final branchId = _branchId(app);
    if (id == null || branchId == null) return const {};

    final openSales =
        app.canAny(const ['sales.view', 'sales.create', 'sales.receipt.create'])
        ? await _safeList(ApiPaths.openSales, {'branch_id': branchId})
        : <Map<String, dynamic>>[];
    final monthSales = app.can('reports.view')
        ? await _safeList(ApiPaths.reportsSales, {
            'branch_id': branchId,
            'from': app.businessMonthStart,
            'to': app.businessDate,
          })
        : <Map<String, dynamic>>[];
    final receivables = app.can('reports.view')
        ? await _safeList(ApiPaths.receivables, {
            'branch_id': branchId,
            'to': app.businessDate,
          })
        : <Map<String, dynamic>>[];

    return {
      'open_sales': EntityRelations.byForeignKey(openSales, 'customer_id', id),
      'month_sales': EntityRelations.byForeignKey(
        monthSales,
        'customer_id',
        id,
      ),
      'receivables': EntityRelations.byForeignKey(
        receivables,
        'customer_id',
        id,
      ),
    };
  }

  Future<Map<String, dynamic>> _loadSupplier(AppState app) async {
    final id = EntityRelations.normalizeId(widget.row['id']);
    final branchId = _branchId(app);
    if (id == null || branchId == null) return const {};

    final openBills = app.canAny(const ['purchase.view', 'purchase.create'])
        ? await _safeList(ApiPaths.openBills, {'branch_id': branchId})
        : <Map<String, dynamic>>[];
    final monthPurchases = app.can('reports.view')
        ? await _safeList(ApiPaths.reportsPurchase, {
            'branch_id': branchId,
            'from': app.businessMonthStart,
            'to': app.businessDate,
          })
        : <Map<String, dynamic>>[];
    final payables = app.can('reports.view')
        ? await _safeList(ApiPaths.payables, {
            'branch_id': branchId,
            'to': app.businessDate,
          })
        : <Map<String, dynamic>>[];

    return {
      'open_bills': EntityRelations.byForeignKey(openBills, 'supplier_id', id),
      'month_purchases': EntityRelations.byForeignKey(
        monthPurchases,
        'supplier_id',
        id,
      ),
      'payables': EntityRelations.byForeignKey(payables, 'supplier_id', id),
    };
  }

  Future<Map<String, dynamic>> _loadPurchase(AppState app) async {
    final supplierId = EntityRelations.normalizeId(widget.row['supplier_id']);
    final branchId = _branchId(app);
    final suppliers = app.canAny(const ['purchase.view', 'purchase.create'])
        ? await _safeList(ApiPaths.suppliers)
        : <Map<String, dynamic>>[];
    final monthPurchases = branchId != null && app.can('reports.view')
        ? await _safeList(ApiPaths.reportsPurchase, {
            'branch_id': branchId,
            'from': app.businessMonthStart,
            'to': app.businessDate,
          })
        : <Map<String, dynamic>>[];
    return {
      if (supplierId != null)
        'supplier': EntityRelations.firstById(suppliers, supplierId),
      'month_match': _findRecordMatch(monthPurchases, widget.row),
    };
  }

  Future<Map<String, dynamic>> _loadProduct(AppState app) async {
    final productId = EntityRelations.normalizeId(
      widget.recordType == 'product'
          ? widget.row['id']
          : widget.row['product_id'],
    );
    final branchId = _branchId(app);
    if (productId == null) return const {};

    var product = widget.recordType == 'product'
        ? widget.row
        : <String, dynamic>{};
    if (product.isEmpty &&
        app.canAny(const ['catalog.product.view', 'catalog.product.manage'])) {
      final products = await _safeList(ApiPaths.products);
      product = EntityRelations.firstById(products, productId) ?? const {};
    }

    final stock = branchId != null && app.can('inventory.view')
        ? await _safeList(ApiPaths.inventoryStock, {'branch_id': branchId})
        : <Map<String, dynamic>>[];
    final history =
        app.canAny(const ['catalog.product.view', 'catalog.product.manage'])
        ? await _safeList(ApiPaths.productHistory(productId))
        : <Map<String, dynamic>>[];

    return {
      'product': product,
      'stock': EntityRelations.byForeignKey(stock, 'product_id', productId),
      'history': history,
    };
  }

  Future<Map<String, dynamic>> _loadEmployee(AppState app) async {
    final employeeId = EntityRelations.normalizeId(widget.row['id']);
    final branchId = _branchId(app);
    if (employeeId == null) return const {};

    final history =
        app.canAny(const [
          'organization.employee.view',
          'organization.employee.manage',
        ])
        ? await _safeList(ApiPaths.employeeHistory(employeeId))
        : <Map<String, dynamic>>[];
    final documents =
        app.canAny(const [
          'organization.employee.view',
          'organization.employee.manage',
        ])
        ? await _safeList(ApiPaths.employeeDocuments(employeeId))
        : <Map<String, dynamic>>[];
    final attendance =
        branchId != null && app.can('workforce.attendance.manage')
        ? await _safeList(ApiPaths.attendanceReport, {
            'branch_id': branchId,
            'from': app.businessMonthStart,
            'to': app.businessDate,
          })
        : <Map<String, dynamic>>[];
    final daily =
        branchId != null &&
            app.canAny(const [
              'daily_order.others',
              'daily_order.approve',
              'daily_order.issue',
              'daily_order.review',
            ])
        ? await _safeList(ApiPaths.dailyCycles, {
            'branch_id': branchId,
            'from': app.businessMonthStart,
            'to': app.businessDate,
          })
        : <Map<String, dynamic>>[];

    return {
      'history': history,
      'documents': documents,
      'attendance': EntityRelations.byForeignKey(
        attendance,
        'employee_id',
        employeeId,
      ),
      'daily': EntityRelations.byForeignKey(daily, 'employee_id', employeeId),
    };
  }

  Future<Map<String, dynamic>> _loadDailyOrder() async {
    final id = EntityRelations.normalizeId(widget.row['id']);
    if (id == null) return const {};
    final detail = await ref
        .read(apiClientProvider)
        .get(ApiPaths.dailyDetail(id));
    return {'detail': Map<String, dynamic>.from(detail as Map)};
  }

  Future<Map<String, dynamic>> _loadTransfer() async {
    final id = EntityRelations.normalizeId(widget.row['id']);
    if (id == null) return const {};
    final detail = await ref
        .read(apiClientProvider)
        .get(ApiPaths.transferDetail(id));
    return {'detail': Map<String, dynamic>.from(detail as Map)};
  }

  Future<List<Map<String, dynamic>>> _safeList(
    String path, [
    Map<String, dynamic>? query,
  ]) async {
    try {
      final data = await ref.read(apiClientProvider).get(path, query: query);
      return ((data as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Map<String, dynamic>? _findRecordMatch(
    List<Map<String, dynamic>> rows,
    Map<String, dynamic> target,
  ) {
    final id = EntityRelations.normalizeId(target['id']);
    if (id != null) {
      final byId = EntityRelations.firstById(rows, id);
      if (byId != null) return byId;
    }
    for (final key in const ['bill_no', 'sale_no', 'reference', 'entry_no']) {
      final value = '${target[key] ?? ''}'.trim();
      if (value.isEmpty) continue;
      for (final row in rows) {
        if ('${row[key] ?? ''}'.trim() == value) return row;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle()),
        actions: [
          IconButton(
            tooltip: 'Refresh workspace',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _WorkspaceError(
              message: '${snapshot.error}',
              onRetry: _refresh,
            );
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          return RefreshIndicator(
            onRefresh: () async {
              _refresh();
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width >= 900 ? 24 : 16,
              ),
              children: [
                _hero(context, app),
                const SizedBox(height: 16),
                ..._workspaceSections(context, app, data),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  String _pageTitle() => switch (widget.recordType) {
    'customer' => 'Customer Workspace',
    'supplier' => 'Supplier Workspace',
    'purchase' => 'Purchase Bill Workspace',
    'product' || 'stock' => 'Product & Stock Workspace',
    'employee' => 'Employee Workspace',
    'daily_order' => 'Daily Order Workspace',
    'stock_transfer' => 'Transfer Workspace',
    _ => 'Record Workspace',
  };

  IconData _icon() => switch (widget.recordType) {
    'customer' => Icons.person_outline_rounded,
    'supplier' => Icons.local_shipping_outlined,
    'purchase' => Icons.receipt_long_outlined,
    'product' || 'stock' => Icons.inventory_2_outlined,
    'employee' => Icons.badge_outlined,
    'daily_order' => Icons.shopping_cart_checkout_rounded,
    'stock_transfer' => Icons.swap_horiz_rounded,
    _ => Icons.description_outlined,
  };

  Widget _hero(BuildContext context, AppState app) {
    final status = widget.row['status'];
    final branch = _branchLabel(app, _branchId(app));
    final subtitle = <String>[
      BusinessFormat.displayName(widget.recordType.replaceAll('_', ' ')),
      if (branch.isNotEmpty) branch,
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                _icon(),
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (status != null)
              _StatusChip(label: BusinessFormat.status(status)),
          ],
        ),
      ),
    );
  }

  List<Widget> _workspaceSections(
    BuildContext context,
    AppState app,
    Map<String, dynamic> data,
  ) {
    return switch (widget.recordType) {
      'customer' => _customerSections(context, data),
      'supplier' => _supplierSections(context, data),
      'purchase' => _purchaseSections(context, data),
      'product' || 'stock' => _productSections(context, data),
      'employee' => _employeeSections(context, data),
      'daily_order' => _dailySections(context, data),
      'stock_transfer' => _transferSections(context, app, data),
      _ => [_overviewSection(context, widget.row)],
    };
  }

  List<Widget> _customerSections(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final open = _maps(data['open_sales']);
    final month = _maps(data['month_sales']);
    final receivables = _maps(data['receivables']);
    return [
      _metrics(context, [
        _Metric(
          'Outstanding',
          BusinessFormat.money(EntityRelations.sum(open, 'outstanding_amount')),
          Icons.account_balance_wallet_outlined,
        ),
        _Metric('Open Sales', '${open.length}', Icons.receipt_long_outlined),
        _Metric(
          'Month Sales',
          BusinessFormat.money(EntityRelations.sum(month, 'gross_amount')),
          Icons.trending_up_rounded,
        ),
      ]),
      const SizedBox(height: 16),
      _overviewSection(context, widget.row, title: 'Customer Profile'),
      const SizedBox(height: 16),
      _section(
        context,
        'Outstanding Sales',
        'Current branch ke posted outstanding sales.',
        _relatedList(
          context,
          open,
          recordType: null,
          empty: 'No outstanding sale.',
        ),
      ),
      if (receivables.isNotEmpty) ...[
        const SizedBox(height: 16),
        _section(
          context,
          'Receivable Position',
          'Accounting receivable report se matched customer rows.',
          _relatedList(context, receivables, empty: 'No receivable row.'),
        ),
      ],
      if (month.isNotEmpty) ...[
        const SizedBox(height: 16),
        _section(
          context,
          'This Month Sales',
          'Business month ke matched sales records.',
          _relatedList(context, month, empty: 'No sales in current month.'),
        ),
      ],
    ];
  }

  List<Widget> _supplierSections(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final bills = _maps(data['open_bills']);
    final month = _maps(data['month_purchases']);
    final payables = _maps(data['payables']);
    return [
      _metrics(context, [
        _Metric(
          'Outstanding',
          BusinessFormat.money(
            EntityRelations.sum(bills, 'outstanding_amount'),
          ),
          Icons.account_balance_wallet_outlined,
        ),
        _Metric('Open Bills', '${bills.length}', Icons.receipt_long_outlined),
        _Metric(
          'Month Purchase',
          BusinessFormat.money(EntityRelations.sum(month, 'total_amount')),
          Icons.local_shipping_outlined,
        ),
      ]),
      const SizedBox(height: 16),
      _overviewSection(context, widget.row, title: 'Supplier Profile'),
      const SizedBox(height: 16),
      _section(
        context,
        'Outstanding Bills',
        'Current branch ke unpaid / partially paid supplier bills.',
        _relatedList(
          context,
          bills,
          recordType: 'purchase',
          empty: 'No outstanding supplier bill.',
        ),
      ),
      if (payables.isNotEmpty) ...[
        const SizedBox(height: 16),
        _section(
          context,
          'Payable Position',
          'Accounting payable report se matched supplier rows.',
          _relatedList(context, payables, empty: 'No payable row.'),
        ),
      ],
      if (month.isNotEmpty) ...[
        const SizedBox(height: 16),
        _section(
          context,
          'This Month Purchases',
          'Business month ke supplier purchase records.',
          _relatedList(
            context,
            month,
            recordType: 'purchase',
            empty: 'No purchase this month.',
          ),
        ),
      ],
    ];
  }

  List<Widget> _purchaseSections(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final supplier = data['supplier'] is Map
        ? Map<String, dynamic>.from(data['supplier'] as Map)
        : <String, dynamic>{};
    final match = data['month_match'] is Map
        ? Map<String, dynamic>.from(data['month_match'] as Map)
        : <String, dynamic>{};
    return [
      _metrics(context, [
        _Metric(
          'Bill Total',
          BusinessFormat.money(widget.row['total_amount']),
          Icons.receipt_long_outlined,
        ),
        _Metric(
          'Paid',
          BusinessFormat.money(widget.row['paid_amount']),
          Icons.payments_outlined,
        ),
        _Metric(
          'Outstanding',
          BusinessFormat.money(widget.row['outstanding_amount']),
          Icons.account_balance_wallet_outlined,
        ),
      ]),
      const SizedBox(height: 16),
      _overviewSection(context, widget.row, title: 'Bill Summary'),
      if (supplier.isNotEmpty) ...[
        const SizedBox(height: 16),
        _section(
          context,
          'Supplier',
          'Is bill se linked supplier master.',
          _linkedEntityCard(context, supplier, 'supplier'),
        ),
      ],
      if (match.isNotEmpty) ...[
        const SizedBox(height: 16),
        _section(
          context,
          'Accounting Report Match',
          'Current month purchase report me matched bill record.',
          _overviewCard(context, match),
        ),
      ],
    ];
  }

  List<Widget> _productSections(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final product = data['product'] is Map
        ? Map<String, dynamic>.from(data['product'] as Map)
        : widget.row;
    final stock = _maps(data['stock']);
    final history = _maps(data['history']);
    final quantity = EntityRelations.sum(stock, 'quantity');
    return [
      _metrics(context, [
        _Metric(
          'Available Stock',
          BusinessFormat.quantity(quantity),
          Icons.inventory_2_outlined,
        ),
        _Metric(
          'Sale Price',
          BusinessFormat.money(product['sale_price']),
          Icons.sell_outlined,
        ),
        _Metric(
          'Points',
          BusinessFormat.quantity(product['points']),
          Icons.stars_outlined,
        ),
      ]),
      const SizedBox(height: 16),
      _overviewSection(context, product, title: 'Product Master'),
      const SizedBox(height: 16),
      _section(
        context,
        'Current Stock & Batches',
        'Selected branch ke stock rows; batch/custodian detail backend ke according.',
        _relatedList(
          context,
          stock,
          empty: 'Current branch me stock nahi hai.',
        ),
      ),
      const SizedBox(height: 16),
      _section(
        context,
        'Commercial History',
        'Effective commercial revisions; current values ko overwrite karke history hide nahi hoti.',
        _relatedList(
          context,
          history,
          empty: 'Commercial history unavailable.',
        ),
      ),
    ];
  }

  List<Widget> _employeeSections(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final attendance = _maps(data['attendance']);
    final daily = _maps(data['daily']);
    final history = _maps(data['history']);
    final docs = _maps(data['documents']);
    return [
      _metrics(context, [
        _Metric(
          'Attendance Days',
          '${attendance.length}',
          Icons.how_to_reg_outlined,
        ),
        _Metric(
          'Daily Orders',
          '${daily.length}',
          Icons.shopping_cart_checkout_outlined,
        ),
        _Metric('Documents', '${docs.length}', Icons.folder_copy_outlined),
      ]),
      const SizedBox(height: 16),
      _overviewSection(context, widget.row, title: 'Employee Profile'),
      if (daily.isNotEmpty) ...[
        const SizedBox(height: 16),
        _section(
          context,
          'Daily Orders',
          'Current business month ke employee cycles.',
          _relatedList(
            context,
            daily,
            recordType: 'daily_order',
            empty: 'No Daily Order.',
          ),
        ),
      ],
      if (attendance.isNotEmpty) ...[
        const SizedBox(height: 16),
        _section(
          context,
          'Attendance',
          'Current business month attendance history.',
          _relatedList(context, attendance, empty: 'No attendance rows.'),
        ),
      ],
      const SizedBox(height: 16),
      _section(
        context,
        'Branch History',
        'Effective branch assignment timeline.',
        _relatedList(context, history, empty: 'No branch history.'),
      ),
      const SizedBox(height: 16),
      _section(
        context,
        'Documents',
        'Employee document registry metadata.',
        _relatedList(context, docs, empty: 'No employee documents.'),
      ),
    ];
  }

  List<Widget> _dailySections(BuildContext context, Map<String, dynamic> data) {
    final detail = data['detail'] is Map
        ? Map<String, dynamic>.from(data['detail'] as Map)
        : <String, dynamic>{};
    final cycle = detail['cycle'] is Map
        ? Map<String, dynamic>.from(detail['cycle'] as Map)
        : widget.row;
    final requests = _maps(detail['requests']);
    final evening = detail['evening'] is Map
        ? Map<String, dynamic>.from(detail['evening'] as Map)
        : <String, dynamic>{};
    final requestLines = <Map<String, dynamic>>[];
    final issuedLines = <Map<String, dynamic>>[];
    for (final request in requests) {
      requestLines.addAll(_maps(request['lines']));
      issuedLines.addAll(_maps(request['issued_lines']));
    }
    final eveningLines = _maps(evening['lines']);
    return [
      _metrics(context, [
        _Metric('Requests', '${requests.length}', Icons.approval_outlined),
        _Metric(
          'Issued Qty',
          BusinessFormat.quantity(EntityRelations.sum(issuedLines, 'quantity')),
          Icons.inventory_2_outlined,
        ),
        _Metric(
          'Expected Deposit',
          BusinessFormat.money(evening['expected_amount']),
          Icons.account_balance_wallet_outlined,
        ),
      ]),
      const SizedBox(height: 16),
      _overviewSection(context, cycle, title: 'Cycle Summary'),
      const SizedBox(height: 16),
      _section(
        context,
        'Request Workflow',
        'Initial/additional requests with approval and issue state.',
        _requestWorkflow(context, requests),
      ),
      if (requestLines.isNotEmpty) ...[
        const SizedBox(height: 16),
        _section(
          context,
          'Requested Products',
          'Requested product quantities across the cycle.',
          _relatedList(context, requestLines, empty: 'No request lines.'),
        ),
      ],
      if (issuedLines.isNotEmpty) ...[
        const SizedBox(height: 16),
        _section(
          context,
          'Issued Stock',
          'Actual issued lines with commercial snapshots.',
          _relatedList(context, issuedLines, empty: 'No issued lines.'),
        ),
      ],
      if (evening.isNotEmpty) ...[
        const SizedBox(height: 16),
        _section(
          context,
          'Evening Settlement',
          'Return, retail, wholesale and deposit reconciliation.',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _overviewCard(context, evening),
              if (eveningLines.isNotEmpty) ...[
                const SizedBox(height: 10),
                _relatedList(context, eveningLines, empty: 'No evening lines.'),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _transferSections(
    BuildContext context,
    AppState app,
    Map<String, dynamic> data,
  ) {
    final detail = data['detail'] is Map
        ? Map<String, dynamic>.from(data['detail'] as Map)
        : <String, dynamic>{};
    final transfer = detail['transfer'] is Map
        ? Map<String, dynamic>.from(detail['transfer'] as Map)
        : widget.row;
    final lines = _maps(detail['lines']);
    final sent = EntityRelations.sum(lines, 'quantity');
    final received = EntityRelations.sum(lines, 'received_quantity');
    final difference = received - sent;
    final source = _branchLabel(
      app,
      EntityRelations.normalizeId(transfer['source_branch_id']),
    );
    final destination = _branchLabel(
      app,
      EntityRelations.normalizeId(transfer['destination_branch_id']),
    );
    return [
      _metrics(context, [
        _Metric(
          'Sent Qty',
          BusinessFormat.quantity(sent),
          Icons.outbox_outlined,
        ),
        _Metric(
          'Received Qty',
          BusinessFormat.quantity(received),
          Icons.move_to_inbox_outlined,
        ),
        _Metric(
          'Difference',
          BusinessFormat.quantity(difference),
          Icons.compare_arrows_rounded,
        ),
      ]),
      const SizedBox(height: 16),
      _section(
        context,
        'Route',
        'Transfer authority ke branch IDs ko authorised branch names me resolve kiya gaya hai.',
        Card(
          child: ListTile(
            leading: const Icon(Icons.route_outlined),
            title: Text(source.isEmpty ? 'Source Branch' : source),
            subtitle: Text(
              destination.isEmpty ? 'Destination Branch' : destination,
            ),
            trailing: const Icon(Icons.arrow_forward_rounded),
          ),
        ),
      ),
      const SizedBox(height: 16),
      _overviewSection(context, transfer, title: 'Transfer Summary'),
      const SizedBox(height: 16),
      _section(
        context,
        'Lifecycle',
        'Created → dispatched → received/cancelled transition timestamps.',
        _transferTimeline(context, transfer),
      ),
      const SizedBox(height: 16),
      _section(
        context,
        'Transfer Lines',
        'Sent vs received quantity with product and batch context.',
        _relatedList(context, lines, empty: 'No transfer lines.'),
      ),
    ];
  }

  Widget _metrics(BuildContext context, List<_Metric> metrics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemWidth = width >= 900
            ? (width - 24) / 3
            : width >= 560
            ? (width - 12) / 2
            : width;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: itemWidth,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          metric.icon,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                metric.label,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                metric.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _overviewSection(
    BuildContext context,
    Map<String, dynamic> row, {
    String title = 'Overview',
  }) {
    return _section(
      context,
      title,
      'Authoritative record fields.',
      _overviewCard(context, row),
    );
  }

  Widget _overviewCard(BuildContext context, Map<String, dynamic> row) {
    final fields = row.entries
        .where(
          (entry) =>
              entry.key != 'status' &&
              !BusinessFormat.isTechnicalKey(entry.key) &&
              !BusinessFormat.isBlank(entry.value) &&
              entry.value is! List &&
              entry.value is! Map,
        )
        .take(16)
        .toList();
    if (fields.isEmpty) return const _EmptyBox(message: 'No display fields.');
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      BusinessFormat.label(fields[i].key),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Text(
                      BusinessFormat.value(fields[i].key, fields[i].value),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            if (i != fields.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    String subtitle,
    Widget child,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 9),
        child,
      ],
    );
  }

  Widget _relatedList(
    BuildContext context,
    List<Map<String, dynamic>> rows, {
    String? recordType,
    required String empty,
  }) {
    if (rows.isEmpty) return _EmptyBox(message: empty);
    return Column(
      children: [
        for (final row in rows.take(30))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                title: Text(_rowTitle(row)),
                subtitle: Text(_rowSubtitle(row)),
                trailing: EntityWorkspaceScreen.supports(recordType)
                    ? const Icon(Icons.arrow_forward_ios_rounded, size: 16)
                    : null,
                onTap: EntityWorkspaceScreen.supports(recordType)
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EntityWorkspaceScreen(
                            row: row,
                            title: _rowTitle(row),
                            recordType: recordType!,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  Widget _linkedEntityCard(
    BuildContext context,
    Map<String, dynamic> row,
    String recordType,
  ) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.link_rounded),
        title: Text(_rowTitle(row)),
        subtitle: Text(_rowSubtitle(row)),
        trailing: const Icon(Icons.arrow_forward_rounded),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EntityWorkspaceScreen(
              row: row,
              title: _rowTitle(row),
              recordType: recordType,
            ),
          ),
        ),
      ),
    );
  }

  Widget _requestWorkflow(
    BuildContext context,
    List<Map<String, dynamic>> requests,
  ) {
    if (requests.isEmpty)
      return const _EmptyBox(message: 'No request history.');
    return Column(
      children: [
        for (final request in requests)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${BusinessFormat.value('type', request['type'])} Request',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        _StatusChip(
                          label: BusinessFormat.status(request['status']),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Created: ${BusinessFormat.dateTime(request['created_at'])}',
                    ),
                    if (!BusinessFormat.isBlank(request['approved_at']))
                      Text(
                        'Approved: ${BusinessFormat.dateTime(request['approved_at'])}',
                      ),
                    if (!BusinessFormat.isBlank(request['issued_at']))
                      Text(
                        'Issued: ${BusinessFormat.dateTime(request['issued_at'])}',
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _transferTimeline(
    BuildContext context,
    Map<String, dynamic> transfer,
  ) {
    final steps = <MapEntry<String, dynamic>>[
      MapEntry('Created', transfer['created_at']),
      MapEntry('Dispatched', transfer['dispatched_at']),
      MapEntry('Received', transfer['received_at']),
      MapEntry('Cancelled', transfer['cancelled_at']),
    ].where((entry) => !BusinessFormat.isBlank(entry.value)).toList();
    if (steps.isEmpty)
      return const _EmptyBox(message: 'No lifecycle timestamps.');
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            ListTile(
              leading: CircleAvatar(radius: 15, child: Text('${i + 1}')),
              title: Text(steps[i].key),
              subtitle: Text(BusinessFormat.dateTime(steps[i].value)),
            ),
            if (i != steps.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  String _rowTitle(Map<String, dynamic> row) {
    for (final key in const [
      'product_name',
      'supplier_name',
      'customer_name',
      'employee_name',
      'full_name',
      'name',
      'bill_no',
      'sale_no',
      'reference',
      'entry_no',
      'title',
    ]) {
      final value = '${row[key] ?? ''}'.trim();
      if (value.isNotEmpty) {
        return key.contains('name')
            ? BusinessFormat.displayName(value)
            : BusinessFormat.value(key, value);
      }
    }
    return 'Record';
  }

  String _rowSubtitle(Map<String, dynamic> row) {
    final parts = <String>[];
    for (final key in const [
      'business_date',
      'bill_date',
      'sale_date',
      'status',
      'quantity',
      'total_amount',
      'gross_amount',
      'outstanding_amount',
    ]) {
      if (BusinessFormat.isBlank(row[key])) continue;
      final value = BusinessFormat.value(key, row[key]);
      if (!parts.contains(value)) parts.add(value);
      if (parts.length == 3) break;
    }
    return parts.isEmpty ? 'Open record' : parts.join(' · ');
  }

  String _branchLabel(AppState app, int? id) {
    if (id == null) return '';
    for (final branch in app.branches) {
      if (EntityRelations.sameId(branch['id'], id)) {
        return '${branch['name'] ?? branch['code'] ?? ''}'.trim();
      }
    }
    return '';
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class _WorkspaceError extends StatelessWidget {
  const _WorkspaceError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 42),
          const SizedBox(height: 12),
          Text(
            'Workspace data load nahi ho paya.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}
