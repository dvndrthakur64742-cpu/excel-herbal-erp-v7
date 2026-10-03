import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/providers.dart';
import '../../core/transaction_guardrails.dart';
import '../../core/whole_pcs.dart';
import '../../core/overlay_transition.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/records_list.dart';
import '../../widgets/module_workspace.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({
    super.key,
    this.initialSection = 'stock',
    this.initialAction,
  });

  final String initialSection;
  final String? initialAction;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  int refresh = 0;
  String? message;
  bool _handledInitialAction = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_handledInitialAction || widget.initialAction == null || !mounted)
        return;
      _handledInitialAction = true;
      switch (widget.initialAction) {
        case 'new_transfer':
          await _createTransfer();
          break;
        case 'adjustment':
          await _createAdjustment();
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final tabs = <(String, Widget)>[];
    if (app.can('inventory.view')) {
      tabs.add((
        'Stock',
        AsyncPanel(
          key: ValueKey('s-${app.currentBranchId}-$refresh'),
          future: app.currentBranchId == null
              ? Future.value(const <dynamic>[])
              : api.get(
                  ApiPaths.inventoryStock,
                  query: {'branch_id': app.currentBranchId},
                ),
          builder: (context, data) =>
              RecordsList(recordType: 'stock', rows: _rows(data)),
        ),
      ));
    }
    if (app.canAny(const [
      'inventory.view',
      'inventory.transfer.create',
      'inventory.transfer.receive',
      'inventory.transfer.cancel',
    ])) {
      tabs.add((
        'Transfers',
        AsyncPanel(
          key: ValueKey('t-${app.currentBranchId}-$refresh'),
          future: app.currentBranchId == null
              ? Future.value(const <dynamic>[])
              : api.get(
                  ApiPaths.transfers,
                  query: {'branch_id': app.currentBranchId},
                ),
          builder: (context, data) => RecordsList(
            recordType: 'stock_transfer',
            rows: _rows(data),
            onTap: _transferActions,
          ),
        ),
      ));
    }
    if (app.canAny(const [
      'inventory.adjustment.create',
      'inventory.adjustment.approve',
    ])) {
      tabs.add((
        'Adjustments',
        AsyncPanel(
          key: ValueKey('a-${app.currentBranchId}-$refresh'),
          future: app.currentBranchId == null
              ? Future.value(const <dynamic>[])
              : api.get(
                  ApiPaths.adjustments,
                  query: {'branch_id': app.currentBranchId},
                ),
          emptyMessage: 'No stock adjustments are available.',
          builder: (context, data) => RecordsList(
            recordType: 'stock_adjustment',
            rows: _rows(data),
            onTap: _adjustmentActions,
          ),
        ),
      ));
    }
    if (app.can('inventory.adjustment.approve')) {
      tabs.add((
        'Quarantine',
        AsyncPanel(
          key: ValueKey('q-${app.currentBranchId}-$refresh'),
          future: app.currentBranchId == null
              ? Future.value(const <dynamic>[])
              : api.get(
                  ApiPaths.quarantine,
                  query: {'branch_id': app.currentBranchId},
                ),
          emptyMessage: 'No quarantined stock is available.',
          builder: (context, data) => RecordsList(
            recordType: 'quarantine',
            rows: _rows(data),
            onTap: _quarantineActions,
          ),
        ),
      ));
    }
    if (tabs.isEmpty)
      return const Scaffold(
        body: Center(child: Text('No authorised inventory functions.')),
      );
    final preferredLabel = switch (widget.initialSection) {
      'transfers' => 'Transfers',
      'adjustments' => 'Adjustments',
      'quarantine' => 'Quarantine',
      _ => 'Stock',
    };
    final requestedIndex = tabs.indexWhere((tab) => tab.$1 == preferredLabel);
    final initialIndex = requestedIndex < 0 ? 0 : requestedIndex;
    final actions = <Widget>[
      if (app.can('inventory.transfer.create'))
        FilledButton.icon(
          onPressed: app.currentBranchId == null ? null : _createTransfer,
          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
          label: const Text('New Transfer'),
        ),
      if (app.can('inventory.adjustment.create'))
        OutlinedButton.icon(
          onPressed: app.currentBranchId == null ? null : _createAdjustment,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Adjustment'),
        ),
      if (app.can('inventory.adjustment.create'))
        OutlinedButton.icon(
          onPressed: app.currentBranchId == null ? null : _createQuarantine,
          icon: const Icon(Icons.gpp_bad_outlined, size: 18),
          label: const Text('Quarantine Stock'),
        ),
    ];
    return DefaultTabController(
      length: tabs.length,
      initialIndex: initialIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inventory'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final tab in tabs) Tab(text: tab.$1)],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: ModuleWorkspaceHeader(
                  title: 'Inventory Control',
                  subtitle:
                      'Branch stock, transfers, adjustments and quarantine control.',
                  icon: Icons.inventory_2_outlined,
                  contextLabel: 'Business date · ${app.businessDate}',
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: BranchSelector(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ModuleActionPanel(
                  title: 'Stock Actions',
                  subtitle:
                      'Move authorised stock or record a controlled adjustment.',
                  actions: actions,
                ),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ModuleMessageBanner(message: message!),
                ),
              Expanded(
                child: app.currentBranchId == null
                    ? const Center(child: Text('Select an authorised branch.'))
                    : TabBarView(children: [for (final tab in tabs) tab.$2]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _rows(dynamic data) =>
      (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<List<Map<String, dynamic>>> _branchStock() async {
    final app = ref.read(appStateProvider);
    return (await ref.read(apiClientProvider).get(
      ApiPaths.inventoryStock,
      query: {'branch_id': app.currentBranchId},
    ) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where(
          (e) =>
              int.tryParse('${e['custodian_key']}') == 0 &&
              (double.tryParse('${e['quantity']}') ?? 0) > 0,
        )
        .toList();
  }

  Future<void> _createTransfer() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    try {
      final stock = await _branchStock();
      if (stock.isEmpty)
        throw Exception('No stock is available for transfer in the selected branch.');
      int? dest;
      int? lineId;
      final qty = TextEditingController();
      final notes = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            title: const Text('New Stock Transfer'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: dest,
                      decoration: const InputDecoration(
                        labelText: 'Destination Branch',
                      ),
                      items: app.branches
                          .where(
                            (b) =>
                                int.parse('${b['id']}') != app.currentBranchId,
                          )
                          .map(
                            (b) => DropdownMenuItem(
                              value: int.parse('${b['id']}'),
                              child: Text('${b['name']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setLocal(() => dest = v),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      menuMaxHeight: 360,
                      initialValue: lineId,
                      decoration: const InputDecoration(
                        labelText: 'Stock Item',
                      ),
                      items: List.generate(
                        stock.length,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text(
                            '${stock[i]['product_name']} · Batch ${stock[i]['batch_no'] ?? '-'} · ${BusinessFormat.quantity(stock[i]['quantity'])} PCS',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      onChanged: (v) => setLocal(() => lineId = v),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: qty,
                      keyboardType: TextInputType.number,
                      inputFormatters: [WholePcs.positiveFormatter],
                      decoration: const InputDecoration(labelText: 'Quantity'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notes,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
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
                onPressed: () =>
                    Navigator.pop(context, dest != null && lineId != null),
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        final selectedLine = lineId;
        final l = selectedLine == null ? null : stock[selectedLine];
        final q = WholePcs.parseOrZero(qty.text);
        final available =
            l == null ? 0 : (double.tryParse('${l['quantity']}') ?? 0);
        final validation = TransactionGuardrails.stockTransfer(
          sourceBranchId: app.currentBranchId,
          destinationBranchId: dest,
          itemSelected: l != null,
          quantity: q,
          available: available,
        );
        if (validation != null) throw Exception(validation);
        final selectedStock = l!;
        final batchKey = int.tryParse('${selectedStock['batch_key']}') ?? 0;
        await api.post(
          ApiPaths.transfers,
          data: {
            'source_branch_id': app.currentBranchId,
            'destination_branch_id': dest,
            'lines': [
              {
                'product_id': selectedStock['product_id'],
                'quantity': q,
                if (batchKey > 0) 'batch_id': batchKey,
              },
            ],
            'notes': notes.text.trim(),
          },
        );
        if (mounted)
          setState(() {
            refresh++;
            message = 'Stock Transfer draft created.';
          });
      }
      qty.dispose();
      notes.dispose();
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _createAdjustment() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    try {
      final stock = await _branchStock();
      if (stock.isEmpty)
        throw Exception('No stock item is available for adjustment.');
      int? lineId;
      final delta = TextEditingController();
      final reason = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            title: const Text('Stock Adjustment Request'),
            content: SizedBox(
              width: 540,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    menuMaxHeight: 360,
                    initialValue: lineId,
                    decoration: const InputDecoration(labelText: 'Stock Item'),
                    items: List.generate(
                      stock.length,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(
                          '${stock[i]['product_name']} · Batch ${stock[i]['batch_no'] ?? '-'} · ${BusinessFormat.quantity(stock[i]['quantity'])} PCS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    onChanged: (v) => setLocal(() => lineId = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: delta,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    inputFormatters: [WholePcs.signedFormatter],
                    decoration: const InputDecoration(
                      labelText: 'Quantity Delta (+ / -)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reason,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Reason'),
                  ),
                ],
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
                  lineId != null && reason.text.trim().length >= 5,
                ),
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        final l = stock[lineId!];
        final d = WholePcs.parseOrZero(delta.text, signed: true);
        if (d == 0) throw Exception('Adjustment quantity cannot be zero.');
        final batchKey = int.tryParse('${l['batch_key']}') ?? 0;
        await api.post(
          ApiPaths.adjustments,
          data: {
            'branch_id': app.currentBranchId,
            'reason': reason.text.trim(),
            'lines': [
              {
                'product_id': l['product_id'],
                'quantity_delta': d,
                if (batchKey > 0) 'batch_id': batchKey,
              },
            ],
          },
        );
        if (mounted)
          setState(() {
            refresh++;
            message = 'Stock adjustment submitted for approval.';
          });
      }
      delta.dispose();
      reason.dispose();
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  void _transferActions(Map<String, dynamic> r) {
    final app = ref.read(appStateProvider);
    final id = int.parse('${r['id']}');
    final status = '${r['status']}';
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(title: Text('Transfer #$id · ${BusinessFormat.status(status)}')),
            if (status == 'draft' && app.can('inventory.transfer.create'))
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Pack'),
                onTap: () => _act(ApiPaths.transferPack(id)),
              ),
            if (status == 'packed' && app.can('inventory.transfer.create'))
              ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: const Text('Dispatch'),
                onTap: () => _act(ApiPaths.transferDispatch(id)),
              ),
            if (status == 'in_transit' && app.can('inventory.transfer.receive'))
              ListTile(
                leading: const Icon(Icons.move_to_inbox_outlined),
                title: const Text('Receive / Verify Quantity'),
                onTap: () => _receiveTransfer(id),
              ),
            if (status == 'difference_reported' &&
                app.can('inventory.adjustment.approve'))
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Approve Shortage Correction'),
                subtitle: const Text(
                  'Stock Variance accounting entry ke saath.',
                ),
                onTap: () => _reasonAction(
                  ApiPaths.transferCorrect(id),
                  'Discrepancy resolution reason',
                  'note',
                ),
              ),
            if ((status == 'draft' || status == 'packed') &&
                app.can('inventory.transfer.create'))
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Cancel Transfer'),
                onTap: () => _reasonAction(
                  ApiPaths.transferCancel(id),
                  'Cancellation reason',
                  'reason',
                ),
              ),
            if (status == 'in_transit' && app.can('inventory.transfer.cancel'))
              ListTile(
                leading: const Icon(Icons.settings_backup_restore_outlined),
                title: const Text('Cancel In-Transit Transfer'),
                subtitle: const Text(
                  'Higher authority + maker/checker; source stock restore hoga.',
                ),
                onTap: () => _reasonAction(
                  ApiPaths.transferCancel(id),
                  'In-transit cancellation reason',
                  'reason',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _receiveTransfer(int id) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    try {
      final detail = Map<String, dynamic>.from(
        await ref.read(apiClientProvider).get(ApiPaths.transferDetail(id))
            as Map,
      );
      final lines = (detail['lines'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final controllers = <int, TextEditingController>{
        for (final l in lines)
          int.parse('${l['id']}'): TextEditingController(
            text: '${l['quantity']}',
          ),
      };
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Receive Transfer #$id'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: lines.map((l) {
                  final lid = int.parse('${l['id']}');
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${l['product_name']} · Batch ${l['batch_no'] ?? '-'}\nDispatched ${l['quantity']} ${l['uom'] ?? ''}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: controllers[lid],
                              keyboardType: TextInputType.number,
                              inputFormatters: [WholePcs.positiveFormatter],
                              decoration: const InputDecoration(
                                labelText: 'Received',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm Receipt'),
            ),
          ],
        ),
      );
      if (ok == true) {
        final payload = <Map<String, dynamic>>[];
        for (final l in lines) {
          final lid = int.parse('${l['id']}');
          final received = WholePcs.parseOrZero(controllers[lid]!.text);
          final dispatched = double.tryParse('${l['quantity']}') ?? 0;
          if (received < 0 || received > dispatched + .0001)
            throw Exception(
              '${l['product_name']} received quantity invalid hai.',
            );
          payload.add({'transfer_line_id': lid, 'received_quantity': received});
        }
        final result = await ref
            .read(apiClientProvider)
            .post(ApiPaths.transferReceive(id), data: {'lines': payload});
        if (mounted)
          setState(() {
            refresh++;
            message = 'Transfer receipt: ${BusinessFormat.status((result as Map)['status'])}';
          });
      }
      for (final c in controllers.values) c.dispose();
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  Future<void> _createQuarantine() async {
    final app = ref.read(appStateProvider);
    final api = ref.read(apiClientProvider);
    try {
      final stock = await _branchStock();
      if (stock.isEmpty) {
        throw Exception('No stock item is available for quarantine.');
      }
      int? lineId;
      final qty = TextEditingController();
      final reason = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            title: const Text('Quarantine Stock'),
            content: SizedBox(
              width: 540,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    menuMaxHeight: 360,
                    initialValue: lineId,
                    decoration: const InputDecoration(labelText: 'Stock Item'),
                    items: List.generate(
                      stock.length,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(
                          '${stock[i]['product_name']} · Batch ${stock[i]['batch_no'] ?? '-'} · ${BusinessFormat.quantity(stock[i]['quantity'])} PCS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    onChanged: (v) => setLocal(() => lineId = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: qty,
                    keyboardType: TextInputType.number,
                    inputFormatters: [WholePcs.positiveFormatter],
                    decoration: const InputDecoration(labelText: 'Quantity'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reason,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Quarantine reason',
                    ),
                  ),
                ],
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
                  lineId != null && reason.text.trim().length >= 5,
                ),
                child: const Text('Hold Stock'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        final l = stock[lineId!];
        final q = WholePcs.parseOrZero(qty.text);
        final available = double.tryParse('${l['quantity']}') ?? 0;
        if (q <= 0 || q > available + .0001) {
          throw Exception('Enter a valid quantity within the available stock.');
        }
        final batchKey = int.tryParse('${l['batch_key']}') ?? 0;
        await api.post(
          ApiPaths.quarantine,
          data: {
            'branch_id': app.currentBranchId,
            'product_id': l['product_id'],
            'quantity': q,
            if (batchKey > 0) 'batch_id': batchKey,
            'reason': reason.text.trim(),
          },
        );
        if (mounted) {
          setState(() {
            refresh++;
            message = 'Stock moved to quarantine for controlled review.';
          });
        }
      }
      qty.dispose();
      reason.dispose();
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  void _adjustmentActions(Map<String, dynamic> r) {
    final app = ref.read(appStateProvider);
    if ('${r['status']}' != 'pending' ||
        !app.can('inventory.adjustment.approve')) return;
    final id = int.parse('${r['id']}');
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(title: Text('Adjustment #$id · ${r['reason']}')),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Approve'),
              onTap: () => _act(
                ApiPaths.adjustmentDecision(id),
                data: {'approve': true},
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Reject'),
              onTap: () => _act(
                ApiPaths.adjustmentDecision(id),
                data: {'approve': false},
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _quarantineActions(Map<String, dynamic> r) {
    final app = ref.read(appStateProvider);
    if (!app.can('inventory.adjustment.approve')) return;
    final id = int.parse('${r['id']}');
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text(
                '${r['product_name']} · ${r['quantity']} · ${r['reason']}',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.inventory_outlined),
              title: const Text('Release to Stock'),
              onTap: () => _quarantineReason(id, 'release'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Write Off'),
              onTap: () => _quarantineReason(id, 'write_off'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _quarantineReason(int id, String action) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    final reason = await _askReason(
      action == 'release' ? 'Release reason' : 'Write-off reason',
    );
    if (reason == null) return;
    await _act(
      ApiPaths.quarantineResolve(id),
      data: {'action': action, 'reason': reason},
      closeSheet: false,
    );
  }

  Future<void> _reasonAction(String path, String title, String key) async {
    final closed = await OverlayTransition.closeAndSettle(context);
    if (!closed || !mounted) return;
    final reason = await _askReason(title);
    if (reason == null) return;
    await _act(path, data: {key: reason}, closeSheet: false);
  }

  Future<String?> _askReason(String title) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 5) Navigator.pop(context, value);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<void> _act(
    String path, {
    Map<String, dynamic>? data,
    bool closeSheet = true,
  }) async {
    if (closeSheet) {
      final closed = await OverlayTransition.closeAndSettle(context);
      if (!closed || !mounted) return;
    }
    try {
      final result =
          await ref.read(apiClientProvider).post(path, data: data ?? const {});
      if (mounted)
        setState(() {
          refresh++;
          message = 'Done: $result';
        });
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }
}
