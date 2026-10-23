import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/gps_route_view.dart';
import '../../widgets/records_list.dart';
import 'employee_finance_review_panel.dart';

/// Existing V7 canonical employee 360 REST response. No shadow customer,
/// sales, stock, attendance or ledger state is maintained in the Flutter app.
/// This is intentionally a detail/profile screen, NOT the employee dashboard.
class Employee360Screen extends ConsumerStatefulWidget {
  const Employee360Screen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.openFinanceReview = false,
  });

  final int employeeId;
  final String employeeName;
  /// Direct the manager to the existing read-only Finance Review tab.
  /// The standard Summary remains the fallback when finance permission is absent.
  final bool openFinanceReview;

  @override
  ConsumerState<Employee360Screen> createState() => _Employee360ScreenState();
}

class _Employee360ScreenState extends ConsumerState<Employee360Screen> {
  late String _from;
  late String _to;
  late Future<Map<String, dynamic>> _profile;

  @override
  void initState() {
    super.initState();
    final app = ref.read(appStateProvider);
    _from = app.businessMonthStart;
    _to = app.businessDate;
    _profile = _readProfile();
  }

  Future<Map<String, dynamic>> _readProfile() async {
    final response = await ref.read(apiClientProvider).get(
      ApiPaths.employee360(widget.employeeId),
      query: {'from': _from, 'to': _to},
    );
    if (response is! Map) {
      throw const FormatException('Employee profile response is invalid.');
    }
    final data = Map<String, dynamic>.from(response);
    if (data['read_only'] != true || data['dashboard_unchanged'] != true) {
      throw const FormatException('Employee profile safety contract is missing.');
    }
    final employee = data['employee'];
    if (employee is! Map ||
        int.tryParse('${employee['id']}') != widget.employeeId) {
      throw const FormatException('Employee profile identity mismatch.');
    }
    return data;
  }

  void _refresh() => setState(() => _profile = _readProfile());

