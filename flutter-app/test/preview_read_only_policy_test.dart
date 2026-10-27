import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/preview_read_only_policy.dart';

void main() {
  test('owner preview blocks every business mutation and unsafe uploads', () {
    const endpoints = [
      '/sales/counter', '/daily/cycles/41/final-post', '/workforce/attendance/check-in',
      '/workforce/gps/points', '/inventory/transfers/2/dispatch',
      '/finance/reversals/4/execute', '/payroll/runs/3/pay',
      '/reports/reminder-drafts/8/dismiss', '/organization/employees/9',
      '/sales/counter?confirm=1', 'https://office.excelherbal.in/auth/login'
    ];
    for (final path in endpoints) {
      expect(PreviewReadOnlyPolicy.permits('POST', path, preview: true), isFalse,
          reason: path);
      expect(PreviewReadOnlyPolicy.permits('PUT', path, preview: true), isFalse);
      expect(PreviewReadOnlyPolicy.permits('DELETE', path, preview: true), isFalse);
    }
  });
  test('preview preserves GET and exact authentication lifecycle only', () {
    expect(PreviewReadOnlyPolicy.permits('GET','/reports/stock',preview:true),isTrue);
    expect(PreviewReadOnlyPolicy.permits('POST','/auth/login',preview:true),isTrue);
    expect(PreviewReadOnlyPolicy.permits('POST','/auth/refresh',preview:true),isTrue);
    expect(PreviewReadOnlyPolicy.permits('POST','/auth/logout',preview:true),isTrue);
    expect(PreviewReadOnlyPolicy.permits('POST','/auth/logout-all',preview:true),isFalse);
    expect(PreviewReadOnlyPolicy.permits('POST','/auth/login?role=admin',preview:true),isFalse);
    expect(PreviewReadOnlyPolicy.permits('POST','/auth/login#frag',preview:true),isFalse);
    expect(PreviewReadOnlyPolicy.permits('PATCH','/auth/login',preview:true),isFalse);
    expect(PreviewReadOnlyPolicy.permits('POST','/sales/counter',preview:false),isTrue);
  });
}
