import 'package:excel_herbal_erp/shell/shell_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile drawer never exceeds the viewport, even in split-screen', () {
    for (final width in <double>[200, 240, 280, 320, 360, 390, 430, 959]) {
      final drawerWidth = ShellLayout.mobileDrawerWidth(width);
      expect(drawerWidth, lessThanOrEqualTo(width));
      expect(drawerWidth, lessThanOrEqualTo(390));
      expect(drawerWidth, greaterThan(0));
    }
    expect(ShellLayout.mobileDrawerWidth(320), 288);
    expect(ShellLayout.mobileDrawerWidth(500), 390);
  });

  test('role-projected tabs preserve the selected ID after reordering', () {
    final initial = <Map<String, dynamic>>[
      {'id': 'home'},
      {'id': 'my_work'},
      {'id': 'actions'},
      {'id': 'profile'},
    ];
    final reordered = <Map<String, dynamic>>[
      {'id': 'home'},
      {'id': 'actions'},
      {'id': 'profile'},
      {'id': 'my_work'},
    ];
    expect(ShellLayout.mobileNavIndex(initial, 'my_work'), 1);
    expect(ShellLayout.mobileNavIndex(reordered, 'my_work'), 3);
  });

  test('revoked tabs fall back to Home, never a different role feature', () {
    final fewerTabs = <Map<String, dynamic>>[
      {'id': 'profile'},
      {'id': 'home'},
      {'id': 'tasks'},
    ];
    expect(ShellLayout.mobileNavIndex(fewerTabs, 'approvals'), 1);
    expect(ShellLayout.mobileNavIndex(fewerTabs, 'home'), 1);
    expect(ShellLayout.mobileNavIndex(<Map<String, dynamic>>[
      {'id': 'profile'},
      {'id': 'tasks'},
    ], 'inventory'), 0);
    expect(ShellLayout.mobileNavIndex([], 'sales'), 0);
  });
}
