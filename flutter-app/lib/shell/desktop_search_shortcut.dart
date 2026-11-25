import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard access to the existing search screen, without replacing a form.
class DesktopSearchShortcut extends StatelessWidget {
  const DesktopSearchShortcut({
    super.key, required this.enabled, required this.onSearch, required this.child,
  });
  final bool enabled;
  final VoidCallback onSearch;
  final Widget child;
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      if (enabled)
        const SingleActivator(LogicalKeyboardKey.keyK, control: true, alt: true): onSearch,
    },
    child: Focus(autofocus: true, child: child),
  );
}
