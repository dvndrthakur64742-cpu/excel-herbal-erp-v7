import 'package:excel_herbal_erp/core/api_client.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/core/gps_location_platform.dart';
import 'package:excel_herbal_erp/core/gps_tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

class _FakeGpsApi implements GpsApiTransport {
  _FakeGpsApi(this.attendance);

  Map<String, dynamic> attendance;
  Object? gpsDutyError;
  Object? gpsPointError;
  final posts = <({String path, Map<String, dynamic>? data})>[];

  @override
  Future<dynamic> get(String path) async {
    if (path == ApiPaths.gpsDuty) {
      if (gpsDutyError != null) throw gpsDutyError!;
      return Map<String, dynamic>.from(attendance);
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    posts.add((path: path, data: data));
    if (path == ApiPaths.gpsPoints && gpsPointError != null) {
      throw gpsPointError!;
    }
    return const <String, dynamic>{'ok': true};
  }
}

class _FakeLocation implements GpsLocationPlatform {
  bool enabled = true;
  bool backgroundTracking = false;
  int watchRequests = 0;
  Object? locationServiceError;
  Object? permissionCheckError;
  Object? permissionRequestError;
  Object? currentFixError;
  LocationPermission permission = LocationPermission.always;
  LocationPermission requestedPermission = LocationPermission.always;
  int permissionRequests = 0;
  int fixRequests = 0;
  GpsFix fix = (
    latitude: 31.9579,
    longitude: 77.1095,
    accuracy: 4.2,
  );

  @override
  bool get supportsBackgroundTracking => backgroundTracking;

  @override
  Stream<GpsFix> watchPositions() {
    watchRequests++;
    return const Stream<GpsFix>.empty();
  }

  @override
  Future<LocationPermission> checkPermission() async {
    if (permissionCheckError != null) throw permissionCheckError!;
    return permission;
  }

