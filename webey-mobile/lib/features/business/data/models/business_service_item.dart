class BusinessServiceItem {
  const BusinessServiceItem({
    this.id,
    required this.name,
    this.description,
    this.price = 0,
    this.durationMinutes = 60,
    this.category,
    this.categoryId,
    this.categorySlug,
    this.isCustomCategory = false,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final String? description;
  final double price;
  final int durationMinutes;

  /// Kategori görünen adı (service_categories.name veya eski text fallback).
  final String? category;

  /// service_categories.id — yeni ilişkisel kategori bağı (null = Kategorisiz).
  final int? categoryId;
  final String? categorySlug;
  final bool isCustomCategory;
  final bool isActive;
  final int sortOrder;

  factory BusinessServiceItem.fromJson(Map<String, Object?> json) {
    return BusinessServiceItem(
      id: _asInt(json['id']),
      name: _asString(json['name']) ?? '',
      description: _asString(json['description']),
      price: _asDouble(json['price']) ?? 0,
      durationMinutes:
          _asInt(json['duration_minutes']) ?? _asInt(json['duration']) ?? 60,
      category: _asString(json['category']),
      categoryId: _asInt(json['category_id']),
      categorySlug: _asString(json['category_slug']),
      isCustomCategory: json['is_custom_category'] == true,
      isActive: _asBool(
        json['is_active'] ?? json['active'] ?? json['status'],
        fallback: true,
      ),
      sortOrder: _asInt(json['sort_order']) ?? 0,
    );
  }

  Map<String, Object?> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
      'price': price,
      'duration_minutes': durationMinutes,
      'category': category,
      'category_id': categoryId,
      'is_active': isActive,
      'sort_order': sortOrder,
    };
  }

  BusinessServiceItem copyWith({
    int? id,
    String? name,
    String? description,
    double? price,
    int? durationMinutes,
    String? category,
    int? categoryId,
    bool clearCategoryId = false,
    String? categorySlug,
    bool? isCustomCategory,
    bool? isActive,
    int? sortOrder,
  }) {
    return BusinessServiceItem(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      category: category ?? this.category,
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      categorySlug: categorySlug ?? this.categorySlug,
      isCustomCategory: isCustomCategory ?? this.isCustomCategory,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  static String? _asString(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static double? _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static bool _asBool(Object? value, {required bool fallback}) {
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
}
