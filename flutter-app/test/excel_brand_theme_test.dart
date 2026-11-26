import 'package:excel_herbal_erp/theme/excel_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sidebar normal and selected text have accessible contrast', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      return ((x > y ? x : y) + 0.05) / ((x < y ? x : y) + 0.05);
    }
    expect(contrast(Colors.white, ExcelBrand.navigationSurface),
        greaterThanOrEqualTo(4.5));
    expect(contrast(Colors.white, ExcelBrand.navigationSelected),
        greaterThanOrEqualTo(4.5));
    expect(contrast(ExcelBrand.navigationMuted, ExcelBrand.navigationSurface),
        greaterThanOrEqualTo(4.5));
  });

  test('primary and error text retain readable contrast against white', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      return ((x > y ? x : y) + 0.05) / ((x < y ? x : y) + 0.05);
    }
    final theme = ExcelBrand.lightTheme();
    expect(contrast(theme.colorScheme.primary, theme.colorScheme.onPrimary),
        greaterThanOrEqualTo(4.5));
    expect(contrast(theme.colorScheme.error, ExcelBrand.surface),
        greaterThanOrEqualTo(4.5));
  });

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
