import 'package:excel_herbal_erp/widgets/module_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('module workspace remains usable at 320px width', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const ModuleWorkspaceHeader(
                  title: 'Inventory Control',
                  subtitle:
                      'Branch stock, transfers, adjustments and quarantine control.',
                  icon: Icons.inventory_2_outlined,
                  contextLabel: 'Business date · 2026-09-09',
                ),
                ModuleActionPanel(
                  title: 'Stock Actions',
                  subtitle: 'Move stock or record a controlled adjustment.',
                  actions: [
                    FilledButton(
                        onPressed: () {}, child: const Text('Transfer')),
                    OutlinedButton(
                        onPressed: () {}, child: const Text('Adjustment')),
                    OutlinedButton(
                        onPressed: () {}, child: const Text('Quarantine')),
                  ],
                ),
                const ModuleSectionHeader(
                  title: 'Inventory Workspace',
                  subtitle: 'Review stock and controlled inventory movements.',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Inventory Control'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
  });
}
