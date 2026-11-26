import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'api_client.dart';
import 'gps_location_platform.dart';
import 'api_paths.dart';
import 'ui_error.dart';

abstract interface class GpsApiTransport {
  Future<dynamic> get(String path);

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? data,
  });
}

class _ApiClientGpsTransport implements GpsApiTransport {
  const _ApiClientGpsTransport(this.api);

  final ApiClient api;

  @override
  Future<dynamic> get(String path) => api.get(path);

  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? data,
  }) =>
      api.post(path, data: data);
}

class GpsTrackingService extends ChangeNotifier {
  GpsTrackingService(
    ApiClient api, {
    GpsLocationPlatform? location,
  })  : _api = _ApiClientGpsTransport(api),
        _location = location ?? const GeolocatorGpsLocationPlatform();

  @visibleForTesting
  GpsTrackingService.forTest({
    required GpsApiTransport api,
    required GpsLocationPlatform location,
  })  : _api = api,
        _location = location;

  final GpsApiTransport _api;
  final GpsLocationPlatform _location;
  Timer? _pointTimer;
  Timer? _scheduleTimer;
  Timer? _stopTimer;
  StreamSubscription<GpsFix>? _positionSubscription;
  bool _active = false;
  bool _armed = false;
  bool _sending = false;
  bool _disposed = false;
  int _epoch = 0;
  int _request = 0;
  DateTime? _windowStop;

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  bool _canSend(int epoch) => _current(epoch) && _active &&
      (_windowStop == null || DateTime.now().isBefore(_windowStop!));

  void _notify() { if (!_disposed) notifyListeners(); }
  String _dutyStatus = 'unknown';
  String? _lastError;
  DateTime? _lastSentAt;

  bool get active => _active;
  bool get armed => _armed;
  bool get sending => _sending;
  String get dutyStatus => _dutyStatus;
  String? get lastError => _lastError;
  DateTime? get lastSentAt => _lastSentAt;
  bool get permissionBlocked => _dutyStatus == 'permission_blocked';
  bool get locationDisabled => _dutyStatus == 'location_disabled';

  /// Synchronises route tracking with the server-owned attendance/GPS policy.
  /// There is deliberately no user-controlled route start/stop state: an
  /// active attendance starts tracking at the duty window and checkout/5 PM
  /// stops it automatically.
  Future<void> start() async {
    if (_disposed) return;
    final request = ++_request;
    Map<String, dynamic>? attendance;
    try {
      final data = await _api.get(ApiPaths.attendanceToday);
      if (_disposed || request != _request) return;
      if (data is! Map) throw const FormatException('Invalid attendance response');
      attendance = Map<String, dynamic>.from(data);
    } catch (e) {
      if (_disposed || request != _request) return;
      _lastError = UiError.message(e);
      stop(status: 'unavailable');
      return;
    }

    if (_disposed || request != _request) return;
    if (attendance.isEmpty) {
      stop(status: 'not_checked_in');
      return;
    }

    final status = '${attendance['gps_status'] ?? 'unknown'}';
    _dutyStatus = status;
    _lastError = null;

    switch (status) {
      case 'active':
        await _activate(attendance);
        return;
      case 'scheduled':
        _armForWindow(attendance);
        return;
      case 'checked_out':
      case 'auto_stopped':
      case 'not_checked_in':
        stop(status: status);
        return;
      default:
        stop(status: status);
    }
  }

  Future<void> sync() => start();

