abstract final class ShellLayout {
  static const double desktopBreakpoint = 960;

  static bool isDesktopWidth(double width) => width >= desktopBreakpoint;

  // The desktop sidebar occupies part of the viewport. A records workspace
  // should not revert to phone cards solely because of that sidebar.
  static bool useRecordTable(double viewportWidth, double contentWidth) =>
      isDesktopWidth(contentWidth) || (isDesktopWidth(viewportWidth) && contentWidth >= 640);

  // A drawer must never be wider than the actual phone viewport, including
  // narrow split-screen mode and large system text settings.
  static double mobileDrawerWidth(double viewportWidth) =>
      (viewportWidth * .9).clamp(0.0, 390.0).toDouble();

  /// NavigationBar requires at least two destinations. Only the universally
  /// permitted Home/Profile routes may fill an incomplete projection.
  static List<Map<String, dynamic>> mobileDestinations(
      List<Map<String, dynamic>> projected) {
    if (projected.length >= 2) return projected;
    final items = List<Map<String, dynamic>>.of(projected);
    for (final item in const [
      {'id': 'home', 'label': 'Home'},
      {'id': 'profile', 'label': 'Profile'},
    ]) {
      if (!items.any((existing) => existing['id'] == item['id'])) {
        items.add(item);
      }
      if (items.length >= 2) break;
    }
    return items;
  }

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
