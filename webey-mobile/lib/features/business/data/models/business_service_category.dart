/// Hizmet kategorisi: sistem (Webey varsayılanı) veya işletmeye özel.
class BusinessServiceCategory {
  const BusinessServiceCategory({
    required this.id,
    required this.name,
    required this.slug,
    this.iconKey,
    this.sortOrder = 0,
    this.isSystem = false,
    this.serviceCount = 0,
  });

  final int id;
  final String name;
  final String slug;
  final String? iconKey;
  final int sortOrder;
  final bool isSystem;
  final int serviceCount;

  factory BusinessServiceCategory.fromJson(Map<String, Object?> json) {
    return BusinessServiceCategory(
      id: _asInt(json['id']) ?? 0,
      name: '${json['name'] ?? ''}'.trim(),
      slug: '${json['slug'] ?? ''}'.trim(),
      iconKey: _asNullableString(json['icon_key']),
      sortOrder: _asInt(json['sort_order']) ?? 0,
      isSystem: json['is_system'] == true,
      serviceCount: _asInt(json['service_count']) ?? 0,
    );
  }

  BusinessServiceCategory copyWith({int? serviceCount}) {
    return BusinessServiceCategory(
      id: id,
      name: name,
      slug: slug,
      iconKey: iconKey,
      sortOrder: sortOrder,
      isSystem: isSystem,
      serviceCount: serviceCount ?? this.serviceCount,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static String? _asNullableString(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }
}
