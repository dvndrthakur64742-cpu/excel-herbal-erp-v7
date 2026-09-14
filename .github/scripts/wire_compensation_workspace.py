from pathlib import Path

screen = Path('flutter-app/lib/screens/performance/performance_screen.dart')
test_file = Path('flutter-app/test/compensation_workspace_visibility_test.dart')
text = screen.read_text(encoding='utf-8')

import_line = "import 'compensation_workspace.dart';\n"
import_anchor = "import '../../widgets/records_list.dart';\n"
if import_line not in text:
    if text.count(import_anchor) != 1:
        raise SystemExit('performance_screen import anchor drifted')
    text = text.replace(import_anchor, import_anchor + "\n" + import_line, 1)

marker = "    if (app.canAny(const [\n      'payroll.generate',\n      'payroll.approve',\n      'payroll.pay',\n    ])) {\n"
compensation_block = """    if (app.canAny(const [
      'salary.view',
      'salary.manage',
      'salary.approve',
      'rewards.view',
      'rewards.manage',
      'rewards.approve',
      'rewards.pay',
      'promotion.view',
      'promotion.request',
      'promotion.approve',
    ])) {
      tabs.add((
        'Compensation',
        const CompensationWorkspace(),
      ));
    }
"""
if "const CompensationWorkspace()" not in text:
    if text.count(marker) != 1:
        raise SystemExit('performance_screen payroll marker drifted')
    text = text.replace(marker, compensation_block + marker, 1)

screen.write_text(text, encoding='utf-8')

test_file.write_text("""import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('performance screen exposes compensation workspace behind exact capabilities', () {
    final source = File('lib/screens/performance/performance_screen.dart')
        .readAsStringSync();

    expect(source, contains("import 'compensation_workspace.dart';"));
    expect(source, contains("'Compensation'"));
    expect(source, contains('const CompensationWorkspace()'));

    for (final capability in const [
      'salary.view',
      'salary.manage',
      'salary.approve',
      'rewards.view',
      'rewards.manage',
      'rewards.approve',
      'rewards.pay',
      'promotion.view',
      'promotion.request',
      'promotion.approve',
    ]) {
      expect(source, contains("'$capability'"), reason: capability);
    }
  });
}
""", encoding='utf-8')

print('Compensation workspace wiring applied.')
