import '../../../../../core/config/api_config.dart';

class BusinessGalleryItem {
  const BusinessGalleryItem({
    required this.id,
    required this.category,
    required this.categoryLabel,
    this.title,
    this.description,
    this.url = '',
    this.thumbUrl = '',
    this.mediumUrl = '',
    this.largeUrl = '',
    this.width,
    this.height,
    this.bytes,
    this.isCover = false,
    this.isVisible = true,
    this.status = 'active',
    this.sortOrder = 0,
    this.serviceId,
    this.staffId,
    this.pairGroupId,
    this.pairRole,
    this.createdAt,
  });

  final String id;
  final String category;
  final String categoryLabel;
  final String? title;
  final String? description;
  final String url;
  final String thumbUrl;
  final String mediumUrl;
  final String largeUrl;
  final int? width;
  final int? height;
  final int? bytes;
  final bool isCover;
  final bool isVisible;
  final String status;
  final int sortOrder;
  final int? serviceId;
  final int? staffId;
  final String? pairGroupId;
  final String? pairRole;
  final String? createdAt;

  String get displayTitle =>
      (title ?? '').trim().isNotEmpty ? title!.trim() : categoryLabel;

  String get bestUrl {
    for (final value in [mediumUrl, largeUrl, url, thumbUrl]) {
      if (value.trim().isNotEmpty) return value;
    }
    return '';
  }

  String get bestThumbUrl {
    for (final value in [thumbUrl, mediumUrl, url, largeUrl]) {
      if (value.trim().isNotEmpty) return value;
    }
    return '';
  }

  factory BusinessGalleryItem.fromJson(Map<String, Object?> json) {
    return BusinessGalleryItem(
      id: _string(json['id']),
      category: _string(json['category']),
      categoryLabel: _string(json['category_label']).isNotEmpty
          ? _string(json['category_label'])
          : _string(json['category']),
      title: _nullableString(json['title']),
      description: _nullableString(json['description']),
      url: ApiConfig.resolveUrl(_nullableString(json['url'])),
      thumbUrl: ApiConfig.resolveUrl(_nullableString(json['thumb_url'])),
      mediumUrl: ApiConfig.resolveUrl(_nullableString(json['medium_url'])),
      largeUrl: ApiConfig.resolveUrl(_nullableString(json['large_url'])),
      width: _int(json['width']),
      height: _int(json['height']),
      bytes: _int(json['bytes']),
      isCover: _bool(json['is_cover'], fallback: false),
      isVisible: _bool(json['is_visible'], fallback: true),
      status: _string(json['status']).isNotEmpty
          ? _string(json['status'])
          : 'active',
      sortOrder: _int(json['sort_order']) ?? 0,
      serviceId: _int(json['service_id']),
      staffId: _int(json['staff_id']),
      pairGroupId: _nullableString(json['pair_group_id']),
      pairRole: _nullableString(json['pair_role']),
      createdAt: _nullableString(json['created_at']),
    );
  }
}

String _string(Object? value) => value?.toString() ?? '';

String? _nullableString(Object? value) {
  final text = value?.toString() ?? '';
  return text.isEmpty ? null : text;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

bool _bool(Object? value, {required bool fallback}) {
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
