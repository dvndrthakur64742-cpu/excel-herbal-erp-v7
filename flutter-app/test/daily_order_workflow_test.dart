import 'package:excel_herbal_erp/core/daily_order_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stock issue preflight requires every requested line', () {
    final lines = <Map<String, dynamic>>[
      {'id': 11, 'quantity': 3},
      {'id': 12, 'quantity': 2},
    ];
    final available = <String, dynamic>{
      'all_available': true,
      'lines': [
        {'request_line_id': 11, 'issueable': true},
        {'request_line_id': 12, 'issueable': true},
      ],
    };
    expect(DailyOrderWorkflow.stockIssueReady(available, lines), isTrue);
    expect(
      DailyOrderWorkflow.stockIssueReady({
        'all_available': true,
        'lines': [
          {'request_line_id': 11, 'issueable': true},
        ],
      }, lines),
      isFalse,
    );
    expect(
      DailyOrderWorkflow.stockIssueReady({
        ...available,
        'all_available': false,
      }, lines),
      isFalse,
    );
  });

  test('stock issue preflight rejects shortage and duplicate line IDs', () {
    final lines = <Map<String, dynamic>>[
      {'id': 11, 'quantity': 3},
    ];
    expect(
      DailyOrderWorkflow.stockIssueReady({
        'all_available': true,
        'lines': [
          {'request_line_id': 11, 'issueable': false},
        ],
      }, lines),
      isFalse,
    );
    expect(
      DailyOrderWorkflow.stockIssueReady({
        'all_available': true,
        'lines': [
          {'request_line_id': 11, 'issueable': true},
          {'request_line_id': 11, 'issueable': true},
        ],
      }, lines),
      isFalse,
    );
    expect(
      DailyOrderWorkflow.stockIssueReady({
        'all_available': true,
        'lines': [],
      }, <Map<String, dynamic>>[]),
      isFalse,
    );
  });

  test('cycle statuses use one clear shared display label', () {
    expect(DailyOrderWorkflow.statusLabel('issued'), 'Issued · Evening Pending');
    expect(DailyOrderWorkflow.statusLabel('stock_requested'), 'Approval Pending');
    expect(DailyOrderWorkflow.statusLabel('evening_submitted'), 'Final Post Pending');
    expect(DailyOrderWorkflow.statusLabel('rejected'), 'Rejected');
    expect(DailyOrderWorkflow.statusLabel('future_status'), 'future_status');
  });

  test('additional request does not erase issued cycle stage', () {
    expect(
      DailyOrderWorkflow.orderStatusLabel({
        'status': 'issued',
        'additional_request_status': 'submitted',
      }),
      'Issued · Additional Approval Pending',
    );
    expect(
      DailyOrderWorkflow.orderStatusLabel({
        'status': 'issued',
        'additional_request_status': 'approved',
      }),
      'Issued · Additional Issue Pending',
    );
    expect(
      DailyOrderWorkflow.orderStatusLabel({
        'status': 'completed',
        'additional_request_status': 'submitted',
      }),
      'Completed',
    );
    expect(
      DailyOrderWorkflow.orderStatusLabel({'status': 'issued'}),
      'Issued · Evening Pending',
    );
  });

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
