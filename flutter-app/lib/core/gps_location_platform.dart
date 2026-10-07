import 'package:geolocator/geolocator.dart';

typedef GpsFix = ({
  double latitude,
  double longitude,
  double accuracy,
});

abstract interface class GpsLocationPlatform {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  Future<GpsFix> currentFix();
}

class GeolocatorGpsLocationPlatform implements GpsLocationPlatform {
  const GeolocatorGpsLocationPlatform();

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() =>
      Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<GpsFix> currentFix() async {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 20),
    );
    final position = await Geolocator.getCurrentPosition(
      locationSettings: settings,
    );
    return (
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  }
}
