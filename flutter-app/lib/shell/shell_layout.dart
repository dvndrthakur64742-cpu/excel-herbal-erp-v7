abstract final class ShellLayout {
  static const double desktopBreakpoint = 960;

  static bool isDesktopWidth(double width) => width >= desktopBreakpoint;

  // A drawer must never be wider than the actual phone viewport, including
  // narrow split-screen mode and large system text settings.
  static double mobileDrawerWidth(double viewportWidth) =>
      (viewportWidth * .9).clamp(0.0, 390.0).toDouble();

  // Preserve the selected destination by stable route ID, not its position.
  // Server-projected role/branch changes can reorder or remove bottom tabs.
  static int mobileNavIndex(
    List<Map<String, dynamic>> items,
    String selectedRoute,
  ) {
    if (items.isEmpty) return 0;
    final selected = items.indexWhere((item) => '${item['id']}' == selectedRoute);
    if (selected >= 0) return selected;
    final home = items.indexWhere((item) => '${item['id']}' == 'home');
    return home >= 0 ? home : 0;
  }
}
