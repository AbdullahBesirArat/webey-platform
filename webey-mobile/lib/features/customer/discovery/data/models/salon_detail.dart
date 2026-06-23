import '../../../../../core/config/api_config.dart';
import 'salon_campaign.dart';
import 'salon_summary.dart';

class SalonDetail {
  const SalonDetail({
    required this.salon,
    this.gallery = const [],
    this.galleryPhotos = const [],
    this.galleryTotal = 0,
    this.coverPhoto,
    this.services = const [],
    this.staff = const [],
    this.businessHours = const [],
    this.reviews = const [],
    required this.reviewSummary,
    required this.depositPolicy,
    this.location,
    this.campaign,
  });

  final SalonSummary salon;

  /// Legacy düz URL listesi (eski istemciler için korunan alan).
  final List<String> gallery;

  /// Tek kaynaklı galeri (business_photos): boyut varyantlı gerçek fotoğraflar.
  final List<SalonGalleryPhoto> galleryPhotos;

  /// Gerçek toplam fotoğraf sayısı (+N hesabı bunu kullanır).
  final int galleryTotal;

  /// İşletmenin seçtiği aktif kapak; yoksa null (customer fallback gösterir).
  final SalonGalleryPhoto? coverPhoto;
  final List<SalonServiceDetail> services;
  final List<SalonStaffDetail> staff;
  final List<BusinessHourDetail> businessHours;
  final List<SalonReviewDetail> reviews;
  final ReviewSummaryDetail reviewSummary;
  final DepositPolicyDetail depositPolicy;
  final SalonLocationDetail? location;

  /// Aktif (şu an geçerli) kampanya; yoksa null (detay bandı gizlenir).
  final SalonCampaign? campaign;

  factory SalonDetail.fromJson(Map<String, Object?> json) {
    final salonJson = json['salon'];
    return SalonDetail(
      salon: salonJson is Map
          ? SalonSummary.fromJson(Map<String, Object?>.from(salonJson))
          : const SalonSummary(id: '', slug: '', name: ''),
      gallery: _stringList(
        json['gallery'],
      ).map(ApiConfig.resolveUrl).where((url) => url.isNotEmpty).toList(),
      galleryPhotos: _galleryPhotosFromJson(json),
      galleryTotal: _galleryTotalFromJson(json),
      coverPhoto: json['cover_photo'] is Map
          ? SalonGalleryPhoto.fromJson(_map(json['cover_photo']))
          : null,
      services: _mapList(json['services'], SalonServiceDetail.fromJson),
      staff: _mapList(json['staff'], SalonStaffDetail.fromJson),
      businessHours: _mapList(
        json['business_hours'],
        BusinessHourDetail.fromJson,
      ),
      reviews: _mapList(json['reviews'], SalonReviewDetail.fromJson),
      reviewSummary: ReviewSummaryDetail.fromJson(_map(json['review_summary'])),
      depositPolicy: DepositPolicyDetail.fromJson(_map(json['deposit_policy'])),
      location: json['location'] is Map
          ? SalonLocationDetail.fromJson(_map(json['location']))
          : null,
      campaign: SalonCampaign.fromJson(json['campaign']),
    );
  }

  static Map<String, Object?> _map(Object? value) {
    return value is Map ? Map<String, Object?>.from(value) : {};
  }

  /// Yeni `gallery_items` alanı varsa onu kullanır; eski backend'de
  /// (alan yoksa) legacy `gallery` URL listesinden türetir.
  static List<SalonGalleryPhoto> _galleryPhotosFromJson(
    Map<String, Object?> json,
  ) {
    if (json['gallery_items'] is List) {
      return _mapList(json['gallery_items'], SalonGalleryPhoto.fromJson);
    }
    return _stringList(json['gallery'])
        .map(ApiConfig.resolveUrl)
        .where((url) => url.isNotEmpty)
        .map(
          (url) => SalonGalleryPhoto(
            id: '',
            thumbUrl: url,
            mediumUrl: url,
            largeUrl: url,
          ),
        )
        .toList();
  }

