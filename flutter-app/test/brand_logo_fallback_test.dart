import 'package:excel_herbal_erp/widgets/brand_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a missing brand asset produces visible text rather than whitespace',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: BrandLogo(
              width: 188,
              height: 72,
              assetPath: 'assets/branding/nonexistent-logo.webp',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Excel Herbal'), findsOneWidget);
    expect(find.byIcon(Icons.spa_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact sidebar branding has a readable icon fallback',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: BrandLogo(
              width: 56,
              height: 56,
              assetPath: 'assets/branding/nonexistent-logo.webp',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.spa_outlined), findsOneWidget);
    expect(tester.getSize(find.byType(BrandLogo)), const Size(56, 56));
    expect(tester.takeException(), isNull);
  });
}
