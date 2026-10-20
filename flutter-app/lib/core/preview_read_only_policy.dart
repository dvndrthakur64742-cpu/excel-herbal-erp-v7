/// Compile-time, browser-side guard for the owner-approved office web preview.
/// This is not a replacement for canonical V7 server authorization.
/// Financial posting remains disabled by the existing backend release gates.
abstract final class PreviewReadOnlyPolicy {
  static const bool enabled = bool.fromEnvironment(
    'EH7_PREVIEW_READ_ONLY', defaultValue: false,
  );

  static bool permits(String method, String path, {bool? preview}) {
    if (!(preview ?? enabled)) return true;
    final verb = method.toUpperCase();
    if (verb == 'GET' || verb == 'HEAD' || verb == 'OPTIONS') return true;
    // Only sign-in/session hygiene is allowed. In particular, do not
    // allow POST for attendance, GPS, stock, sales, B2B, cash, or finance.
    final parsed = Uri.tryParse(path);
    if (parsed == null || parsed.hasQuery || parsed.hasFragment) return false;
    return verb == 'POST' &&
        const {'/auth/login', '/auth/refresh', '/auth/logout'}.contains(parsed.path) &&
        !parsed.hasAuthority;
  }
}
