class CustomerProfileStats {
  const CustomerProfileStats({
    required this.appointmentsCount,
    required this.completedCount,
    required this.cancelledCount,
  });

  final int appointmentsCount;
  final int completedCount;
  final int cancelledCount;

  static const empty = CustomerProfileStats(
    appointmentsCount: 0,
    completedCount: 0,
    cancelledCount: 0,
  );

  factory CustomerProfileStats.fromJson(Map<String, Object?> json) {
    return CustomerProfileStats(
      appointmentsCount: _int(json['appointments_count']),
      completedCount: _int(json['completed_count']),
      cancelledCount: _int(json['cancelled_count']),
    );
  }
}

class CustomerProfile {
  const CustomerProfile({
    required this.id,
    required this.email,
    required this.fullName,
    this.firstName,
    this.lastName,
    this.phone,
    this.city,
    this.district,
    this.neighborhood,
    this.addressLine,
    this.latitude,
    this.longitude,
    this.avatarUrl,
    required this.stats,
  });

  final String id;
  final String email;
  final String fullName;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? city;
  final String? district;
  final String? neighborhood;
  final String? addressLine;
  final double? latitude;
  final double? longitude;
  final String? avatarUrl;
  final CustomerProfileStats stats;

  bool get hasSavedLocation => latitude != null && longitude != null;

  String get displayInitial {
    if (fullName.isNotEmpty) return fullName[0].toUpperCase();
    if (email.isNotEmpty) return email[0].toUpperCase();
    return 'U';
  }

  String get displayFirstName {
    if (firstName != null && firstName!.isNotEmpty) return firstName!;
    final parts = fullName.split(' ');
    return parts.isNotEmpty ? parts.first : fullName;
  }

  String get displayLastName {
    if (lastName != null && lastName!.isNotEmpty) return lastName!;
    final parts = fullName.split(' ');
    return parts.length > 1 ? parts.skip(1).join(' ') : '';
  }

  factory CustomerProfile.fromJson(Map<String, Object?> json) {
    final p = _map(json['profile']) ?? json;
    final statsJson = _map(p['stats']) ?? const {};
    return CustomerProfile(
      id: _str(p['id']) ?? '',
      email: _str(p['email']) ?? '',
      fullName: _str(p['full_name']) ?? '',
      firstName: _str(p['first_name']),
      lastName: _str(p['last_name']),
      phone: _str(p['phone']),
      city: _str(p['city']),
      district: _str(p['district']),
      neighborhood: _str(p['neighborhood']),
      addressLine: _str(p['address_line']),
      latitude: _double(p['latitude']),
      longitude: _double(p['longitude']),
      avatarUrl: _str(p['avatar_url']),
      stats: CustomerProfileStats.fromJson(statsJson),
    );
  }
}

// Backend alanları int/string/null dönebilir; tip drift'inde profilin
// sessizce boşalmaması için güvenli parse helper'ları.
Map<String, Object?>? _map(Object? value) {
  if (value is Map) return Map<String, Object?>.from(value);
  return null;
}

String? _str(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double? _double(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
