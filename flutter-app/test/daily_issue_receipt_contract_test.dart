import 'dart:io';

import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter daily issue preview and employee receipt match V7 routes', () {
    expect(ApiPaths.dailyIssuePreflight(31),
        '/daily/requests/31/issue-preflight');
    expect(ApiPaths.dailyIssue(31), '/daily/requests/31/issue');
    expect(ApiPaths.dailyReceive(31), '/daily/requests/31/receive');
  });

  test('allocation success waits for employee physical receipt', () {
    final source = File('lib/screens/my_work/my_work_daily_order.dart')
        .readAsStringSync();
    expect(source, contains("result['status'] != 'awaiting_receipt'"));
    expect(source, isNot(contains("result['stock_moved'] != true")));
    expect(source, contains('Confirm physical stock receipt'));
    expect(source, contains('ApiPaths.dailyReceive(requestId)'));
    expect(source, contains("response['status'] != 'issued'"));
    expect(source, contains('custody is now updated'));
  });
}