  static int _galleryTotalFromJson(Map<String, Object?> json) {
    final total = json['gallery_total'];
    if (total is int) return total;
    final parsed = int.tryParse(total?.toString() ?? '');
    if (parsed != null) return parsed;
    return _galleryPhotosFromJson(json).length;
  }

  static List<T> _mapList<T>(
    Object? value,
    T Function(Map<String, Object?> json) fromJson,
  ) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => fromJson(Map<String, Object?>.from(item)))
        .toList();
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}

class SalonReviewDetail {
  const SalonReviewDetail({
    required this.id,
    required this.customerName,
    required this.rating,
    this.comment,
    this.serviceName,
    this.staffName,
    this.createdAt,
  });

  final String id;
  final String customerName;
  final int rating;
  final String? comment;
  final String? serviceName;
  final String? staffName;
  final DateTime? createdAt;

  factory SalonReviewDetail.fromJson(Map<String, Object?> json) {
    return SalonReviewDetail(
      id: _string(json['id']),
      customerName: _string(json['customer_name']),
      rating: _int(json['rating']) ?? 0,
      comment: _nullableString(json['comment']),
      serviceName: _nullableString(json['service_name']),
      staffName: _nullableString(json['staff_name']),
      createdAt: DateTime.tryParse(_string(json['created_at'])),
    );
  }
}

/// business_photos kaynaklı tek fotoğraf (boyut varyantlarıyla).
class SalonGalleryPhoto {
  const SalonGalleryPhoto({
    required this.id,
    required this.thumbUrl,
    required this.mediumUrl,
    required this.largeUrl,
    this.category,
    this.caption,
    this.isCover = false,
  });

  final String id;
  final String thumbUrl;
  final String mediumUrl;
  final String largeUrl;
  final String? category;
  final String? caption;
  final bool isCover;

  factory SalonGalleryPhoto.fromJson(Map<String, Object?> json) {
    String resolve(Object? value) =>
        ApiConfig.resolveUrl(value?.toString() ?? '');
    final thumb = resolve(json['thumb_url']);
    final medium = resolve(json['medium_url']);
    final large = resolve(json['large_url']);
    return SalonGalleryPhoto(
      id: json['id']?.toString() ?? '',
      thumbUrl: thumb.isNotEmpty ? thumb : (medium.isNotEmpty ? medium : large),
      mediumUrl: medium.isNotEmpty
          ? medium
          : (large.isNotEmpty ? large : thumb),
      largeUrl: large.isNotEmpty ? large : (medium.isNotEmpty ? medium : thumb),
      category: json['category']?.toString(),
      caption: json['caption']?.toString(),
      isCover: json['is_cover'] == true,
    );
  }
}

class SalonServiceDetail {
  const SalonServiceDetail({
    required this.id,
    required this.name,
    this.durationMin,
    this.price,
    this.description,
    this.categoryId,
    this.categoryName,
    this.categorySlug,
    this.isCustomCategory = false,
  });

  final String id;
  final String name;
  final int? durationMin;
  final double? price;
  final String? description;
  final int? categoryId;
  final String? categoryName;
  final String? categorySlug;
  final bool isCustomCategory;

  /// Gruplama anahtarı: kategorisiz hizmetler "Diğer Hizmetler" altında toplanır.
  String get categoryKey => categoryId != null
      ? (isCustomCategory ? 'business_$categoryId' : 'system_$categoryId')
      : 'uncategorized';

  String get categoryLabel => (categoryName == null || categoryName!.isEmpty)
      ? 'Diğer Hizmetler'
      : categoryName!;

  factory SalonServiceDetail.fromJson(Map<String, Object?> json) {
    return SalonServiceDetail(
      id: _string(json['id']),
      name: _string(json['name']),
      durationMin: _int(json['duration_min']),
      price: _double(json['price']),
      description: _nullableString(json['description']),
      categoryId: _int(json['category_id']),
      categoryName: _nullableString(json['category_name']),
      categorySlug: _nullableString(json['category_slug']),
      isCustomCategory: json['is_custom_category'] == true,
    );
  }
}

