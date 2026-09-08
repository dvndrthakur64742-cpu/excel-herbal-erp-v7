from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
changes: dict[str, str] = {}


def current(path: str) -> str:
    if path in changes:
        return changes[path]
    return (ROOT / path).read_text(encoding="utf-8")


def swap(path: str, old: str, new: str, expected: int = 1) -> None:
    text = current(path)
    found = text.count(old)
    if found != expected:
        raise RuntimeError(f"{path}: expected {expected} occurrence(s), found {found}: {old[:100]!r}")
    changes[path] = text.replace(old, new, expected)


def put(path: str, content: str) -> None:
    changes[path] = content


# ---------------------------------------------------------------------------
# Central Daily Order workflow policy.
# ---------------------------------------------------------------------------
put(
    "flutter-app/lib/core/daily_order_workflow.dart",
    r'''abstract final class DailyOrderWorkflow {
  static const Set<String> _blockingAdditionalStatuses = {
    'draft',
    'submitted',
    'approved',
  };

  static bool canOperateOwnOrder(Iterable<String> capabilities) =>
      capabilities.contains('daily_order.self') ||
      capabilities.contains('daily_order.others');

  static bool canSubmitDraft(
    String cycleStatus,
    Iterable<String> capabilities,
  ) =>
      cycleStatus == 'morning_draft' && canOperateOwnOrder(capabilities);

  static bool canApproveRequest(
    String requestStatus,
    Iterable<String> capabilities,
  ) =>
      requestStatus == 'submitted' && capabilities.contains('daily_order.approve');

  static bool canIssueRequest(
    String requestStatus,
    Iterable<String> capabilities,
  ) =>
      requestStatus == 'approved' && capabilities.contains('daily_order.issue');

  static bool hasBlockingAdditionalRequests(
    Iterable<Map<String, dynamic>> requests,
  ) {
    for (final request in requests) {
      if ('${request['type']}' != 'additional') continue;
      if (_blockingAdditionalStatuses.contains('${request['status']}')) return true;
    }
    return false;
  }

  static String? eveningBlockReason({
    required String cycleStatus,
    required Iterable<Map<String, dynamic>> requests,
    required Iterable<String> capabilities,
  }) {
    if (!canOperateOwnOrder(capabilities)) {
      return 'Evening Closing ke liye Daily Order self/others permission required hai.';
    }
    if (cycleStatus != 'issued') {
      return 'Evening Closing sirf issued Daily Order par start ho sakti hai.';
    }
    if (hasBlockingAdditionalRequests(requests)) {
      return 'Additional Requirement abhi approval/issue pending hai. Pehle uska sequence complete karein.';
    }
    return null;
  }
}
''',
)

# ---------------------------------------------------------------------------
# One FEFO stock allocation engine for both My Work and Team issue flows.
# ---------------------------------------------------------------------------
put(
    "flutter-app/lib/core/stock_allocation.dart",
    r'''class StockAllocationException implements Exception {
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
        throw const StockAllocationException('Approved request line invalid hai.');
      }

      final candidateIndexes = <int>[
        for (var i = 0; i < stockRows.length; i++)
          if (int.tryParse('${stockRows[i]['product_id']}') == productId) i,
      ]
        ..sort(
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
''',
)

# ---------------------------------------------------------------------------
# Strict Final Post monetary guardrails.
# ---------------------------------------------------------------------------
put(
    "flutter-app/lib/core/daily_order_math.dart",
    r'''abstract final class DailyOrderMath {
  static double retailSold(num issued, num returned, num wholesale) {
    final value =
        issued.toDouble() - returned.toDouble() - wholesale.toDouble();
    return value > 0 ? value : 0;
  }

  static bool quantitiesFit(num issued, num returned, num wholesale) =>
      returned >= 0 &&
      wholesale >= 0 &&
      returned.toDouble() + wholesale.toDouble() <= issued.toDouble() + 0.0001;

  static bool wholesaleRateValid(
    num wholesaleQty,
    num wholesaleRate,
    num retailRate,
  ) {
    if (wholesaleQty <= 0) return true;
    return wholesaleRate > 0 &&
        wholesaleRate.toDouble() <= retailRate.toDouble() + 0.005;
  }

  static double totalAmount(
    num retailSold,
    num retailRate,
    num wholesaleQty,
    num wholesaleRate,
  ) =>
      retailSold.toDouble() * retailRate.toDouble() +
      wholesaleQty.toDouble() * wholesaleRate.toDouble();

  static bool depositMatches(num entered, num expected) =>
      (entered.toDouble() - expected.toDouble()).abs() <= 0.005;

  static bool paymentComponentsValid(num cash, num online) =>
      cash.toDouble().isFinite &&
      online.toDouble().isFinite &&
      cash.toDouble() >= 0 &&
      online.toDouble() >= 0;

  static bool reconciliationMatches(num serverExpected, num calculated) =>
      (serverExpected.toDouble() - calculated.toDouble()).abs() <= 0.01;

  static bool finalPostAllowed({
    required num cash,
    required num online,
    required num expected,
    required num calculatedExpected,
    num? serverExpected,
  }) {
    if (!paymentComponentsValid(cash, online)) return false;
    if (!depositMatches(cash.toDouble() + online.toDouble(), expected)) {
      return false;
    }
    if (serverExpected != null &&
        !reconciliationMatches(serverExpected, calculatedExpected)) {
      return false;
    }
    return true;
  }
}
''',
)

