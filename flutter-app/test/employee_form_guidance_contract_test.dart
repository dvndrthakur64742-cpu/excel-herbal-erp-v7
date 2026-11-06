import 'dart:io';

import 'package:excel_herbal_erp/core/transaction_guardrails.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new employee form marks exactly the backend-required inputs', () {
    final source = File('lib/screens/organization/organization_employees.dart')
        .readAsStringSync();
    final createStart = source.indexOf('Future<void> _createEmployee() async');
    final actionsStart = source.indexOf('void _employeeActions(');
    expect(createStart, greaterThanOrEqualTo(0));
    expect(actionsStart, greaterThan(createStart));
    final createForm = source.substring(createStart, actionsStart);

    for (final requiredLabel in [
      'Employee Code *',
      'Full Name *',
      'Designation *',
      'Joining Date *',
    ]) {
      expect(createForm, contains(requiredLabel));
    }
    expect(createForm, contains("prefixText: '₹ '"));
    expect(createForm, contains('Mobile and Email are optional'));
    expect(createForm, contains('Login credentials are issued separately'));
  });

  test('mandatory inputs cannot bypass existing validation', () {
    String? validate({
      String code = 'EH-001',
      String name = 'Synthetic Employee',
      String? role = 'FE',
      String joining = '2026-11-06',
    }) => TransactionGuardrails.employeeCreate(
          employeeCode: code,
          fullName: name,
          designationCode: role,
          mobile: '',
          email: '',
          joiningDate: joining,
        );

    expect(validate(code: ''), 'Employee Code is required.');
    expect(validate(name: ''), 'Full Name is required.');
    expect(validate(role: null), 'Designation is required.');
    expect(validate(joining: ''), isNotNull);
    expect(validate(), isNull);
  });

  test('salary input remains optional to manager role and cannot be negative', () {
    expect(
      TransactionGuardrails.nonNegativeMoneyText('0', label: 'Monthly Salary'),
      isNull,
    );
    expect(
      TransactionGuardrails.nonNegativeMoneyText('-1', label: 'Monthly Salary'),
      contains('non-negative'),
    );
    expect(
      TransactionGuardrails.nonNegativeMoneyText('abc', label: 'Monthly Salary'),
      isNotNull,
    );
  });
}
