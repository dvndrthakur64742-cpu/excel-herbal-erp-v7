import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('advanced compensation workspace is UAT-only', () {
    final performance = File(
      'lib/screens/performance/performance_screen.dart',
    ).readAsStringSync();
    final config = File('lib/core/app_config.dart').readAsStringSync();

    expect(performance, contains("import '../../core/app_config.dart';"));
    expect(performance, contains('if (AppConfig.isUat &&'));
    expect(performance, contains("'Compensation'"));
    expect(config, contains("defaultValue: 'uat'"));
    expect(config, contains("static const bool isProduction = environment == 'production';"));
    expect(config, contains('static const bool isUat = !isProduction;'));
  });

  test('performance target action follows create then approve backend contract', () {
    final performance = File(
      'lib/screens/performance/performance_screen.dart',
    ).readAsStringSync();

    expect(performance, contains(".post(ApiPaths.targetApprove(id), data: const {})"));
    expect(performance, contains("title: Text('Approve Target #\$id')"));
    expect(performance, isNot(contains('ApiPaths.performanceTarget(id)')));
    expect(performance, isNot(contains('.put(')));
  });
}
