import '../../../../../core/config/api_config.dart';
import 'salon_campaign.dart';

class SalonSummary {
  const SalonSummary({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    this.atelierNote,
    this.city,
    this.district,
    this.address,
    this.phone,
    this.coverImageUrl = '',
    this.logoUrl = '',
    this.rating,
    this.reviewCount = 0,
    this.minPrice,
    this.maxPrice,
    this.depositRequired = false,
    this.depositAmount,
    this.isOpenNow = false,
    this.nextAvailableText,
    this.badges = const [],
    this.categorySlugs = const [],
    this.isBoosted = false,
    this.boostBadge,
    this.boostEndsAt,
    this.subscriptionStatus,
    this.visibilityStatus,
    this.profileQualityScore = 0,
    this.distanceKm,
    this.latitude,
    this.longitude,
    this.campaign,
  });

  final String id;
  final String slug;
  final String name;
  final String? description;
  final String? atelierNote;
  final String? city;
  final String? district;
  final String? address;
  final String? phone;
  final String coverImageUrl;
  final String logoUrl;
  final double? rating;
  final int reviewCount;
  final double? minPrice;
  final double? maxPrice;
  final bool depositRequired;
  final double? depositAmount;
  final bool isOpenNow;
  final String? nextAvailableText;
  final List<String> badges;
  final List<String> categorySlugs;
  final bool isBoosted;
  final String? boostBadge;
  final DateTime? boostEndsAt;
  final String? subscriptionStatus;
  final String? visibilityStatus;
  final int profileQualityScore;
  final double? distanceKm;
  final double? latitude;
  final double? longitude;

  /// Aktif (şu an geçerli) vitrin kampanyası; yoksa null.
  final SalonCampaign? campaign;

  bool get hasCampaign => campaign != null;

  factory SalonSummary.fromJson(Map<String, Object?> json) {
    final priceLevel = json['price_level'];
    final priceMap = priceLevel is Map
        ? Map<String, Object?>.from(priceLevel)
        : const <String, Object?>{};

    return SalonSummary(
      id: _string(json['id']),
      slug: _string(json['slug']),
      name: _string(json['name']),
      description: _nullableString(json['description']),
      atelierNote: _nullableString(json['atelier_note']),
      city: _nullableString(json['city']),
      district: _nullableString(json['district']),
      address: _nullableString(json['address']),
      phone: _nullableString(json['phone']),
      coverImageUrl: ApiConfig.resolveUrl(
        _nullableString(json['cover_image_url']),
      ),
      logoUrl: ApiConfig.resolveUrl(_nullableString(json['logo_url'])),
      rating: _double(json['rating']),
      reviewCount: _int(json['review_count']),
      minPrice: _double(priceMap['min']),
      maxPrice: _double(priceMap['max']),
      depositRequired: json['deposit_required'] == true,
      depositAmount: _double(json['deposit_amount']),
      isOpenNow: json['is_open_now'] == true,
      nextAvailableText: _nullableString(json['next_available_text']),
      badges: _stringList(json['badges']),
      categorySlugs: _stringList(json['category_slugs']),
      isBoosted: _bool(json['is_boosted']),
      boostBadge: _nullableString(json['boost_badge']),
      boostEndsAt: DateTime.tryParse(_nullableString(json['boost_ends_at']) ?? ''),
      subscriptionStatus: _nullableString(json['subscription_status']),
      visibilityStatus: _nullableString(json['visibility_status']),
      profileQualityScore: _int(json['profile_quality_score']),
      distanceKm: _double(json['distance_km']),
      latitude: _double(json['latitude']),
      longitude: _double(json['longitude']),
      campaign: SalonCampaign.fromJson(json['campaign']),
    );
  }

  static String _string(Object? value) => value?.toString() ?? '';

  static String? _nullableString(Object? value) {
    final text = value?.toString() ?? '';
    return text.isEmpty ? null : text;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().toLowerCase().trim();
    return text == '1' || text == 'true' || text == 'yes' || text == 'on';
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
