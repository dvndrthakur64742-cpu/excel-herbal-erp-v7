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
    expect(config, contains("defaultValue: 'production'"));
    expect(config, contains("static const bool isUat = environment != 'production';"));
  });
}