class SalonStaffDetail {
  const SalonStaffDetail({
    required this.id,
    required this.name,
    this.phone,
    this.color,
    this.isActive = true,
    this.rating,
    this.reviewCount = 0,
    this.profilePhotoUrl,
    this.profilePhotoVersion,
  });

  final String id;
  final String name;
  final String? phone;
  final String? color;
  final bool isActive;
  final double? rating;
  final int reviewCount;
  final String? profilePhotoUrl;
  final String? profilePhotoVersion;

  factory SalonStaffDetail.fromJson(Map<String, Object?> json) {
    return SalonStaffDetail(
      id: _string(json['id']),
      name: _string(json['name']),
      phone: _nullableString(json['phone']),
      color: _nullableString(json['color']),
      isActive: json['is_active'] != false,
      rating: _double(json['rating']),
      reviewCount: _int(json['review_count']) ?? 0,
      profilePhotoUrl: ApiConfig.resolveUrl(
        _nullableString(json['profile_photo_url']),
      ),
      profilePhotoVersion: _nullableString(json['profile_photo_version']),
    );
  }
}

class BusinessHourDetail {
  const BusinessHourDetail({
    required this.day,
    required this.isOpen,
    this.openTime,
    this.closeTime,
  });

  final String day;
  final bool isOpen;
  final String? openTime;
  final String? closeTime;

  factory BusinessHourDetail.fromJson(Map<String, Object?> json) {
    return BusinessHourDetail(
      day: _string(json['day']),
      isOpen: json['is_open'] == true,
      openTime: _nullableString(json['open_time']),
      closeTime: _nullableString(json['close_time']),
    );
  }
}

class ReviewSummaryDetail {
  const ReviewSummaryDetail({this.rating, this.reviewCount = 0});

  final double? rating;
  final int reviewCount;

  factory ReviewSummaryDetail.fromJson(Map<String, Object?> json) {
    return ReviewSummaryDetail(
      rating: _double(json['rating']),
      reviewCount: _int(json['review_count']) ?? 0,
    );
  }
}

class DepositPolicyDetail {
  const DepositPolicyDetail({
    required this.required,
    this.amount,
    this.ratePct,
    this.description,
    this.hasIban = false,
    this.iban,
    this.ibanFormatted,
    this.accountHolder,
    this.bankName,
    this.instructions,
  });

  final bool required;
  final double? amount;

  /// Salon kapora oranı (% — 25/50/75/100). Booking ekranında gerçek tutarı
  /// hesaplamak için kullanılır; hardcoded oran kullanılmaz.
  final int? ratePct;
  final String? description;

  // Manuel IBAN kapora bilgileri (booking onay ekranında önizleme için).
  final bool hasIban;
  final String? iban;
  final String? ibanFormatted;
  final String? accountHolder;
  final String? bankName;
  final String? instructions;

  factory DepositPolicyDetail.fromJson(Map<String, Object?> json) {
    return DepositPolicyDetail(
      required: json['required'] == true,
      amount: _double(json['amount']),
      ratePct: _int(json['rate_pct']),
      description: _nullableString(json['description']),
      hasIban: json['has_iban'] == true,
      iban: _nullableString(json['iban']),
      ibanFormatted: _nullableString(json['iban_formatted']),
      accountHolder: _nullableString(json['account_holder']),
      bankName: _nullableString(json['bank_name']),
      instructions: _nullableString(json['instructions']),
    );
  }
}

class SalonLocationDetail {
  const SalonLocationDetail({
    this.city,
    this.district,
    this.address,
    this.latitude,
    this.longitude,
    this.mapUrl,
  });

  final String? city;
  final String? district;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? mapUrl;

  factory SalonLocationDetail.fromJson(Map<String, Object?> json) {
    return SalonLocationDetail(
      city: _nullableString(json['city']),
      district: _nullableString(json['district']),
      address: _nullableString(json['address']),
      latitude: _double(json['latitude']),
      longitude: _double(json['longitude']),
      mapUrl: _nullableString(json['map_url']),
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
  return int.tryParse(value?.toString() ?? '');
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
