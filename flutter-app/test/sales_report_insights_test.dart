import 'package:excel_herbal_erp/core/sales_report_totals.dart';
import 'package:excel_herbal_erp/widgets/sales_report_insights.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> row(int id, String date, String gross, String paid, String outstanding) => {
  'id': id, 'business_date': date, 'reference': 'SALE-$id', 'status': 'posted',
  'gross_amount': gross, 'paid_amount': paid, 'outstanding_amount': outstanding,
};

void main() {
  final rows = [row(1,'2026-11-24','100.10','50.10','50.00'),
    row(2,'2026-11-25','200.20','200.20','0.00'),
    row(3,'2026-11-24','0.01','0.01','0.00')];
  test('exact cents and date groups use returned records only', () {
    final totals = SalesReportTotals.read(rows)!;
    expect(totals.grossMinor, 30031);
    expect(totals.paidMinor, 25031);
    expect(totals.outstandingMinor, 5000);
    expect(totals.days.map((d) => d.date), ['2026-11-25','2026-11-24']);
    expect(totals.days.last.grossMinor, 10011);
    expect(totals.days.last.rows.length, 2);
  });
  test('invalid or duplicate records never become zero totals', () {
    expect(SalesReportTotals.read([rows.first, rows.first]), isNull);
    expect(SalesReportTotals.read([row(4,'2026-02-30','1','1','0')]), isNull);
    expect(SalesReportTotals.read([row(4,'2026-11-25','bad','1','0')]), isNull);
    expect(SalesReportTotals.read([])!.grossMinor, 0);
  });
  testWidgets('daily drill-down reveals the selected report records', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      SalesReportInsights(rows: rows, scope: 'Head Office · November'))));
    await tester.tap(find.textContaining('Sales totals & daily breakdown'));
    await tester.pumpAndSettle();
    expect(find.text('Reported gross'), findsOneWidget);
    expect(find.text('Head Office · November'), findsOneWidget);
    await tester.tap(find.text('25 Nov 2026'));
    await tester.pumpAndSettle();
    expect(find.text('SALE-2'), findsOneWidget);
    expect(find.text('SALE-1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
