import 'package:excel_herbal_erp/screens/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('four dashboard metrics use balanced rows at each width', () {
    expect(managementColumns(1400, 4), 4);
    expect(managementColumns(900, 4), 2);
    expect(managementColumns(600, 4), 2);
    expect(managementColumns(320, 4), 1);
    expect(managementColumns(900, 3), 3);
    expect(managementColumns(1400, 1), 1);
    expect(managementColumns(1100, 4, textScale: 1.6), 2);
    expect(managementColumns(600, 4, textScale: 1.6), 1);
    expect(managementColumns(1400, 4, textScale: 2), 2);
  });
}
