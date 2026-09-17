import 'package:excel_herbal_erp/theme/excel_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ERP theme keeps tabs and business tables visually consistent', () {
    final theme = ExcelBrand.lightTheme();

    expect(theme.tabBarTheme.indicatorColor, ExcelBrand.primary);
    expect(theme.tabBarTheme.indicatorSize, TabBarIndicatorSize.tab);
    expect(
      theme.dataTableTheme.headingRowColor?.resolve(<WidgetState>{}),
      ExcelBrand.primarySoft,
    );
    expect(theme.dataTableTheme.dividerThickness, 1);
    expect(theme.dataTableTheme.horizontalMargin, 16);
  });
}