  Future<void> _choosePeriod() async {
    final start = DateTime.tryParse(_from);
    final end = DateTime.tryParse(_to);
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: start != null && end != null && !end.isBefore(start)
          ? DateTimeRange(start: start, end: end)
          : null,
      helpText: 'Employee 360 reporting period',
    );
    if (!mounted || selected == null) return;
    if (selected.end.difference(selected.start).inDays > 366) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select up to 366 days.')),
      );
      return;
    }
    String date(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    setState(() {
      _from = date(selected.start);
      _to = date(selected.end);
      _profile = _readProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final showGps = app.can('workforce.gps.team.view');
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.employeeName} · Employee 360'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_outlined),
            tooltip: 'Select reporting period',
            onPressed: _choosePeriod,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh employee records',
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Employee360Failure(
              message: UiError.message(snapshot.error!),
              retry: _refresh,
            );
          }
          final profile = snapshot.data;
          if (profile == null) {
            return _Employee360Failure(
              message: 'Employee profile is not available.',
              retry: _refresh,
            );
          }
          final ledgerData = profile['person_ledger'];
          final financeVisible = ledgerData is Map &&
              ledgerData['visible'] == true &&
              app.can('finance.accounting.view');
          final tabs = <Tab>[
            const Tab(text: 'Summary'),
            const Tab(text: 'Sales'),
            const Tab(text: 'Stock'),
            const Tab(text: 'Stock Requests'),
            const Tab(text: 'Daily Reconciliation'),
            const Tab(text: 'Attendance'),
            if (financeVisible) const Tab(text: 'Ledger'),
            if (financeVisible) const Tab(text: 'Person Ledger'),
            if (financeVisible) const Tab(text: 'Cash Responsibility'),
            if (financeVisible) const Tab(text: 'Cash Control'),
            if (financeVisible) const Tab(text: 'Finance Review'),
            if (showGps) const Tab(text: 'GPS Route'),
          ];
          final financeIndex =
              tabs.indexWhere((tab) => tab.text == 'Finance Review');
          final cashControlIndex =
              tabs.indexWhere((tab) => tab.text == 'Cash Control');
          final personLedgerIndex =
              tabs.indexWhere((tab) => tab.text == 'Person Ledger');
          return DefaultTabController(
            key: ValueKey('employee360-${widget.employeeId}-$financeVisible-$showGps-${widget.openFinanceReview}'),
            length: tabs.length,
            initialIndex: widget.openFinanceReview && financeVisible &&
                    financeIndex >= 0
                ? financeIndex
                : 0,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$_from to $_to · Posted records only · Read-only',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                TabBar(isScrollable: true, tabs: tabs),
                Expanded(
                  child: TabBarView(
                    children: [
                      _Employee360Summary(profile: profile),
                      _Employee360PagedRegister(
                        employeeId: widget.employeeId,
                        type: 'sales',
                        from: _from,
                        to: _to,
                      ),
                      _Employee360PagedRegister(
                        employeeId: widget.employeeId,
                        type: 'stock',
                        from: _from,
                        to: _to,
                      ),
                      _Employee360PagedRegister(
                        employeeId: widget.employeeId,
                        type: 'requests',
                        from: _from,
                        to: _to,
                      ),
                      _Employee360PagedRegister(
                        employeeId: widget.employeeId,
                        type: 'reconciliation',
                        from: _from,
                        to: _to,
                      ),
                      _Employee360List(
                        title: 'Attendance by business date',
                        rows: profile['attendance_history'],
                      ),
                      if (financeVisible)
                        _Employee360List(
                          title: 'Employee-tagged journal lines (not a full cash ledger)',
                          rows: ledgerData['entries'],
                        ),
                      if (financeVisible)
                        _Employee360PagedRegister(
                          employeeId: widget.employeeId,
                          type: 'person_ledger',
                          from: _from,
                          to: _to,
                        ),
                      if (financeVisible)
                        _Employee360TransitLedger(rows: ledgerData['entries']),
                      if (financeVisible)
                        _Employee360CashControl(
                          employeeId: widget.employeeId,
                          from: _from,
                          to: _to,
                        ),
                      if (financeVisible)
                        Builder(
                          builder: (financeTabContext) => EmployeeFinanceReviewPanel(
                            employeeId: widget.employeeId,
                            from: _from,
                            to: _to,
                            onOpenCashControl: cashControlIndex >= 0
                                ? () => DefaultTabController.of(financeTabContext)
                                    .animateTo(cashControlIndex)
                                : null,
                            onOpenPersonLedger: personLedgerIndex >= 0
                                ? () => DefaultTabController.of(financeTabContext)
                                    .animateTo(personLedgerIndex)
                                : null,
                          ),
                        ),
                      if (showGps)
                        _Employee360Gps(
                          employeeId: widget.employeeId,
                          from: _from,
                          to: _to,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Employee360Failure extends StatelessWidget {
  const _Employee360Failure({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 42),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: retry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}

List<Map<String, dynamic>> _recordRows(dynamic data) {
  if (data is! List) return const [];
  return data.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
}

class _Employee360Summary extends StatelessWidget {
  const _Employee360Summary({required this.profile});
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final employee = Map<String, dynamic>.from(profile['employee'] as Map);
    final months = _recordRows(profile['monthly_summary']);
    final stock = _recordRows(profile['employee_stock']);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${employee['full_name'] ?? ''} · ${employee['employee_code'] ?? ''}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text('Designation: ${employee['designation_code'] ?? '-'}'
            '   •   Status: ${employee['status'] ?? '-'}'),
        const SizedBox(height: 14),
        Text('Monthly sales, performance points and attendance',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (months.isEmpty)
          const ListTile(title: Text('No posted monthly activity in this period.'))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Month')),
                DataColumn(label: Text('Sale ₹')),
                DataColumn(label: Text('Points')),
                DataColumn(label: Text('Days present')),
              ],
              rows: months.map((m) => DataRow(cells: [
                DataCell(Text('${m['month'] ?? ''}')),
                DataCell(Text('${m['sales_amount'] ?? '0.00'}')),
                DataCell(Text('${m['points'] ?? '0.00'}')),
                DataCell(Text('${m['days_present'] ?? 0}')),
              ])).toList(),
            ),
          ),
        const SizedBox(height: 16),
        Text('Employee stock currently held',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        if (stock.isEmpty)
          const ListTile(title: Text('No positive employee-custodied stock.'))
        else
          ...stock.take(15).map((r) => ListTile(
                dense: true,
                title: Text('${r['product_name'] ?? r['sku'] ?? ''}'),
                subtitle: Text('Branch ${r['branch_id'] ?? ''} · Batch ${r['batch_key'] ?? 0}'),
                trailing: Text('${r['quantity'] ?? 0} PCS'),
              )),
        if (stock.length > 15)
          Text('Showing 15 of ${stock.length} stock balances.'),
        const SizedBox(height: 12),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Cash remittance is not yet reconciled here'),
          subtitle: Text(
            'Sales and Cash/UPI settlements do not prove that field cash was deposited with the branch. No outstanding is inferred.',
          ),
        ),
      ],
    );
  }
}

class _Employee360List extends StatelessWidget {
  const _Employee360List({required this.title, required this.rows});
  final String title;
  final dynamic rows;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          Expanded(child: RecordsList(rows: _recordRows(rows))),
        ],
      );
}

