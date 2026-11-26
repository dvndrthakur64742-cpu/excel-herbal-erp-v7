import 'package:excel_herbal_erp/widgets/module_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('module context remains readable with narrow large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const scope = 'Long authorised branch name / 2026-11-26';
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.6)),
        child: child!,
      ),
      home: const Scaffold(body: SingleChildScrollView(
        child: ModuleWorkspaceHeader(
          title: 'Inventory',
          subtitle: 'Manage stock movements and reviews.',
          icon: Icons.inventory_2_outlined,
          contextLabel: scope,
        ),
      )),
    ));
    final text = tester.widget<Text>(find.text(scope));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('Inventory Control'), findsNothing);
    expect(find.textContaining('Branch stock, transfers'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
  });
}
