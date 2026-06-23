import 'business_gallery_item.dart';

class BusinessGalleryCategory {
  const BusinessGalleryCategory({
    required this.key,
    required this.label,
    required this.count,
    this.limit,
  });

  final String key;
  final String label;
  final int count;
  final int? limit;

  factory BusinessGalleryCategory.fromJson(Map<String, Object?> json) {
    return BusinessGalleryCategory(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      count: _int(json['count']) ?? 0,
      limit: _int(json['limit']),
    );
  }
}

class BusinessGallerySummary {
  const BusinessGallerySummary({
    required this.items,
    required this.categories,
    required this.quotaUsed,
    required this.quotaLimit,
    this.coverItem,
  });

  final List<BusinessGalleryItem> items;
  final List<BusinessGalleryCategory> categories;
  final int quotaUsed;
  final int quotaLimit;
  final BusinessGalleryItem? coverItem;

  factory BusinessGallerySummary.fromJson(Map<String, Object?> json) {
    final quota = json['quota'] is Map
        ? Map<String, Object?>.from(json['quota'] as Map)
        : const <String, Object?>{};
    final cover = json['cover_item'];
    return BusinessGallerySummary(
      items: _mapList(json['items'], BusinessGalleryItem.fromJson),
      categories: _mapList(
        json['categories'],
        BusinessGalleryCategory.fromJson,
      ),
      quotaUsed: _int(quota['used']) ?? 0,
      quotaLimit: _int(quota['limit']) ?? 20,
      coverItem: cover is Map
          ? BusinessGalleryItem.fromJson(Map<String, Object?>.from(cover))
          : null,
    );
  }
}

List<T> _mapList<T>(
  Object? value,
  T Function(Map<String, Object?> json) fromJson,
) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => fromJson(Map<String, Object?>.from(item)))
      .toList();
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
