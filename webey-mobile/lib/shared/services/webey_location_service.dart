import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class WebeyLocationResult {
  const WebeyLocationResult({
    required this.latitude,
    required this.longitude,
    this.city,
    this.district,
    this.neighborhood,
    this.addressLine,
  });

  final double latitude;
  final double longitude;
  final String? city;
  final String? district;
  final String? neighborhood;
  final String? addressLine;

  bool get hasUsableCoordinates => latitude != 0 || longitude != 0;

  Map<String, dynamic> toProfileJson() {
    return {
      'city': city,
      'district': district,
      'neighborhood': neighborhood,
      'address_line': addressLine,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}

class WebeyLocationException implements Exception {
  const WebeyLocationException(this.message, {this.permanentlyDenied = false});

  final String message;
  final bool permanentlyDenied;

  @override
  String toString() => message;
}

class WebeyLocationService {
  const WebeyLocationService();

  static const instance = WebeyLocationService();

  Future<WebeyLocationResult> getCurrentLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const WebeyLocationException(
        'Konum servisleri kapalı. Bilgileri manuel girebilirsiniz.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const WebeyLocationException(
        'Konum izni verilmedi. Bilgileri manuel girebilirsiniz.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const WebeyLocationException(
        'Konum izni kapalı. Ayarlardan izin verebilirsiniz.',
        permanentlyDenied: true,
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );

    if (position.latitude == 0 && position.longitude == 0) {
      throw const WebeyLocationException(
        'Geçerli bir konum alınamadı. Bilgileri manuel girebilirsiniz.',
      );
    }

    return _withPlacemark(position.latitude, position.longitude);
  }

  Future<WebeyLocationResult> _withPlacemark(
    double latitude,
    double longitude,
  ) async {
    try {
      final marks = await placemarkFromCoordinates(latitude, longitude);
      final mark = marks.isNotEmpty ? marks.first : null;
      final city = _firstNonEmpty([mark?.administrativeArea, mark?.locality]);
      final district = _firstNonEmpty([
        mark?.subAdministrativeArea,
        mark?.subLocality,
      ]);
      final neighborhood = _firstNonEmpty([
        mark?.subLocality,
        mark?.thoroughfare,
      ]);
      final addressLine = _addressLine(mark);
      return WebeyLocationResult(
        latitude: latitude,
        longitude: longitude,
        city: city,
        district: district,
        neighborhood: neighborhood,
        addressLine: addressLine,
      );
    } catch (_) {
      return WebeyLocationResult(latitude: latitude, longitude: longitude);
    }
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  static String? _addressLine(Placemark? mark) {
    if (mark == null) return null;
    final parts = <String>[
      if ((mark.street ?? '').trim().isNotEmpty) mark.street!.trim(),
      if ((mark.subLocality ?? '').trim().isNotEmpty) mark.subLocality!.trim(),
      if ((mark.subAdministrativeArea ?? '').trim().isNotEmpty)
        mark.subAdministrativeArea!.trim(),
      if ((mark.administrativeArea ?? '').trim().isNotEmpty)
        mark.administrativeArea!.trim(),
    ];
    if (parts.isEmpty) return null;
    return parts.toSet().join(', ');
  }
}