put(
    "flutter-app/test/daily_order_math_test.dart",
    r'''import 'package:excel_herbal_erp/core/daily_order_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retail sold excludes returns and wholesale', () {
    expect(DailyOrderMath.retailSold(10, 2, 3), 5);
    expect(DailyOrderMath.retailSold(10, 2, 0), 8);
  });

  test('retail sold never becomes negative', () {
    expect(DailyOrderMath.retailSold(5, 4, 3), 0);
  });

  test('return plus wholesale cannot exceed issued', () {
    expect(DailyOrderMath.quantitiesFit(10, 2, 8), isTrue);
    expect(DailyOrderMath.quantitiesFit(10, 3, 8), isFalse);
  });

  test('wholesale rate validation', () {
    expect(DailyOrderMath.wholesaleRateValid(2, 90, 100), isTrue);
    expect(DailyOrderMath.wholesaleRateValid(2, 110, 100), isFalse);
    expect(DailyOrderMath.wholesaleRateValid(2, 0, 100), isFalse);
    expect(DailyOrderMath.wholesaleRateValid(0, 0, 100), isTrue);
  });

  test('retail plus wholesale amount is calculated', () {
    expect(DailyOrderMath.totalAmount(5, 100, 2, 80), 660);
  });

  test('deposit equality uses rounding tolerance', () {
    expect(DailyOrderMath.depositMatches(1000, 1000.004), isTrue);
    expect(DailyOrderMath.depositMatches(1000, 1000.01), isFalse);
  });

  test('negative payment components are rejected', () {
    expect(DailyOrderMath.paymentComponentsValid(500, 500), isTrue);
    expect(DailyOrderMath.paymentComponentsValid(-1, 1001), isFalse);
    expect(DailyOrderMath.paymentComponentsValid(1001, -1), isFalse);
  });

  test('server and product totals must reconcile', () {
    expect(DailyOrderMath.reconciliationMatches(1000, 1000.009), isTrue);
    expect(DailyOrderMath.reconciliationMatches(1000, 999.98), isFalse);
  });

  test('final post requires valid components, deposit and reconciliation', () {
    expect(
      DailyOrderMath.finalPostAllowed(
        cash: 600,
        online: 400,
        expected: 1000,
        calculatedExpected: 1000,
        serverExpected: 1000,
      ),
      isTrue,
    );
    expect(
      DailyOrderMath.finalPostAllowed(
        cash: -100,
        online: 1100,
        expected: 1000,
        calculatedExpected: 1000,
        serverExpected: 1000,
      ),
      isFalse,
    );
    expect(
      DailyOrderMath.finalPostAllowed(
        cash: 600,
        online: 400,
        expected: 1000,
        calculatedExpected: 950,
        serverExpected: 1000,
      ),
      isFalse,
    );
  });
}
''',
)