/// Finance-only, read-only view of canonical employee-tagged journal lines.
/// History is paginated upstream (1000 limit), so never infer a final liability
/// balance from the rows present here. No UAT remittance fields are asserted live.
class _Employee360TransitLedger extends StatelessWidget {
  const _Employee360TransitLedger({required this.rows});
  final dynamic rows;

  @override
  Widget build(BuildContext context) {
    final tagged = _recordRows(rows)
        .where((e) =>
            '${e['account_code'] ?? ''}' == 'EMPLOYEE_CASH_IN_TRANSIT' &&
            (e['source_type'] == 'b2b_retailer_sale' ||
             e['source_type'] == 'b2b_cash_remittance'))
        .toList();
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Field Cash Dr = received from customer; Cr = cashier handover '
            'journal. This is an employee-tagged journal excerpt, not a '
            'complete balance or independent proof of cash deposit.',
          ),
        ),
        Expanded(child: RecordsList(rows: tagged)),
      ],
    );
  }
}

class _Employee360PagedRegister extends ConsumerStatefulWidget {
  const _Employee360PagedRegister({
    required this.employeeId,
    required this.type,
    required this.from,
    required this.to,
  });
  final int employeeId;
  final String type;
  final String from;
  final String to;

  @override
  ConsumerState<_Employee360PagedRegister> createState() =>
      _Employee360PagedRegisterState();
}

