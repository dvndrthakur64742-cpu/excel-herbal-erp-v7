import 'dart:io';

import 'package:excel_herbal_erp/core/daily_order_action_target.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> order(String status, List<Map<String, dynamic>> requests,
    {int id = 41}) =>
  {'cycle': {'id': id, 'status': status}, 'requests': requests};

Map<String, dynamic> req(
  int id, String type, String status,
  {int cycle = 41, int? requester = 10}
) => {
  'id': id,
  'daily_cycle_id': cycle,
  'type': type,
  'status': status,
  if (requester != null) 'requested_by': requester,
};

Map<String, dynamic>? choose(
  Map<String, dynamic> detail,
  String action, {
  int? actor = 20,
  Iterable<String> caps = const [
    'daily_order.self', 'daily_order.others',
    'daily_order.approve', 'daily_order.issue',
  ],
}) => DailyOrderActionTarget.select(
  detail: detail, action: action,
  capabilities: caps, actorEmployeeId: actor,
);

void main() {
  test('ASM must approve ONLY submitted initial for stock_requested cycle', () {
    final data = order('stock_requested', [
      req(91, 'initial', 'submitted'),
      req(92, 'additional', 'submitted'),
    ]);
    expect(choose(data, 'approve')?['id'], 91);
    expect(choose(data, 'reject')?['id'], 91);
    expect(choose(data, 'issue'), isNull);
    expect(choose(data, 'approve', actor: 10), isNull);
    expect(choose(data, 'approve', caps: ['daily_order.others']), isNull);
  });

  test('ASM approves ONLY current submitted additional when cycle is issued', () {
    final data = order('issued', [
      req(91, 'initial', 'issued'),
      req(92, 'additional', 'cancelled'),
      req(93, 'additional', 'submitted'),
    ]);
    expect(choose(data, 'approve')?['id'], 93);
    expect(choose(data, 'reject')?['id'], 93);
    expect(choose(data, 'issue'), isNull);
    expect(choose(data, 'approve', actor: 10), isNull);
  });

  test('stock custody issue requires exact approved type and separate requester', () {
    expect(choose(order('approved', [
      req(91, 'initial', 'approved'), req(92, 'additional', 'approved'),
    ]), 'issue')?['id'], 91);
    expect(choose(order('issued', [
      req(91, 'initial', 'issued'), req(92, 'additional', 'approved'),
    ]), 'issue')?['id'], 92);
    expect(choose(order('issued', [req(92, 'additional', 'approved')]),
      'issue', caps: ['daily_order.approve']), isNull);
    expect(choose(order('issued', [req(92, 'additional', 'approved')]),
      'issue', actor: 10), isNull);
  });

  test('cancel additional cannot select old cancelled or original issue', () {
    final data = order('issued', [
      req(10, 'initial', 'issued'),
      req(11, 'additional', 'cancelled'),
      req(12, 'additional', 'approved'),
    ]);
    expect(choose(data, 'cancel_additional')?['id'], 12);
    expect(choose(data, 'cancel_additional', caps: ['daily_order.approve']),
      isNull);
    expect(choose(order('completed', [req(12, 'additional', 'approved')]),
      'cancel_additional'), isNull);
    expect(choose(order('issued', [req(11, 'additional', 'cancelled')]),
      'cancel_additional'), isNull);
  });

  test('reject unknown cycle, cross-cycle target or forged request identity', () {
    expect(choose({}, 'approve'), isNull);
    expect(choose(order('stock_requested', [
      req(1, 'initial', 'submitted', cycle: 999),
    ]), 'approve'), isNull);
    expect(choose(order('stock_requested', [
      req(1, 'initial', 'submitted', requester: null),
    ]), 'approve'), isNull);
    expect(choose(order('issued', [req(1, 'additional', 'approved')]),
      'approve'), isNull);
    expect(choose(order('issued', [req(1, 'additional', 'approved')]),
      'arbitrary'), isNull);
    expect(choose(order('stock_requested', [
      req(1, 'initial', 'submitted'),
    ]), 'approve', actor: null), isNull);
  });

  test('ambiguous repeated submitted or approved targets fail closed', () {
    expect(choose(order('issued', [
      req(11, 'additional', 'submitted'),
      req(12, 'additional', 'submitted'),
    ]), 'approve'), isNull);
    expect(choose(order('issued', [
      req(11, 'additional', 'approved'),
      req(12, 'additional', 'approved'),
    ]), 'issue'), isNull);
    expect(choose(order('issued', [
      req(11, 'additional', 'submitted'),
      req(12, 'additional', 'approved'),
    ]), 'cancel_additional'), isNull);
  });

  test('only original API remains writer; frontend refreshes detail before action', () {
    final code = File('lib/screens/my_work/my_work_daily_order.dart')
        .readAsStringSync();
    final shell = File('lib/screens/my_work/my_work_screen.dart')
        .readAsStringSync();
    expect(shell, contains("import '../../core/daily_order_action_target.dart';"));
    expect(code, contains("action: 'approve'"));
    expect(code, contains("action: 'issue'"));
    expect(code, contains('action: action,'));
    expect(code, contains('DailyOrderActionTarget.select('));
    expect(code, contains('ApiPaths.dailyApprove('));
    expect(code, contains('ApiPaths.dailyIssuePreflight('));
    expect(code, contains('ApiPaths.dailyReject('));
    expect(code, contains('ApiPaths.dailyCancelAdditional('));
    expect(code, contains('_dailyDetail(id)'));
    expect(code, isNot(contains("_requestWithStatus(d, 'submitted')")));
    expect(code, isNot(contains("_requestWithStatus(d, 'approved')")));
  });
}
