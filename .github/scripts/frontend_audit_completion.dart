import 'dart:io';

String readNormalized(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

void replaceOrVerify(String path, String oldText, String newText) {
  final file = File(path);
  var text = readNormalized(path);
  if (text.contains(newText)) return;
  if (!text.contains(oldText)) {
    throw StateError('$path: expected old or new frontend-audit marker not found');
  }
  text = text.replaceFirst(oldText, newText);
  file.writeAsStringSync(text);
}

void main() {
  const shell = 'flutter-app/lib/shell/app_shell.dart';
  replaceOrVerify(
    shell,
    "import '../core/overlay_transition.dart';\n",
    "import '../core/business_format.dart';\nimport '../core/overlay_transition.dart';\n",
  );
  replaceOrVerify(
    shell,
    """        'approvals' => const EnterpriseHubScreen(initialTab: 0),
        'global_search' => const EnterpriseHubScreen(initialTab: 1),""",
    """        'approvals' => const EnterpriseHubScreen(
            key: ValueKey('mobile-enterprise-approvals'),
            initialTab: 0,
          ),
        'global_search' => const EnterpriseHubScreen(
            key: ValueKey('mobile-enterprise-global-search'),
            initialTab: 1,
          ),""",
  );
  replaceOrVerify(
    shell,
    """                      Text(
                        '\${employee['employee_code'] ?? ''} · \${employee['designation_code'] ?? ''}',""",
    """                      Text(
                        '\${employee['employee_code'] ?? ''} · \${BusinessFormat.value('designation_code', employee['designation_code'])}',""",
  );
  replaceOrVerify(
    shell,
    """    final designation =
        '\${employee['designation_name'] ?? employee['designation_code'] ?? ''}'
            .trim();""",
    """    final designationName = '\${employee['designation_name'] ?? ''}'.trim();
    final designation = designationName.isNotEmpty
        ? BusinessFormat.displayName(designationName)
        : BusinessFormat.value('designation_code', employee['designation_code']);""",
  );

  const work = 'flutter-app/lib/screens/my_work/my_work_screen.dart';
  replaceOrVerify(
    work,
    "'Aaj Evening Closing ke liye koi issued order available nahi hai.'",
    "'No issued Daily Order is available for Evening Closing today.'",
  );
  replaceOrVerify(
    work,
    "emptyMessage: 'Daily Order nahi mila.'",
    "emptyMessage: 'No Daily Orders for the selected scope.'",
  );
  replaceOrVerify(
    work,
    "emptyMessage: 'Abhi koi leave request nahi hai.'",
    "emptyMessage: 'No leave requests yet.'",
  );
  replaceOrVerify(
    work,
    "emptyMessage: 'Koi active field visit nahi hai.'",
    "emptyMessage: 'No active field visit.'",
  );

  const inventory = 'flutter-app/lib/screens/inventory/inventory_screen.dart';
  replaceOrVerify(
    inventory,
    "emptyMessage: 'Koi stock adjustment nahi hai.'",
    "emptyMessage: 'No stock adjustments for the selected branch.'",
  );
  replaceOrVerify(
    inventory,
    "emptyMessage: 'Quarantine empty hai.'",
    "emptyMessage: 'No quarantined stock for the selected branch.'",
  );
  replaceOrVerify(
    inventory,
    "throw Exception('Selected branch me transfer ke liye stock nahi hai.');",
    "throw Exception('Selected branch has no stock available for transfer.');",
  );

  const navigationTest = 'flutter-app/test/frontend_functional_navigation_test.dart';
  replaceOrVerify(
    navigationTest,
    """    expect(source, contains(\"ValueKey('desktop-enterprise-global-search')\"));
    expect(source, contains('openConnectedAction: _openConnectedAction'));""",
    """    expect(source, contains(\"ValueKey('desktop-enterprise-global-search')\"));
    expect(source, contains(\"ValueKey('mobile-enterprise-approvals')\"));
    expect(source, contains(\"ValueKey('mobile-enterprise-global-search')\"));
    expect(source, contains('openConnectedAction: _openConnectedAction'));""",
  );

  final polishTest = File('flutter-app/test/frontend_audit_polish_test.dart');
  polishTest.writeAsStringSync(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('frontend audit polish keeps navigation and empty states explicit', () {
    final shell = File('lib/shell/app_shell.dart').readAsStringSync();
    final work = File('lib/screens/my_work/my_work_screen.dart').readAsStringSync();
    final inventory = File('lib/screens/inventory/inventory_screen.dart').readAsStringSync();

    expect(shell, contains("ValueKey('mobile-enterprise-approvals')"));
    expect(shell, contains("ValueKey('mobile-enterprise-global-search')"));
    expect(shell, contains("BusinessFormat.value('designation_code'"));

    expect(work, contains('No Daily Orders for the selected scope.'));
    expect(work, contains('No leave requests yet.'));
    expect(work, contains('No active field visit.'));
    expect(work, isNot(contains('Daily Order nahi mila.')));

    expect(inventory, contains('No stock adjustments for the selected branch.'));
    expect(inventory, contains('No quarantined stock for the selected branch.'));
  });
}
''');
}
