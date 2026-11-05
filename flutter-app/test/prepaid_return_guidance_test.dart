import 'dart:io';

import 'package:excel_herbal_erp/core/prepaid_return_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PrepaidReturnGuidance check(String status, {bool complete = false}) =>
      PrepaidReturnGuidance.forStatus(
        status: status,
        evidenceComplete: complete,
      );

  test('requested return directs physical inspection, not stock posting', () {
    final result = check('requested');
    expect(result.title, contains('physical inspection'));
    expect(result.explanation, contains('No stock is released'));
    expect(result.explanation, contains('no refund is paid'));
  });

  test('received return directs independent maker-checker decision', () {
    final result = check('received');
    expect(result.title, contains('independent'));
    expect(result.explanation, contains('different authorised reviewer'));
  });

  test('refund_pending with incomplete evidence names its next actor', () {
    final result = check('refund_pending');
    expect(result.title, contains('record and verify'));
    expect(result.explanation, contains('different authorised reviewer'));
    expect(result.explanation, contains('not proof'));
  });

  test('complete evidence never claims payout, stock or credit-note posting', () {
    final result = check('refund_pending', complete: true);
    expect(result.title, contains('no payout recorded'));
    expect(result.explanation, contains('cannot pay a refund'));
    expect(result.explanation, contains('credit note'));
    expect(result.explanation, contains('release stock'));
  });

  test('rejected or unknown states fail closed', () {
    final rejected = check('rejected');
    expect(rejected.title, contains('rejected'));
    expect(rejected.explanation, contains('remain unchanged'));
    final unknown = check('future_unknown_state');
    expect(unknown.title, contains('Finance'));
    expect(unknown.explanation, contains('Do not infer'));
  });

  test('real return screen uses the guidance; no payout action is exposed', () {
    final source = File(
      'lib/screens/sales/prepaid_returns_screen.dart',
    ).readAsStringSync();
    expect(source, contains('PrepaidReturnGuidance.forStatus('));
    expect(source, contains("check['evidence_complete'] == true"));
    expect(source, contains('Text(guidance.title'));
    expect(source, contains('Text(guidance.explanation'));
    expect(source, isNot(contains('refund cannot be posted')));
    expect(source, isNot(contains('ApiPaths.prepaidRefundPost(')));
    expect(source, isNot(contains('ApiPaths.prepaidCreditNotePost(')));
    expect(source, isNot(contains('ApiPaths.reversalExecute(')));
  });
}
