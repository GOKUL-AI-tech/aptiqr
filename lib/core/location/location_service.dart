import 'package:geolocator/geolocator.dart';

class LocationException implements Exception {
  final String message;
  LocationException(this.message);
  @override
  String toString() => message;
}

/// One-shot high-accuracy fix, used only when a test has a geofence.
class LocationService {
  LocationService._();

  static Future<Position> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationException('Turn on your phone\'s location and try again.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw LocationException('Location permission is needed to start this test. Allow it in Settings > Apps > AptiQR.');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
    );
    if (pos.isMocked) {
      throw LocationException('Mock locations are not allowed. Turn them off and try again.');
    }
    return pos;
  }
}
