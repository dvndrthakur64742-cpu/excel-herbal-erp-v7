import 'dart:convert';
import 'package:excel_herbal_erp/core/report_print_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wide reports retain all columns in ordered groups', () {
    final groups = ReportPrintDocument.columnGroups(16);
    expect(groups.map((g) => g.length), [7, 7, 2]);
    expect(groups.expand((g) => g), List.generate(16, (i) => i));
  });

  test('print policy rejects missing data and unsupported characters without truncation', () {
    String? check(List<List<String>> rows) => ReportPrintDocument.limitation(
      title: 'Report', scope: 'Branch', columns: ['Name'], rows: rows);
    expect(check([]), isNotNull);
    expect(check([['A', 'B']]), isNotNull);
    expect(check(List.generate(1001, (_) => ['A'])), isNotNull);
    expect(check([[List.filled(181, 'x').join()]]), isNotNull);
    expect(check([['नाम']]), isNotNull);
    expect(check([['₹12.50 — paid']]), isNull);
  });

  test('PDF generation produces a document from saved records', () async {
    final pdf = await ReportPrintDocument.build(
      title: 'Saved order statement', scope: 'Test branch',
      columns: ['Product', 'Quantity', 'Amount (INR)'],
      rows: [['101', '2', '15.00'], ['102', '1', '20.00']],
      note: 'Not a tax invoice or payment receipt.',
    );
    expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
    expect(pdf.length, greaterThan(500));
  });
}
