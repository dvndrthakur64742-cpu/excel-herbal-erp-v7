import 'package:flutter/widgets.dart';

class OverlayTransition {
  OverlayTransition._();
  static bool _closing = false;

  static Future<bool> closeAndSettle(BuildContext context) async {
    if (_closing || !context.mounted) return false;
    final navigator = Navigator.maybeOf(context);
    if (navigator == null || !navigator.canPop()) return false;
    _closing = true;
    try {
      navigator.pop();
      await WidgetsBinding.instance.endOfFrame;
      return true;
    } finally {
      _closing = false;
    }
  }
}