put(
    "flutter-app/test/daily_order_workflow_test.dart",
    r'''import 'package:excel_herbal_erp/core/daily_order_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('request approval and issue require exact permissions', () {
    expect(
      DailyOrderWorkflow.canApproveRequest('submitted', ['daily_order.approve']),
      isTrue,
    );
    expect(
      DailyOrderWorkflow.canApproveRequest('submitted', ['daily_order.others']),
      isFalse,
    );
    expect(
      DailyOrderWorkflow.canIssueRequest('approved', ['daily_order.issue']),
      isTrue,
    );
    expect(
      DailyOrderWorkflow.canIssueRequest('approved', ['daily_order.review']),
      isFalse,
    );
  });

  test('evening closing is blocked while additional request is pending', () {
    final requests = <Map<String, dynamic>>[
      {'type': 'initial', 'status': 'issued'},
      {'type': 'additional', 'status': 'submitted'},
    ];
    expect(
      DailyOrderWorkflow.eveningBlockReason(
        cycleStatus: 'issued',
        requests: requests,
        capabilities: ['daily_order.self'],
      ),
      isNotNull,
    );
  });

  test('evening closing opens after additional sequence completes', () {
    final requests = <Map<String, dynamic>>[
      {'type': 'initial', 'status': 'issued'},
      {'type': 'additional', 'status': 'issued'},
    ];
    expect(
      DailyOrderWorkflow.eveningBlockReason(
        cycleStatus: 'issued',
        requests: requests,
        capabilities: ['daily_order.self'],
      ),
      isNull,
    );
  });
}
''',
)

put(
    "flutter-app/test/stock_allocation_test.dart",
    r'''import 'package:excel_herbal_erp/core/stock_allocation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FEFO allocation consumes earliest expiry first', () {
    final allocations = StockAllocation.fefo(
      requestLines: [
        {'id': 10, 'product_id': 1, 'product_name': 'P1', 'quantity': 6},
      ],
      stock: [
        {
          'product_id': 1,
          'custodian_key': 0,
          'quantity': 5,
          'batch_key': 20,
          'expires_on': '2027-12-31',
        },
        {
          'product_id': 1,
          'custodian_key': 0,
          'quantity': 4,
          'batch_key': 10,
          'expires_on': '2027-01-31',
        },
      ],
    );
    expect(allocations.length, 2);
    expect(allocations[0]['batch_id'], 10);
    expect(allocations[0]['quantity'], 4);
    expect(allocations[1]['batch_id'], 20);
    expect(allocations[1]['quantity'], 2);
  });

  test('allocation fails when authorised stock is insufficient', () {
    expect(
      () => StockAllocation.fefo(
        requestLines: [
          {'id': 10, 'product_id': 1, 'product_name': 'P1', 'quantity': 6},
        ],
        stock: [
          {'product_id': 1, 'custodian_key': 0, 'quantity': 5},
        ],
      ),
      throwsA(isA<StockAllocationException>()),
    );
  });
}
''',
)