  Future<void> _activate(Map<String, dynamic> attendance) async {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    if (_active) {
      _scheduleAutoStop(attendance);
      return;
    }
    _clearTracking();
    final epoch = _epoch;
    _armed = true;
    _scheduleAutoStop(attendance);
    if (!_current(epoch)) return;
    if (!_active) {
      bool permissionReady;
      try {
        permissionReady = await _ensurePermission(epoch);
        if (!_current(epoch)) return;
      } catch (e) {
        if (!_current(epoch)) return;
        // Browser/device geolocation APIs can throw when unavailable or blocked
        // (for example, a browser permission API failure). Keep attendance intact,
        // expose the real GPS failure in the UI, and allow an explicit retry.
        _active = false;
        _pointTimer?.cancel();
        _pointTimer = null;
        _dutyStatus = 'unavailable';
        _lastError = 'Unable to check device location permission: ${UiError.message(e)}';
        _scheduleAutoStop(attendance);
        _notify();
        return;
      }
      if (!permissionReady) {
        _active = false;
        _pointTimer?.cancel();
        _pointTimer = null;
        _scheduleAutoStop(attendance);
        _notify();
        return;
      }
      _active = true;
      _dutyStatus = 'active';
      _notify();
      await sendNow();
      if (!_canSend(epoch)) return;
      if (_active && _location.supportsBackgroundTracking) {
        // Android's foreground location service keeps collecting fixes while
        // the employee switches apps or locks the screen. Upload no more than
        // one point per five minutes to preserve the agreed route cadence.
        await _positionSubscription?.cancel();
        if (!_canSend(epoch)) return;
        _positionSubscription = _location.watchPositions().listen(
          (position) {
            if (!_canSend(epoch) || _sending) return;
            final last = _lastSentAt;
            if (last != null &&
                DateTime.now().difference(last) < const Duration(minutes: 5)) {
              return;
            }
            unawaited(_sendPosition(position));
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_canSend(epoch)) return;
            _lastError = 'Background GPS stream error: ${UiError.message(error)}';
            // Fall back to foreground polling if the native stream terminates;
            // the error remains visible so the operator can diagnose gaps.
            _pointTimer?.cancel();
            _pointTimer = Timer.periodic(
              const Duration(minutes: 5),
              (_) { if (_canSend(epoch)) unawaited(sendNow()); },
            );
            _notify();
          },
        );
      } else if (_active) {
        // Web/browser tracking is foreground-only; browsers may throttle
        // location and timers when a tab is backgrounded.
        _pointTimer?.cancel();
        _pointTimer = Timer.periodic(
          const Duration(minutes: 5),
          (_) { if (_canSend(epoch)) unawaited(sendNow()); },
        );
      }
    }
    if (_current(epoch)) _scheduleAutoStop(attendance);
  }

  void _armForWindow(Map<String, dynamic> attendance) {
    _clearTracking();
    final epoch = _epoch;
    _armed = true;
    _dutyStatus = 'scheduled';

    final startsAt = DateTime.tryParse(
      '${attendance['gps_window_start_utc'] ?? ''}',
    )?.toLocal();
    if (startsAt == null) {
      _lastError = 'GPS duty schedule unavailable.';
      _armed = false;
      _notify();
      return;
    }
    final delay = startsAt.difference(DateTime.now());
    if (delay <= Duration.zero) {
      // Avoid an unbounded immediate loop if server/device clocks differ.
      _scheduleTimer = Timer(const Duration(seconds: 30), () { if (_current(epoch)) unawaited(start()); });
    } else {
      _scheduleTimer = Timer(delay, () { if (_current(epoch)) unawaited(start()); });
    }
    _scheduleAutoStop(attendance);
    _notify();
  }

  void _scheduleAutoStop(Map<String, dynamic> attendance) {
    _stopTimer?.cancel();
    final stopsAt = DateTime.tryParse(
      '${attendance['gps_window_stop_utc'] ?? ''}',
    )?.toLocal();
    _windowStop = stopsAt;
    if (stopsAt == null) {
      _lastError = 'GPS duty cutoff unavailable.';
      stop(status: 'unavailable');
      return;
    }
    final delay = stopsAt.difference(DateTime.now());
    if (delay <= Duration.zero) {
      stop(status: 'auto_stopped');
      return;
    }
    final epoch = _epoch;
    _stopTimer = Timer(delay, () { if (_current(epoch)) stop(status: 'auto_stopped'); });
  }

  /// Internal/system lifecycle stop only. UI must never expose a manual route
  /// Start/Stop business action; checkout/server policy owns the route state.
  void stop({String status = 'stopped'}) {
    if (_disposed) return;
    // Legacy UI may still call stop() without a server-owned reason. Refuse to
    // turn tracking off in that case so an employee cannot bypass duty GPS.
    if (status == 'stopped') {
      _lastError =
          'Duty GPS is automatic. It stops only after checkout or the 5 PM duty cutoff.';
      _notify();
      return;
    }
    ++_request;
    _clearTracking();
    _dutyStatus = status;
    _notify();
  }

  void _clearTracking() {
    ++_epoch;
    _pointTimer?.cancel();
    _scheduleTimer?.cancel();
    _stopTimer?.cancel();
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
    _pointTimer = null;
    _scheduleTimer = null;
    _stopTimer = null;
    _windowStop = null;
    _active = false;
    _armed = false;
    _sending = false;
  }

  Future<void> sendNow() async {
    final epoch = _epoch;
    if (!_canSend(epoch) || _sending) return;
    _sending = true;
    _notify();
    try {
      final position = await _location.currentFix();
      if (!_canSend(epoch)) return; // Checkout, cutoff or session change while locating.
      await _api.post(
        ApiPaths.gpsPoints,
        data: {
          'lat': position.latitude,
          'lng': position.longitude,
          'accuracy': position.accuracy,
          'source': 'duty',
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      if (!_current(epoch)) return;
      _lastSentAt = DateTime.now();
      _lastError = null;
    } catch (e) {
      if (!_current(epoch)) return;
      _lastError = UiError.message(e);
      if (e is ApiException &&
          const {
            'gps_checkin_required',
            'gps_window_closed',
            'gps_recorded_date_invalid',
          }.contains(e.code)) {
        stop(
          status: e.code == 'gps_window_closed'
              ? 'auto_stopped'
              : 'not_checked_in',
        );
        return;
      }
      if (e is ApiException && e.code == 'gps_window_not_started') {
        stop(status: 'scheduled');
        unawaited(start());
      }
    } finally {
      if (_current(epoch)) {
        _sending = false;
        _notify();
      }
    }
  }

  Future<void> _sendPosition(GpsFix position) async {
    final epoch = _epoch;
    if (!_canSend(epoch) || _sending) return;
    _sending = true;
    _notify();
    try {
      await _api.post(
        ApiPaths.gpsPoints,
        data: {
          'lat': position.latitude,
          'lng': position.longitude,
          'accuracy': position.accuracy,
          'source': 'duty',
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      if (!_current(epoch)) return;
      _lastSentAt = DateTime.now();
      _lastError = null;
    } catch (e) {
      if (!_current(epoch)) return;
      _lastError = UiError.message(e);
      if (e is ApiException &&
          const {
            'gps_checkin_required',
            'gps_window_closed',
            'gps_recorded_date_invalid',
          }.contains(e.code)) {
        stop(
          status: e.code == 'gps_window_closed'
              ? 'auto_stopped'
              : 'not_checked_in',
        );
      }
    } finally {
      if (_current(epoch)) {
        _sending = false;
        _notify();
      }
    }
  }

  Future<bool> _ensurePermission(int epoch) async {
    final serviceEnabled = await _location.isLocationServiceEnabled();
    if (!_current(epoch)) return false;
    if (!serviceEnabled) {
      _dutyStatus = 'location_disabled';
      _lastError =
          'Device location is off. Turn on Location, then tap Retry for duty GPS.';
      return false;
    }

    var permission = await _location.checkPermission();
    if (!_current(epoch)) return false;
    if (permission == LocationPermission.denied) {
      permission = await _location.requestPermission();
    }
    if (!_current(epoch)) return false;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _dutyStatus = 'permission_blocked';
      _lastError = permission == LocationPermission.deniedForever
          ? 'Location permission is blocked. Allow location for this site in browser or device settings, then tap Retry.'
          : 'Location permission is required for duty GPS. Allow it when prompted, then tap Retry.';
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_request;
    _clearTracking();
    super.dispose();
  }
}
