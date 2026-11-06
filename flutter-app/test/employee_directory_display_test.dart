import 'package:excel_herbal_erp/core/business_format.dart';
import 'package:excel_herbal_erp/widgets/records_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('designation codes stay exact but full names use company catalog', () {
    expect(BusinessFormat.label('designation_name'), 'Designation');
    expect(BusinessFormat.label('designation_code'), 'Designation Code');
    expect(BusinessFormat.value('designation_code', 'FE'), 'FE');
    expect(BusinessFormat.value('designation_code', 'BRANCH_MANAGER'),
        'Branch Manager');
    expect(BusinessFormat.value('designation_name', 'FIELD EXECUTIVE'),
        'FIELD EXECUTIVE');
  });

  const employee = <String, dynamic>{
    'id': 17,
    'full_name': 'Ankita Sharma',
    'employee_code': 'EH-017',
    'designation_code': 'FE',
    'designation_name': 'Field Executive',
    'mobile': '9000000017',
    'status': 'active',
  };

  testWidgets('desktop employee directory shows name before code',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1220, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: RecordsList(
        rows: [employee],
        recordType: 'employee',
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Designation'), findsOneWidget);
    expect(find.text('Ankita Sharma'), findsOneWidget);
    expect(find.text('Field Executive'), findsOneWidget);
    expect(find.text('EH-017'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('employee mobile card highlights designation instead of ID',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: RecordsList(
        rows: [employee],
        recordType: 'employee',
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ankita Sharma'), findsOneWidget);
    expect(find.textContaining('Designation: Field Executive'), findsOneWidget);
    expect(find.textContaining('Employee Code: EH-017'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy row without a display name still shows the code',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: RecordsList(
        rows: [{
          'id': 2, 'full_name': 'Kajal',
          'employee_code': 'EH-002', 'designation_code': 'ASM',
          'status': 'active',
        }],
        recordType: 'employee',
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Kajal'), findsOneWidget);
    expect(find.textContaining('Designation Code: ASM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
