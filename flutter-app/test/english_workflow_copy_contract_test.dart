import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // The ERP is used by nontechnical staff. Important actionable messages
  // must be clear English and may not regress to mixed-language/debug copy.
  const expectedCopy = <String, List<String>>{
    'lib/screens/my_work/my_work_daily_order.dart': [
      'Select an authorised branch.',
      'Enter a quantity for at least one product.',
      'No matching product found.',
      'Issue remains disabled until the shortage is resolved.',
    ],
    'lib/screens/my_work/my_work_daily_closing.dart': [
      'Return plus Wholesale quantity cannot exceed issued stock.',
      'Wholesale rate must be above zero',
      'the wholesale discount is split equally',
      'Final Post stays blocked until both totals reconcile.',
    ],
    'lib/screens/finance/finance_bank.dart': [
      'No bank reconciliation records yet.',
      'Enter valid numbers for Opening and Closing Balance.',
      'Import statement lines to continue.',
    ],
    'lib/screens/finance/finance_expenses.dart': [
      'Enter a valid expense amount.',
      'Expense submitted for approval.',
    ],
    'lib/screens/finance/finance_closing.dart': [
      'No branch closing records yet.',
    ],
    'lib/screens/finance/finance_periods.dart': [
      'Your role is not authorised to manage accounting periods.',
    ],
    'lib/screens/common/entity_workspace_screen.dart': [
      'Customer records matched to the Accounts Receivable report.',
      'Commercial revisions preserve previous values',
      'Workspace data could not be loaded.',
    ],
    'lib/screens/home/enterprise_hub_screen.dart': [
      'Enter at least 2 characters to search.',
    ],
    'lib/screens/my_work/my_work_attendance.dart': [
      'No GPS route points have been recorded today.',
    ],
  };

  for (final entry in expectedCopy.entries) {
    test('Staff-facing guidance remains plain English: ${entry.key}', () {
      final source = File(entry.key).readAsStringSync();
      for (final phrase in entry.value) {
        expect(source, contains(phrase));
      }
    });
  }
}
