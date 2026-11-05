import 'dart:io';

import 'package:excel_herbal_erp/core/navigation_authority.dart';
import 'package:excel_herbal_erp/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppState projected({
  required List<String> capabilities,
  required List<String> sections,
  required List<String> bottom,
  List<int> branches = const [1],
}) => AppState(
      authenticated: true,
      loading: false,
      currentBranchId: branches.isEmpty ? null : branches.first,
      bootstrap: {
        'me': {
          'employee': {
            'id': 101,
            'full_name': 'Synthetic Role',
            'designation_code': 'STAFF',
          },
          'branch_ids': branches,
          'capabilities': capabilities,
        },
        'branches': [
          for (final id in branches) {'id': id, 'name': 'Test $id'}
        ],
        'navigation': {
          'sections': [
            for (final id in sections) {'id': id, 'label': id}
          ],
          'bottom_nav': [
            for (final id in bottom) {'id': id, 'label': id}
          ],
        },
      },
    );

void main() {
  test('revoked capability hides stale server-projected modules and tabs', () {
    final state = projected(
      capabilities: ['erp.access', 'reports.view'],
      sections: ['home', 'team', 'sales', 'reports', 'finance',
        'administration', 'unknown_module', 'reports'],
      bottom: ['home', 'my_work', 'actions', 'tasks', 'profile',
        'profile', 'unrecognised_route'],
    );
    expect(state.sections.map((s) => s['id']), ['home', 'reports']);
    expect(state.sectionVisible('team'), isFalse);
    expect(state.sectionVisible('sales'), isFalse);
    expect(state.managementDashboardVisible, isFalse);
    expect(state.bottomNav.map((s) => s['id']), ['home', 'profile']);
  });

  test('staff sees only projected self-service options without duplicate tabs',
      () {
    final state = projected(
      capabilities: [
        'erp.access', 'daily_order.self', 'communication.view',
      ],
      sections: ['home', 'my_work', 'team', 'communication',
        'sales', 'my_work'],
      bottom: ['home', 'my_work', 'actions', 'tasks', 'profile',
        'tasks', 'erp_tools'],
    );
    expect(state.sections.map((s) => s['id']),
        ['home', 'my_work', 'communication']);
    // ERP Tools is the legacy authorised self-service entry; it must not
    // disappear merely because the app has a new canonical Communications UI.
    expect(state.bottomNav.map((s) => s['id']),
        ['home', 'my_work', 'actions', 'tasks', 'profile']);
    expect(state.sectionVisible('administration'), isFalse);
    expect(state.sectionVisible('finance'), isFalse);
  });

  test('role title does not grant an unprojected action, and branch fail closes',
      () {
    final manager = projected(
      capabilities: [
        'erp.access', 'daily_order.approve', 'finance.expense.approve',
      ],
      sections: ['home', 'team', 'finance', 'administration'],
      bottom: ['home', 'my_work', 'actions', 'profile'],
    );
    expect(manager.sections.map((s) => s['id']),
        ['home', 'team', 'finance']);
    expect(manager.bottomNav.map((s) => s['id']), ['home', 'profile']);

    final blocked = projected(
      capabilities: [
        'erp.access', 'administration.access.manage', 'finance.view',
      ],
      sections: ['home', 'finance', 'administration'],
      bottom: ['home', 'actions', 'profile'],
      branches: [],
    );
    expect(blocked.sections.map((s) => s['id']), ['home']);
    expect(blocked.bottomNav.map((s) => s['id']), ['home', 'profile']);
  });

  test('client section rules stay in sync with PHP navigation capabilities',
      () {
    final php = File(
      '../plugin/excel-herbal-erp-v7/src/App/NavigationProjection.php',
    ).readAsStringSync();
    final constants = File(
      '../plugin/excel-herbal-erp-v7/src/Security/Capabilities.php',
    ).readAsStringSync();
    final values = <String, String>{
      for (final m in RegExp(r"([A-Z_]+)='([^']+)'").allMatches(constants))
        m.group(1)!: m.group(2)!,
    };
    final candidates = {...values.values, '__invalid_capability__'};
    final projectedSections = RegExp(
      r"\['id'=>'([a-z_]+)','label'=>'[^']+','visible'=>\$can\(\[([^\]]+)\]\)\]",
    ).allMatches(php).toList();
    expect(projectedSections, hasLength(11),
        reason: 'New server sections must be explicitly reviewed in the client.');
    for (final entry in projectedSections) {
      final id = entry.group(1)!;
      final allowed = {
        for (final match
            in RegExp(r'Capabilities::([A-Z_]+)').allMatches(entry.group(2)!))
          values[match.group(1)]!,
      };
      expect(allowed, isNotEmpty, reason: id);
      for (final candidate in candidates) {
        expect(NavigationAuthority.sectionAllowed(
          id, (cap) => cap == candidate,
        ), allowed.contains(candidate),
            reason: '$id capability parity: $candidate');
      }
    }
    expect(NavigationAuthority.sectionAllowed('home', (_) => false), isTrue);
    expect(NavigationAuthority.sectionAllowed('unknown', (_) => true), isFalse);
  });

  test('client bottom actions and tasks match PHP projection', () {
    final php = File(
      '../plugin/excel-herbal-erp-v7/src/App/NavigationProjection.php',
    ).readAsStringSync();
    final values = <String, String>{
      for (final m in RegExp(r"([A-Z_]+)='([^']+)'").allMatches(
          File('../plugin/excel-herbal-erp-v7/src/Security/Capabilities.php')
              .readAsStringSync()))
        m.group(1)!: m.group(2)!,
    };
    final projectedBottom = RegExp(
      r"if\(\$can\(\[([^\]]+)\]\)\)\$bottom\[\]=\['id'=>'([a-z_]+)','label'=>'[^']+'\];",
    ).allMatches(php).toList();
    expect(projectedBottom, hasLength(3));
    for (final entry in projectedBottom) {
      final id = entry.group(2)!;
      final serverAllowed = {
        for (final cap
            in RegExp(r'Capabilities::([A-Z_]+)').allMatches(entry.group(1)!))
          values[cap.group(1)]!,
      };
      for (final candidate in {...values.values, '__no_cap__'}) {
        expect(
          NavigationAuthority.bottomAllowed(
            id, (cap) => cap == candidate, erpToolsVisible: false,
          ),
          serverAllowed.contains(candidate),
          reason: '$id bottom-nav parity: $candidate',
        );
      }
    }
    expect(NavigationAuthority.bottomAllowed(
      'profile', (_) => false, erpToolsVisible: false,
    ), isTrue);
    expect(NavigationAuthority.bottomAllowed(
      'unknown', (_) => true, erpToolsVisible: true,
    ), isFalse);
  });

  testWidgets('320px mobile navigation stays usable with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 690);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final state = projected(
      capabilities: [
        'erp.access', 'daily_order.self', 'communication.view',
      ],
      sections: ['home', 'my_work', 'communication'],
      bottom: ['home', 'my_work', 'actions', 'tasks', 'profile',
        'tasks', 'unexpected'],
    );
    final items = state.bottomNav;
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: StatefulBuilder(builder: (context, update) => Scaffold(
          body: const Center(child: Text('Permitted workspace')),
          bottomNavigationBar: NavigationBar(
            selectedIndex: selected,
            onDestinationSelected: (index) => update(() => selected = index),
            destinations: [
              for (final item in items)
                NavigationDestination(
                  icon: const Icon(Icons.circle_outlined),
                  label: '${item['label']}',
                ),
            ],
          ),
        )),
      ),
    ));
    await tester.pumpAndSettle();
    expect(items, hasLength(5));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('profile'));
    await tester.pumpAndSettle();
    expect(selected, 4);
    expect(tester.takeException(), isNull);
  });
}