class _Employee360PagedRegisterState extends ConsumerState<_Employee360PagedRegister> {
  static const _pageSize = 25;
  late Future<Map<String, dynamic>> _result;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _result = _fetch();
  }

  @override
  void didUpdateWidget(covariant _Employee360PagedRegister oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employeeId != widget.employeeId ||
        oldWidget.type != widget.type ||
        oldWidget.from != widget.from || oldWidget.to != widget.to) {
      _page = 1;
      _result = _fetch();
    }
  }

  Future<Map<String, dynamic>> _fetch() async {
    final response = await ref.read(apiClientProvider).get(
      ApiPaths.employee360Register(widget.employeeId),
      query: {
        'type': widget.type,
        'from': widget.from,
        'to': widget.to,
        'page': _page,
        'page_size': _pageSize,
      },
    );
    if (response is! Map) {
      throw const FormatException('Employee register response invalid.');
    }
    final data = Map<String, dynamic>.from(response);
    if (data['read_only'] != true ||
        data['register'] != widget.type ||
        int.tryParse('${data['employee_id']}') != widget.employeeId ||
        int.tryParse('${data['page']}') != _page ||
        (widget.type == 'person_ledger' &&
            (data['balance_basis'] != 'complete_tagged_movement_history_not_visible_page' ||
             data['financial_accounts'] is! List ||
             data['stock_items'] is! List ||
             data['employee_cash_handover_verified'] != false ||
             data['upi_bank_settlement_verified'] != false))) {
      throw const FormatException('Employee register security contract mismatch.');
    }
    return data;
  }

  void _next(int page) => setState(() {
        _page = page;
        _result = _fetch();
      });

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _result,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Employee360Failure(
              message: UiError.message(snapshot.error!),
              retry: () => _next(_page),
            );
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          final rows = _recordRows(data['rows']);
          final hasMore = data['has_more'] == true;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Text(
                  widget.type == 'sales'
                      ? 'Posted sales/points · not proof of branch cash deposit'
                      : 'Employee-custodied stock IN/OUT · audit trail',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (widget.type == 'person_ledger')
                SizedBox(
                  height: 166,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      const Text('INR per employee-tagged GL account (Dr−Cr), not bank/cashier proof'),
                      ..._recordRows(data['financial_accounts']).take(5).map(
                        (a) => Text(
                          '${a['account_code']}: opening ${a['opening_debit_minus_credit']} + '
                          'Dr ${a['period_debit']} − Cr ${a['period_credit']} = '
                          '${a['closing_debit_minus_credit']} INR',
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text('Stock PCS per branch/product/batch; movements, not physical count'),
                      ..._recordRows(data['stock_items']).take(5).map(
                        (s) => Text(
                          'Branch ${s['branch_id']} · Product ${s['product_id']} '
                          '· Batch ${s['batch_key']}: '
                          '${s['opening_quantity']} + ${s['period_in']} − '
                          '${s['period_out']} = ${s['closing_quantity']} PCS',
                        ),
                      ),
                      const Text('Sales INR and points are separate events, not balances.'),
                    ],
                  ),
                ),
              Expanded(child: RecordsList(rows: rows)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: _page == 1 ? null : () => _next(_page - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('Page $_page'),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: hasMore ? () => _next(_page + 1) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          );
        },
      );
}

class _Employee360Gps extends ConsumerStatefulWidget {
  const _Employee360Gps({
    required this.employeeId,
    required this.from,
    required this.to,
  });
  final int employeeId;
  final String from;
  final String to;

  @override
  ConsumerState<_Employee360Gps> createState() => _Employee360GpsState();
}

class _Employee360GpsState extends ConsumerState<_Employee360Gps> {
  late Future<List<Map<String, dynamic>>> _points;

  @override
  void initState() {
    super.initState();
    _points = _load();
  }

  @override
  void didUpdateWidget(covariant _Employee360Gps oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employeeId != widget.employeeId ||
        oldWidget.from != widget.from || oldWidget.to != widget.to) {
      _points = _load();
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    // Reuse the existing protected V7 GPS route API; there is no manual duty toggle.
    // Restrict to one selected business day to keep the map focused and bounded.
    final day = DateTime.tryParse(widget.to);
    if (day == null) throw const FormatException('Invalid route date.');
    final start = DateTime(day.year, day.month, day.day).toUtc();
    final end = DateTime(day.year, day.month, day.day, 23, 59, 59).toUtc();
    final response = await ref.read(apiClientProvider).get(
      ApiPaths.gpsRoute,
      query: {
        'employee_id': widget.employeeId,
        'from': start.toIso8601String(),
        'to': end.toIso8601String(),
      },
    );
    return _recordRows(response);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _points,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Employee360Failure(
              message: UiError.message(snapshot.error!),
              retry: () => setState(() => _points = _load()),
            );
          }
          final points = snapshot.data ?? const <Map<String, dynamic>>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Recorded duty route on ${widget.to}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              GpsRouteView(points: points),
            ],
          );
        },
      );
}


