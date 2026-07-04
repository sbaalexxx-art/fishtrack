import 'package:geolocator/geolocator.dart';

enum LocationFailureReason {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

class LocationFailure implements Exception {
  const LocationFailure(this.reason);

  final LocationFailureReason reason;
}

class LocationService {
  const LocationService();

  Future<Position> determinePosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const LocationFailure(LocationFailureReason.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw const LocationFailure(LocationFailureReason.permissionDenied);
      }

      if (permission == LocationPermission.deniedForever) {
        throw const LocationFailure(
          LocationFailureReason.permissionDeniedForever,
        );
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } on LocationFailure {
      rethrow;
    } on Exception {
      throw const LocationFailure(LocationFailureReason.unavailable);
    }
  }
}
