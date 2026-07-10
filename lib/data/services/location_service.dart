import 'package:geolocator/geolocator.dart';

class PetAgentLocation {
  const PetAgentLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;

  Map<String, dynamic> toJson() {
    return {
      'permission': 'granted_by_user',
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_meters': accuracyMeters,
      'timestamp': timestamp.toIso8601String(),
      'source': 'device_gps',
    };
  }
}

abstract class LocationService {
  Future<PetAgentLocation> requestCurrentLocation();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<PetAgentLocation> requestCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceException(
        'Location services are off. Turn them on and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const LocationServiceException(
        'Location permission was not granted.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationServiceException(
        'Location permission is blocked. Enable it in system settings.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );

    return PetAgentLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      timestamp: position.timestamp,
    );
  }
}

class LocationServiceException implements Exception {
  const LocationServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
