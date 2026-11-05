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

  test('ERP theme keeps dialogs menus and sheets inside shared surfaces', () {
    final theme = ExcelBrand.lightTheme();

    expect(
      theme.dialogTheme.insetPadding,
      const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    );
    expect(theme.popupMenuTheme.color, ExcelBrand.surface);
    expect(theme.popupMenuTheme.surfaceTintColor, Colors.transparent);
    expect(theme.bottomSheetTheme.showDragHandle, isTrue);
    expect(theme.bottomSheetTheme.clipBehavior, Clip.antiAlias);
    expect(theme.bottomSheetTheme.modalBackgroundColor, ExcelBrand.surface);
  });
}