# ---------------------------------------------------------------------------
# Team Operations: business date + exact permission gating + shared FEFO.
# ---------------------------------------------------------------------------
TEAM = "flutter-app/lib/screens/organization/team_screen.dart"
swap(
    TEAM,
    "import '../../core/api_paths.dart';\n",
    "import '../../core/api_paths.dart';\nimport '../../core/daily_order_workflow.dart';\nimport '../../core/stock_allocation.dart';\n",
)
swap(
    TEAM,
    "                    'from': _monthStart(),\n                    'to': _today(),",
    "                    'from': app.businessMonthStart,\n                    'to': app.businessDate,",
)
swap(
    TEAM,
    "      final api = ref.read(apiClientProvider);\n      final data = Map<String, dynamic>.from(\n",
    "      final api = ref.read(apiClientProvider);\n      final app = ref.read(appStateProvider);\n      final data = Map<String, dynamic>.from(\n",
)
swap(
    TEAM,
    "                          if ('${r['status']}' == 'submitted')\n",
    "                          if (DailyOrderWorkflow.canApproveRequest(\n                            '${r['status']}',\n                            app.capabilities,\n                          ))\n",
)
swap(
    TEAM,
    "                          if ('${r['status']}' == 'approved')\n",
    "                          if (DailyOrderWorkflow.canIssueRequest(\n                            '${r['status']}',\n                            app.capabilities,\n                          ))\n",
)
swap(
    TEAM,
    "  Future<void> _approve(int requestId) async {\n    final closed = await OverlayTransition.closeAndSettle(context);",
    "  Future<void> _approve(int requestId) async {\n    final app = ref.read(appStateProvider);\n    if (!app.can('daily_order.approve')) {\n      setState(() => message = 'Daily Order approval permission required hai.');\n      return;\n    }\n    final closed = await OverlayTransition.closeAndSettle(context);",
)
swap(
    TEAM,
    "  Future<void> _issue(Map<String, dynamic> request, int branchId) async {\n    try {\n      final api = ref.read(apiClientProvider);",
    "  Future<void> _issue(Map<String, dynamic> request, int branchId) async {\n    final app = ref.read(appStateProvider);\n    if (!app.can('daily_order.issue')) {\n      setState(() => message = 'Daily Order stock issue permission required hai.');\n      return;\n    }\n    try {\n      final api = ref.read(apiClientProvider);",
)
old_team_allocation = r'''      final stock =
          (await api.get(
                ApiPaths.inventoryStock,
                query: {'branch_id': branchId},
              ) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where(
                (e) =>
                    (int.tryParse('${e['custodian_key']}') ?? 0) == 0 &&
                    (double.tryParse('${e['quantity']}') ?? 0) > 0,
              )
              .toList();
      final allocations = <Map<String, dynamic>>[];
      for (final raw in (request['lines'] as List)) {
        final l = Map<String, dynamic>.from(raw as Map);
        var remaining = double.tryParse('${l['quantity']}') ?? 0;
        final pid = int.parse('${l['product_id']}');
        final candidates =
            stock
                .where((s) => int.tryParse('${s['product_id']}') == pid)
                .toList()
              ..sort(
                (x, y) => '${x['expires_on'] ?? '9999-12-31'}'.compareTo(
                  '${y['expires_on'] ?? '9999-12-31'}',
                ),
              );
        for (final s in candidates) {
          if (remaining <= .0001) break;
          final available = double.tryParse('${s['quantity']}') ?? 0;
          final take = available < remaining ? available : remaining;
          final batchKey = int.tryParse('${s['batch_key']}') ?? 0;
          allocations.add({
            'request_line_id': l['id'],
            'quantity': take,
            if (batchKey > 0) 'batch_id': batchKey,
          });
          remaining -= take;
        }
        if (remaining > .0001)
          throw Exception(
            '${l['product_name']} ka authorised branch stock insufficient hai.',
          );
      }
'''
new_team_allocation = r'''      final stock = (await api.get(
        ApiPaths.inventoryStock,
        query: {'branch_id': branchId},
      ) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final requestLines = (request['lines'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final allocations = StockAllocation.fefo(
        requestLines: requestLines,
        stock: stock,
      );
'''
swap(TEAM, old_team_allocation, new_team_allocation)
swap(
    TEAM,
    r'''  static String _today() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _monthStart() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-01';
  }
''',
    "",
)