/// Finance-only canonical accounting reconciliation. A matching ledger debit
/// is never evidence of physical employee cash remittance to the cashier.
class _Employee360CashControl extends ConsumerStatefulWidget {
  const _Employee360CashControl({
    required this.employeeId,
    required this.from,
    required this.to,
  });

  final int employeeId;
  final String from;
  final String to;

  @override
  ConsumerState<_Employee360CashControl> createState() =>
      _Employee360CashControlState();
}

class _Employee360CashControlState
    extends ConsumerState<_Employee360CashControl> {
  int _page = 1;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _Employee360CashControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employeeId != widget.employeeId ||
        oldWidget.from != widget.from || oldWidget.to != widget.to) {
      _page = 1;
      _future = _load();
    }
  }

  Future<Map<String, dynamic>> _load() async {
    final raw = await ref.read(apiClientProvider).get(
      ApiPaths.employee360CashControl(widget.employeeId),
      query: {'from': widget.from, 'to': widget.to, 'page': _page, 'page_size': 25},
    );
    if (raw is! Map) {
      throw const FormatException('Cash control response is invalid.');
    }
    final data = Map<String, dynamic>.from(raw);
    if (data['read_only'] != true ||
        data['cash_remittance_status'] != 'not_available_in_legacy_v7' ||
        int.tryParse('${data['employee_id']}') != widget.employeeId) {
      throw const FormatException('Cash control safety contract is missing.');
    }
    return data;
  }

  void _pageTo(int value) => setState(() {
        _page = value;
        _future = _load();
      });

  static String _rupees(dynamic paise) {
    final v = int.tryParse('$paise') ?? 0;
    return '₹${v ~/ 100}.${(v % 100).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Client-side hiding is only presentational. The API rechecks finance RBAC.
    if (!ref.watch(appStateProvider).can('finance.accounting.view')) {
      return const Center(child: Text('Finance permission required.'));
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _Employee360Failure(
            message: UiError.message(snapshot.error!),
            retry: () => _pageTo(_page),
          );
        }
        final data = snapshot.data!;
        final rows = _recordRows(data['rows']);
        final totals = Map<String, dynamic>.from(
          (data['page_totals'] as Map?) ?? const {},
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Legacy V7 accounting check only. Matching journal amounts do NOT prove employee cash was handed to cashier or UPI reached the bank.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Page $_page · Cash posted: ${_rupees(totals['cash_reported_paise'])} · '
                'UPI posted: ${_rupees(totals['upi_reported_paise'])}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No posted daily closing records.'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final status = '${row['journal_check'] ?? 'unknown'}';
                        final matched = status == 'journal_amounts_match';
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5,
                          ),
                          child: ListTile(
                            leading: Icon(
                              matched ? Icons.fact_check_outlined : Icons.warning_amber_rounded,
                              color: matched ? null : Theme.of(context).colorScheme.error,
                            ),
                            title: Text(
                              '${row['business_date'] ?? ''} · Daily #${row['daily_cycle_id'] ?? ''}',
                            ),
                            subtitle: Text(
                              'Cash: ${_rupees(row['reported_cash_paise'])} · '
                              'UPI: ${_rupees(row['reported_upi_paise'])}\n'
                              'Journal: $status · Cash handover: '
                              '${row['cash_remittance_proof'] ?? 'unknown'}',
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton(
                    onPressed: _page <= 1 ? null : () => _pageTo(_page - 1),
                    child: const Text('Previous'),
                  ),
                  OutlinedButton(
                    onPressed: data['has_more'] == true
                        ? () => _pageTo(_page + 1)
                        : null,
                    child: const Text('Next'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
