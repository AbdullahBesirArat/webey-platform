class BusinessStaffHour {
  const BusinessStaffHour({
    this.day,
    this.isOpen = true,
    this.openTime,
    this.closeTime,
  });

  final String? day;
  final bool isOpen;
  final String? openTime;
  final String? closeTime;

  factory BusinessStaffHour.fromJson(Map<String, Object?> json) {
    return BusinessStaffHour(
      day: _asString(json['day']),
      isOpen: _asBool(json['is_open'], fallback: true),
      openTime: _asString(json['open_time']),
      closeTime: _asString(json['close_time']),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'day': day,
      'is_open': isOpen,
      'open_time': openTime,
      'close_time': closeTime,
    };
  }
}

class BusinessStaffItem {
  const BusinessStaffItem({
    this.id,
    required this.name,
    this.role,
    this.phone,
    this.email,
    this.avatarUrl,
    this.isActive = true,
    this.serviceIds = const [],
    this.hours = const [],
  });

  final int? id;
  final String name;
  final String? role;
  final String? phone;
  final String? email;
  final String? avatarUrl;
  final bool isActive;
  final List<int> serviceIds;
  final List<BusinessStaffHour> hours;

  factory BusinessStaffItem.fromJson(Map<String, Object?> json) {
    return BusinessStaffItem(
      id: _asInt(json['id']),
      name: _asString(json['name']) ?? '',
      role: _asString(json['role']),
      phone: _asString(json['phone']),
      email: _asString(json['email']),
      avatarUrl: _asString(json['avatar_url']),
      isActive: _asBool(
        json['is_active'] ?? json['active'] ?? json['status'],
        fallback: true,
      ),
      serviceIds: _asIntList(json['service_ids']),
      hours: _asHours(json['hours']),
    );
  }

  Map<String, Object?> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'role': role,
      'phone': phone,
      'email': email,
      'avatar_url': avatarUrl,
      'is_active': isActive,
      'service_ids': serviceIds,
      'hours': hours.map((hour) => hour.toJson()).toList(),
    };
  }

  BusinessStaffItem copyWith({
    int? id,
    String? name,
    String? role,
    String? phone,
    String? email,
    String? avatarUrl,
    bool? isActive,
    List<int>? serviceIds,
    List<BusinessStaffHour>? hours,
  }) {
    return BusinessStaffItem(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isActive: isActive ?? this.isActive,
      serviceIds: serviceIds ?? this.serviceIds,
      hours: hours ?? this.hours,
    );
  }
}

String? _asString(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

bool _asBool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (['1', 'true', 'yes', 'active', 'aktif'].contains(normalized)) {
      return true;
    }
    if (['0', 'false', 'no', 'inactive', 'pasif'].contains(normalized)) {
      return false;
    }
  }
  return fallback;
}

List<int> _asIntList(Object? value) {
  if (value is! List) return const [];
  return value.map(_asInt).whereType<int>().toList();
}

List<BusinessStaffHour> _asHours(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (item) => BusinessStaffHour.fromJson(Map<String, Object?>.from(item)),
      )
      .toList();
}