# ---------------------------------------------------------------------------
# My Work: action state machine, shared FEFO, strict Final Post, honest GPS.
# ---------------------------------------------------------------------------
MY = "flutter-app/lib/screens/my_work/my_work_screen.dart"
swap(
    MY,
    "import '../../core/daily_order_math.dart';\n",
    "import '../../core/daily_order_math.dart';\nimport '../../core/daily_order_workflow.dart';\nimport '../../core/stock_allocation.dart';\n",
)
swap(
    MY,
    "    if (status == 'morning_draft') {\n",
    "    if (DailyOrderWorkflow.canSubmitDraft(status, app.capabilities)) {\n",
)
swap(
    MY,
    r'''    if (status == 'issued') {
      if (app.can('daily_order.self') || app.can('daily_order.others')) {
        out.add(
          const PopupMenuItem(
            value: 'additional',
            child: Text('Additional Requirement'),
          ),
        );
      }
      out.add(
        const PopupMenuItem(
          value: 'evening',
          child: Text('Start Evening Closing'),
        ),
      );
    }
''',
    r'''    if (status == 'issued' &&
        DailyOrderWorkflow.canOperateOwnOrder(app.capabilities)) {
      out.add(
        const PopupMenuItem(
          value: 'additional',
          child: Text('Additional Requirement'),
        ),
      );
      out.add(
        const PopupMenuItem(
          value: 'evening',
          child: Text('Start Evening Closing'),
        ),
      );
    }
''',
)
swap(
    MY,
    "      final api = ref.read(apiClientProvider);\n      if (action == 'view') {",
    "      final api = ref.read(apiClientProvider);\n      final app = ref.read(appStateProvider);\n      if (action == 'view') {",
)
swap(
    MY,
    r'''      } else if (action == 'evening') {
        await api.post(ApiPaths.eveningStart(id), data: const {});
        await _editEvening(id);
        return;
''',
    r'''      } else if (action == 'evening') {
        final detail = await _dailyDetail(id);
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
        await _editEvening(id);
        return;
''',
)
swap(
    MY,
    r'''    final lines = ((r['lines'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (lines.isEmpty) throw Exception('Approved request lines missing.');

    final ok = await showModalBottomSheet<bool>(
''',
    r'''    final lines = ((r['lines'] as List?) ?? const [])
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
    final allocations = StockAllocation.fefo(
      requestLines: lines,
      stock: stock,
    );

    final ok = await showModalBottomSheet<bool>(
''',
)
swap(
    MY,
    "                              'Full approved quantity will be issued',",
    "                              'Full approved quantity will be issued using FEFO batches',",
)
swap(
    MY,
    r'''    if (ok == true) {
      final allocations = <Map<String, dynamic>>[];
      for (final l in lines) {
        final lid = int.parse('${l['id']}');
        final q = num.tryParse('${l['quantity'] ?? 0}')?.toDouble() ?? 0;
        if (q <= 0) throw Exception('Approved issue quantity missing.');
        allocations.add({'request_line_id': lid, 'quantity': q});
      }
      await api.post(
''',
    r'''    if (ok == true) {
      await api.post(
''',
)
swap(
    MY,
    r'''    final reconciliationDifference = backendExpected == null
        ? 0.0
        : (backendExpected - calculatedExpected).abs();

    final cash = TextEditingController(text: expected.toStringAsFixed(2));
''',
    r'''    final reconciliationDifference = backendExpected == null
        ? 0.0
        : (backendExpected - calculatedExpected).abs();
    final reconciliationOk = backendExpected == null ||
        DailyOrderMath.reconciliationMatches(
          backendExpected,
          calculatedExpected,
        );

    final cash = TextEditingController(text: expected.toStringAsFixed(2));
''',
)
swap(
    MY,
    "            final matched = DailyOrderMath.depositMatches(deposit, expected);",
    "            final matched =\n                DailyOrderMath.paymentComponentsValid(cashValue, upiValue) &&\n                reconciliationOk &&\n                DailyOrderMath.depositMatches(deposit, expected);",
)
swap(
    MY,
    "Server total ${BusinessFormat.money(backendExpected)} · Product calculation ${BusinessFormat.money(calculatedExpected)}. Posting server expected total ke against verify hoga.",
    "Server total ${BusinessFormat.money(backendExpected)} · Product calculation ${BusinessFormat.money(calculatedExpected)}. Final Post blocked hai jab tak dono totals reconcile nahi hote.",
)
swap(
    MY,
    r'''        if (!DailyOrderMath.depositMatches(c + u, expected)) {
          throw Exception(
            'Cash + Online expected amount ke barabar hona chahiye.',
          );
        }
''',
    r'''        if (!DailyOrderMath.finalPostAllowed(
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
''',
)
swap(
    MY,
    r'''      if (checkIn) {
        try {
          await ref.read(gpsTrackingProvider).start();
        } catch (_) {
          // Attendance remains successful even if periodic tracking could not
          // start; the ERP Tools screen exposes the tracking status/retry.
        }
      } else {
        ref.read(gpsTrackingProvider).stop();
      }
      if (mounted) {
        setState(() {
          refresh++;
          message = checkIn
              ? 'Check-In successful. GPS tracking started.'
              : 'Check-Out successful. GPS tracking stopped.';
        });
      }
''',
    r'''      var gpsStarted = !checkIn;
      if (checkIn) {
        try {
          await ref.read(gpsTrackingProvider).start();
          gpsStarted = true;
        } catch (_) {
          gpsStarted = false;
          // Attendance remains successful even if periodic tracking could not
          // start; the ERP Tools screen exposes the tracking status/retry.
        }
      } else {
        ref.read(gpsTrackingProvider).stop();
      }
      if (mounted) {
        setState(() {
          refresh++;
          message = checkIn
              ? (gpsStarted
                    ? 'Check-In successful. GPS tracking started.'
                    : 'Check-In successful. GPS tracking could not start; ERP Tools se retry karein.')
              : 'Check-Out successful. GPS tracking stopped.';
        });
      }
''',
)
swap(
    MY,
    r'''  Future<void> _applyLeave() async {
    final type = TextEditingController(text: 'Casual Leave');
    final from = TextEditingController(text: _today());
    final to = TextEditingController(text: _today());
''',
    r'''  Future<void> _applyLeave() async {
    final app = ref.read(appStateProvider);
    final type = TextEditingController(text: 'Casual Leave');
    final from = TextEditingController(text: app.businessDate);
    final to = TextEditingController(text: app.businessDate);
''',
)