  @override
  Future<GpsFix> currentFix() async {
    fixRequests++;
    if (currentFixError != null) throw currentFixError!;
    return fix;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    if (locationServiceError != null) throw locationServiceError!;
    return enabled;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    if (permissionRequestError != null) throw permissionRequestError!;
    permissionRequests++;
    permission = requestedPermission;
    return permission;
  }
}

Map<String, dynamic> _attendance(String status) => {
      'gps_status': status,
      'gps_window_start_utc': '',
      'gps_window_stop_utc': '',
    };

void main() {
  group('GpsTrackingService Android policy', () {
    test('Office old backend missing GPS duty route fails closed without location access', () async {
      final api = _FakeGpsApi(_attendance('active'))
        ..gpsDutyError = const ApiException(
          'rest_no_route',
          'No route was found matching the URL and request method.',
          404,
        );
      final location = _FakeLocation();
      final service = GpsTrackingService.forTest(
        api: api, location: location,
      );

      await service.start();

      expect(service.active, isFalse);
      expect(service.armed, isFalse);
      expect(service.dutyStatus, 'unavailable');
      expect(service.lastError, contains('ERP server does not support'));
      expect(service.lastError, contains('No GPS point was sent'));
      expect(location.fixRequests, 0);
      expect(location.watchRequests, 0);
      expect(location.permissionRequests, 0);
      expect(api.posts, isEmpty);

      // Backend upgrade may restore the route; an explicit sync then
      // resumes only from a fresh, authoritative server duty decision.
      api.gpsDutyError = null;
      await service.sync();
      expect(service.active, isTrue);
      expect(api.posts, hasLength(1));
      expect(service.lastError, isNull);
      service.stop(status: 'signed_out');
      service.dispose();
    });

    test('GPS duty API permission denial does not impersonate a missing route', () async {
      final api = _FakeGpsApi(_attendance('active'))
        ..gpsDutyError = const ApiException(
          'permission_denied', 'Access denied.', 403,
        );
      final location = _FakeLocation();
      final service = GpsTrackingService.forTest(
        api: api, location: location,
      );

      await service.start();
      expect(service.active, isFalse);
      expect(service.dutyStatus, 'unavailable');
      expect(service.lastError, contains('not authorised'));
      expect(service.lastError, isNot(contains('does not support')));
      expect(location.fixRequests, 0);
      expect(api.posts, isEmpty);
      service.dispose();
    });

    test('a business-specific 404 is not mistaken for a missing REST route', () async {
      final api = _FakeGpsApi(_attendance('active'))
        ..gpsDutyError = const ApiException(
          'gps_employee_missing', 'Employee is not configured.', 404,
        );
      final location = _FakeLocation();
      final service = GpsTrackingService.forTest(
        api: api, location: location,
      );

      await service.start();
      expect(service.active, isFalse);
      expect(service.dutyStatus, 'unavailable');
      expect(service.lastError, 'Employee is not configured.');
      expect(location.fixRequests, 0);
      expect(api.posts, isEmpty);
      service.dispose();
    });

    test('blocks tracking when device location service is off', () async {
      final api = _FakeGpsApi(_attendance('active'));
      final location = _FakeLocation()..enabled = false;
      final service = GpsTrackingService.forTest(
        api: api,
        location: location,
      );

      await service.start();

      expect(service.active, isFalse);
      expect(service.locationDisabled, isTrue);
      expect(service.lastError, contains('Device location is off'));
      expect(location.fixRequests, 0);
    });

    test('surfaces browser location-service API failures and remains retryable', () async {
      final api = _FakeGpsApi(_attendance('active'));
      final location = _FakeLocation()
        ..locationServiceError = StateError('location service API failed');
      final service = GpsTrackingService.forTest(
        api: api,
        location: location,
      );

      await service.start();

      expect(service.active, isFalse);
      expect(service.dutyStatus, 'unavailable');
      expect(service.lastError, contains('location service API failed'));
      expect(api.posts, isEmpty);

      location.locationServiceError = null;
      await service.sync();
      expect(service.active, isTrue);
      expect(api.posts, hasLength(1));
      service.stop(status: 'checked_out');
      service.dispose();
    });

    test('surfaces browser permission-query failures instead of losing GPS state', () async {
      final api = _FakeGpsApi(_attendance('active'));
      final location = _FakeLocation()
        ..permissionCheckError = StateError('permission query failed');
      final service = GpsTrackingService.forTest(
        api: api,
        location: location,
      );

      await service.start();

      expect(service.active, isFalse);
      expect(service.dutyStatus, 'unavailable');
      expect(service.lastError, contains('permission query failed'));
      expect(api.posts, isEmpty);
      service.dispose();
    });

    test('handles runtime permission denial without sending GPS', () async {
      final api = _FakeGpsApi(_attendance('active'));
      final location = _FakeLocation()
        ..permission = LocationPermission.denied
        ..requestedPermission = LocationPermission.denied;
      final service = GpsTrackingService.forTest(
        api: api,
        location: location,
      );

      await service.start();

      expect(service.active, isFalse);
      expect(service.permissionBlocked, isTrue);
      expect(location.permissionRequests, 1);
      expect(location.fixRequests, 0);
      expect(api.posts, isEmpty);
    });

    test('handles denied-forever permission without re-requesting it', () async {
      final api = _FakeGpsApi(_attendance('active'));
      final location = _FakeLocation()
        ..permission = LocationPermission.deniedForever;
      final service = GpsTrackingService.forTest(
        api: api,
        location: location,
      );

      await service.start();

      expect(service.active, isFalse);
      expect(service.permissionBlocked, isTrue);
      expect(service.lastError, contains('blocked'));
      expect(location.permissionRequests, 0);
      expect(api.posts, isEmpty);
    });

    test('independent GPS duty can arm without any attendance record', () async {
      final api = _FakeGpsApi(_attendance('scheduled'));
      final service = GpsTrackingService.forTest(
        api: api, location: _FakeLocation());
      await service.start();
      expect(service.dutyStatus, 'scheduled');
      expect(api.posts, isEmpty);
      service.dispose();
    });

    test('granted permission sends an immediate high-accuracy point', () async {
      final api = _FakeGpsApi(_attendance('active'));
      final location = _FakeLocation();
      final service = GpsTrackingService.forTest(
        api: api,
        location: location,
      );

      await service.start();

      expect(service.active, isTrue);
      expect(service.dutyStatus, 'active');
      expect(location.fixRequests, 1);
      expect(api.posts, hasLength(1));
      expect(api.posts.single.path, ApiPaths.gpsPoints);
      expect(api.posts.single.data?['lat'], location.fix.latitude);
      expect(api.posts.single.data?['lng'], location.fix.longitude);
      expect(api.posts.single.data?['accuracy'], location.fix.accuracy);
      service.stop(status: 'checked_out');
    });

    test('uses a location stream for Android foreground duty tracking', () async {
      final api = _FakeGpsApi(_attendance('active'));
      final location = _FakeLocation()..backgroundTracking = true;
      final service = GpsTrackingService.forTest(
        api: api,
        location: location,
      );

      await service.start();

      expect(service.active, isTrue);
      expect(location.watchRequests, 1);
      expect(api.posts, hasLength(1));
      service.stop(status: 'checked_out');
      service.dispose();
    });

    test('surfaces current-position failures and permits immediate retry', () async {
      final api = _FakeGpsApi(_attendance('active'));
      final location = _FakeLocation()
        ..currentFixError = StateError('position unavailable');
      final service = GpsTrackingService.forTest(
        api: api,
        location: location,
      );

      await service.start();

      expect(service.active, isTrue);
      expect(service.lastError, contains('position unavailable'));
      expect(api.posts, isEmpty);

      location.currentFixError = null;
      await service.sendNow();

      expect(api.posts, hasLength(1));
      expect(service.lastError, isNull);
      service.stop(status: 'checked_out');
      service.dispose();
    });

    test('server GPS cutoff stops local tracking immediately', () async {
      final api = _FakeGpsApi(_attendance('active'))
        ..gpsPointError = const ApiException(
          'gps_window_closed',
          'GPS duty window is closed.',
          422,
        );
      final location = _FakeLocation();
      final service = GpsTrackingService.forTest(
        api: api,
        location: location,
      );

      await service.start();

      expect(service.active, isFalse);
      expect(service.armed, isFalse);
      expect(service.dutyStatus, 'auto_stopped');
    });

    test('server revokes GPS duty during upload and cancels sampling', () async {
      final api = _FakeGpsApi(_attendance('active'))
        ..gpsPointError = const ApiException(
          'gps_duty_inactive', 'Approved leave stops GPS duty.', 409,
        );
      final location = _FakeLocation()..backgroundTracking = true;
      final service = GpsTrackingService.forTest(
        api: api, location: location);
      await service.start();
      expect(service.active, isFalse);
      expect(service.armed, isFalse);
      expect(service.dutyStatus, 'not_scheduled');
      expect(service.lastError, contains('Approved leave'));
      expect(location.watchRequests, 0);
      expect(api.posts, hasLength(1));
      service.dispose();
    });

    test('failed server duty refresh closes existing local GPS collection', () async {
      final api = _FakeGpsApi(_attendance('active'));
      final service = GpsTrackingService.forTest(
        api: api, location: _FakeLocation());
      await service.start();
      expect(service.active, isTrue);
      api.attendance = <String, dynamic>{'gps_status': 'not_scheduled'};
      await service.sync();
      expect(service.active, isFalse);
      expect(service.armed, isFalse);
      expect(service.dutyStatus, 'not_scheduled');
      service.dispose();
    });

    test('server leave/holiday state prevents local tracking', () async {
      final api = _FakeGpsApi(_attendance('not_scheduled'));
      final service = GpsTrackingService.forTest(
        api: api,
        location: _FakeLocation(),
      );

      await service.start();

      expect(service.active, isFalse);
      expect(service.dutyStatus, 'not_scheduled');
      expect(api.posts, isEmpty);
    });

    test('manual stop cannot bypass automatic duty GPS', () async {
      final api = _FakeGpsApi(_attendance('active'));
      final service = GpsTrackingService.forTest(
        api: api,
        location: _FakeLocation(),
      );
      await service.start();
      expect(service.active, isTrue);

      service.stop();

      expect(service.active, isTrue);
      expect(service.lastError, contains('automatic'));
      service.stop(status: 'checked_out');
      expect(service.active, isFalse);
    });

    test('signed-out lifecycle always stops local tracking', () async {
      final api = _FakeGpsApi(_attendance('active'));
      final service = GpsTrackingService.forTest(
        api: api,
        location: _FakeLocation(),
      );
      await service.start();
      expect(service.active, isTrue);

      service.stop(status: 'signed_out');

      expect(service.active, isFalse);
      expect(service.armed, isFalse);
      expect(service.dutyStatus, 'signed_out');
    });
  });
}
