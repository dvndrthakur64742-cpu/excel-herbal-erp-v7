import 'package:excel_herbal_erp/core/daily_order_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('request approval and issue require exact permissions', () {
    expect(
      DailyOrderWorkflow.canApproveRequest(
        'submitted',
        ['daily_order.approve'],
      ),
      isTrue,
    );
    expect(
      DailyOrderWorkflow.canApproveRequest(
        'submitted',
        ['daily_order.others'],
      ),
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

  test('maker-checker blocks self approval when identities are known', () {
    expect(
      DailyOrderWorkflow.canApproveRequest(
        'submitted',
        ['daily_order.approve'],
        requesterId: 2,
        currentEmployeeId: 2,
      ),
      isFalse,
    );
    expect(
      DailyOrderWorkflow.canApproveRequest(
        'submitted',
        ['daily_order.approve'],
        requesterId: 6,
        currentEmployeeId: 2,
      ),
      isTrue,
    );
  });

  test('maker-checker blocks requester from issuing own stock', () {
    expect(
      DailyOrderWorkflow.canIssueRequest(
        'approved',
        ['daily_order.issue'],
        requesterId: 2,
        currentEmployeeId: 2,
      ),
      isFalse,
    );
    expect(
      DailyOrderWorkflow.canIssueRequest(
        'approved',
        ['daily_order.issue'],
        requesterId: 6,
        currentEmployeeId: 2,
      ),
      isTrue,
    );
  });

  test('maker-checker keeps older payloads compatible when identity is absent', () {
    expect(
      DailyOrderWorkflow.canApproveRequest(
        'submitted',
        ['daily_order.approve'],
        requesterId: null,
        currentEmployeeId: 2,
      ),
      isTrue,
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