# ---------------------------------------------------------------------------
# Home: authoritative business date for today's order and management periods.
# ---------------------------------------------------------------------------
HOME = "flutter-app/lib/screens/home/home_screen.dart"
swap(HOME, "    final today = _today();", "    final today = app.businessDate;")
swap(
    HOME,
    "    final period = {'branch_id': branch, 'from': _monthStart(), 'to': _today()};",
    "    final period = {\n      'branch_id': branch,\n      'from': app.businessMonthStart,\n      'to': app.businessDate,\n    };",
)
swap(
    HOME,
    "        'from': _monthStart(),\n        'to': _today(),\n        'employee_id': (app.me['employee'] as Map?)?['id'],",
    "        'from': app.businessMonthStart,\n        'to': app.businessDate,\n        'employee_id': (app.me['employee'] as Map?)?['id'],",
)

# ---------------------------------------------------------------------------
# Performance/Payroll: all default periods follow ERP business date.
# ---------------------------------------------------------------------------
PERF = "flutter-app/lib/screens/performance/performance_screen.dart"
swap(
    PERF,
    "                    'from': _monthStart(),\n                    'to': _today(),",
    "                    'from': app.businessMonthStart,\n                    'to': app.businessDate,",
)
swap(
    PERF,
    "              'period_start': _monthStart(),\n              'period_end': _today(),",
    "              'period_start': app.businessMonthStart,\n              'period_end': app.businessDate,",
)
swap(
    PERF,
    "  Future<void> _payPayroll(int id) async {\n    try {",
    "  Future<void> _payPayroll(int id) async {\n    final app = ref.read(appStateProvider);\n    try {",
)
swap(PERF, "      final date = TextEditingController(text: _today());", "      final date = TextEditingController(text: app.businessDate);")
swap(
    PERF,
    "      final from = TextEditingController(text: _monthStart());\n      final to = TextEditingController(text: _today());",
    "      final from = TextEditingController(text: app.businessMonthStart);\n      final to = TextEditingController(text: app.businessDate);",
)

# ---------------------------------------------------------------------------
# Finance: branch books/expense/closing/bank/period defaults use business date.
# ---------------------------------------------------------------------------
FIN = "flutter-app/lib/screens/finance/finance_screen.dart"
swap(FIN, "              'to': _today(),", "              'to': app.businessDate,")
swap(FIN, "            'expense_date': _today(),", "            'expense_date': app.businessDate,")
swap(FIN, "              'business_date': _today(),", "              'business_date': app.businessDate,", expected=2)
swap(
    FIN,
    "      final from = TextEditingController(text: _monthStart());\n      final to = TextEditingController(text: _today());",
    "      final from = TextEditingController(text: app.businessMonthStart);\n      final to = TextEditingController(text: app.businessDate);",
)
swap(
    FIN,
    "  Future<void> _addBankLine(int id) async {\n    final date = TextEditingController(text: _today());",
    "  Future<void> _addBankLine(int id) async {\n    final app = ref.read(appStateProvider);\n    final date = TextEditingController(text: app.businessDate);",
)
swap(
    FIN,
    "  Future<void> _closePeriod() async {\n    final from = TextEditingController(text: _monthStart());\n    final to = TextEditingController(text: _today());",
    "  Future<void> _closePeriod() async {\n    final app = ref.read(appStateProvider);\n    final from = TextEditingController(text: app.businessMonthStart);\n    final to = TextEditingController(text: app.businessDate);",
)

# ---------------------------------------------------------------------------
# Organization effective dates also come from ERP business date.
# ---------------------------------------------------------------------------
ORG = "flutter-app/lib/screens/organization/organization_screen.dart"
swap(ORG, "      final joining = TextEditingController(text: _today());", "      final joining = TextEditingController(text: app.businessDate);")
swap(
    ORG,
    "    final date = TextEditingController(text: _today());",
    "    final date = TextEditingController(text: app.businessDate);",
)

# Write only after every assertion above succeeds.
for rel_path, content in changes.items():
    target = ROOT / rel_path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")

print(f"P0 logic stabilization patched {len(changes)} files")
