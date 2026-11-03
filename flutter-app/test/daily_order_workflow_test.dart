import 'package:excel_herbal_erp/core/daily_order_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('request approval and issue require exact permissions', () {
    expect(
      DailyOrderWorkflow.canApproveRequest(
        'reviewed',
        ['daily_order.approve'],
      ),
      isTrue,
    );
    expect(
      DailyOrderWorkflow.canApproveRequest(
        'reviewed',
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

  test('review requires independent SM/ASM before BM/HO approval', () {
    expect(
      DailyOrderWorkflow.canReviewRequest(
        'submitted',
        ['daily_order.others'],
        designationCode: 'SM',
        requesterId: 11,
        beneficiaryEmployeeId: 11,
        currentEmployeeId: 22,
      ),
      isTrue,
    );
    expect(
      DailyOrderWorkflow.canReviewRequest(
        'submitted',
        ['daily_order.others'],
        designationCode: 'BM',
        requesterId: 11,
        beneficiaryEmployeeId: 11,
        currentEmployeeId: 22,
      ),
      isFalse,
    );
    expect(
      DailyOrderWorkflow.canReviewRequest(
        'submitted',
        ['daily_order.others'],
        designationCode: 'SM',
        requesterId: 11,
        beneficiaryEmployeeId: 11,
        currentEmployeeId: 11,
      ),
      isFalse,
    );
    expect(
      DailyOrderWorkflow.canApproveRequest(
        'submitted',
        ['daily_order.approve'],
        requesterId: 11,
        currentEmployeeId: 22,
      ),
      isFalse,
    );
    expect(
      DailyOrderWorkflow.canApproveRequest(
        'reviewed',
        ['daily_order.approve'],
        requesterId: 11,
        currentEmployeeId: 22,
      ),
      isTrue,
    );
  });

  test('maker-checker blocks self approval when identities are known', () {
    expect(
      DailyOrderWorkflow.canApproveRequest(
        'reviewed',
        ['daily_order.approve'],
        requesterId: 2,
        currentEmployeeId: 2,
      ),
      isFalse,
    );
    expect(
      DailyOrderWorkflow.canApproveRequest(
        'reviewed',
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
        'reviewed',
        ['daily_order.approve'],
        requesterId: null,
        currentEmployeeId: 2,
      ),
      isTrue,
    );
  });

  test('physical receipt is beneficiary-only after allocation', () {
    expect(
      DailyOrderWorkflow.canReceiveRequest(
        'awaiting_receipt',
        ['daily_order.self'],
        beneficiaryEmployeeId: 7,
        currentEmployeeId: 7,
      ),
      isTrue,
    );
    expect(
      DailyOrderWorkflow.canReceiveRequest(
        'awaiting_receipt',
        ['daily_order.self'],
        beneficiaryEmployeeId: 7,
        currentEmployeeId: 8,
      ),
      isFalse,
    );
    expect(
      DailyOrderWorkflow.canReceiveRequest(
        'awaiting_receipt',
        ['daily_order.issue'],
        beneficiaryEmployeeId: 7,
        currentEmployeeId: 7,
      ),
      isFalse,
    );
    expect(
      DailyOrderWorkflow.canReceiveRequest(
        'approved',
        ['daily_order.self'],
        beneficiaryEmployeeId: 7,
        currentEmployeeId: 7,
      ),
      isFalse,
    );
    expect(
      DailyOrderWorkflow.canReceiveRequest(
        'awaiting_receipt',
        ['daily_order.self'],
        beneficiaryEmployeeId: null,
        currentEmployeeId: 7,
      ),
      isFalse,
    );
  });

  test('evening remains blocked while additional receipt is pending', () {
    final pending = <Map<String, dynamic>>[
      {'type': 'additional', 'status': 'awaiting_receipt'},
    ];
    expect(DailyOrderWorkflow.hasBlockingAdditionalRequests(pending), isTrue);
    expect(
      DailyOrderWorkflow.eveningBlockReason(
        cycleStatus: 'issued',
        requests: pending,
        capabilities: ['daily_order.self'],
      ),
      isNotNull,
    );
  });

  test('issued, rejected or withdrawn additional request no longer blocks summary', () {
    expect(DailyOrderWorkflow.additionalQueueSettled(''), isTrue);
    expect(DailyOrderWorkflow.additionalQueueSettled('issued'), isTrue);
    expect(DailyOrderWorkflow.additionalQueueSettled('cancelled'), isTrue);
    expect(DailyOrderWorkflow.additionalQueueSettled('rejected'), isTrue);
    for (final pending in ['draft', 'submitted', 'reviewed', 'approved', 'awaiting_receipt']) {
      expect(DailyOrderWorkflow.additionalQueueSettled(pending), isFalse);
    }
    final finished = <Map<String, dynamic>>[
      {'type': 'initial', 'status': 'issued'},
      {'type': 'additional', 'status': 'cancelled'},
    ];
    expect(DailyOrderWorkflow.hasBlockingAdditionalRequests(finished), isFalse);
    expect(
      DailyOrderWorkflow.eveningBlockReason(
        cycleStatus: 'issued',
        requests: finished,
        capabilities: ['daily_order.self'],
      ),
      isNull,
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
