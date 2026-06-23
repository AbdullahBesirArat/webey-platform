import '../../../../../core/config/api_config.dart';
import '../../../../../shared/data/turkey_locations.dart';
import '../../../../../shared/mock/mock_data.dart';
import '../../../../../shared/models/beauty_models.dart';
import '../../../../../shared/services/api_client.dart';
import '../models/category_item.dart';
import '../models/paginated_response.dart';
import '../models/salon_detail.dart';
import '../models/salon_summary.dart';
import '../models/search_suggestion.dart';

class CustomerDiscoveryRepository {
  const CustomerDiscoveryRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? const ApiClient();

  static const instance = CustomerDiscoveryRepository();

  final ApiClient _apiClient;

  Future<List<CategoryItem>> getCategories() async {
    if (ApiConfig.useMockDiscovery) {
      return MockData.categories
          .map(
            (category) => CategoryItem(
              id: category.id,
              slug: category.id,
              title: category.label,
              subtitle: category.description,
              icon: category.id,
              sortOrder: 0,
            ),
          )
          .toList();
    }

    try {
      final data = await _apiClient.getData('/public/categories.php');
      final items = data['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map((item) => CategoryItem.fromJson(Map<String, Object?>.from(item)))
          .toList();
    } catch (_) {
      // Fake/sabit kategori gösterilmez: endpoint hatasında bölüm gizlenir.
      return const [];
    }
  }

  Future<PaginatedResponse<SalonSummary>> getSalons({
    String? q,
    String? city,
    String? district,
    String? category,
    String? deposit,
    bool? availableToday,
    bool campaignOnly = false,
    String? campaignType,
    String? campaignKind,
    double? lat,
    double? lng,
    int page = 1,
    int limit = 20,
  }) async {
    if (ApiConfig.useMockDiscovery) {
      var salons = MockData.salons.where((salon) => salon.isPublished);
      if (q != null && q.trim().isNotEmpty) {
        final needle = q.toLowerCase();
        salons = salons.where((salon) {
          return '${salon.name} ${salon.about} ${salon.city} ${salon.district}'
              .toLowerCase()
              .contains(needle);
        });
      }
      if (city != null && city.isNotEmpty) {
        salons = salons.where((salon) => salon.city == city);
      }
      if (district != null && district.isNotEmpty) {
        salons = salons.where((salon) => salon.district == district);
      }
      if (category != null && category.isNotEmpty) {
        salons = salons.where((salon) => salon.categoryIds.contains(category));
      }
      if (availableToday == true) {
        salons = salons.where((salon) => salon.availableToday);
      }
      if (deposit == 'required') {
        salons = salons.where((salon) => salon.acceptsDeposit);
      } else if (deposit == 'none') {
        salons = salons.where((salon) => !salon.acceptsDeposit);
      }
      // Mock veride kampanya yoktur; kampanya filtresi boş sonuç döner.
      if (campaignOnly) {
        salons = salons.where((_) => false);
      }

      final list = salons.toList();
      final start = ((page - 1) * limit).clamp(0, list.length);
      final end = (start + limit).clamp(0, list.length);
      return PaginatedResponse<SalonSummary>(
        items: list.sublist(start, end).map(_summaryFromMock).toList(),
        page: page,
        limit: limit,
        total: list.length,
        hasMore: end < list.length,
      );
    }

    final apiCity = TurkeyLocations.normalizeCityForApi(city);
    final apiDistrict = TurkeyLocations.normalizeDistrictForApi(
      apiCity,
      district,
    );

    final data = await _apiClient.getData(
      _path('/public/salons.php', {
        'q': q,
        'city': apiCity,
        'district': apiDistrict,
        'category': category,
        'deposit': deposit,
        'available_today': availableToday == true ? '1' : null,
        'campaign': campaignOnly ? '1' : null,
        'campaign_type': campaignOnly ? campaignType : null,
        'discount_kind': campaignOnly ? campaignKind : null,
        'lat': lat?.toStringAsFixed(6),
        'lng': lng?.toStringAsFixed(6),
        'page': page,
        'limit': limit,
      }),
    );
    return PaginatedResponse.fromJson(data, SalonSummary.fromJson);
  }

  /// Harita görünümü: sadece koordinatı olan salonları (viewport bounds
  /// opsiyonel) tek istekte çeker. `salons.php?view=map`.
  Future<List<SalonSummary>> getSalonsForMap({
    String? q,
    String? city,
    String? district,
    String? category,
    String? deposit,
    double? lat,
    double? lng,
    double? north,
    double? south,
    double? east,
    double? west,
    int limit = 200,
  }) async {
    if (ApiConfig.useMockDiscovery) {
      final response = await getSalons(
        q: q,
        city: city,
        district: district,
        category: category,
        deposit: deposit,
        limit: limit,
      );
      return response.items
          .where((s) => s.latitude != null && s.longitude != null)
          .toList();
    }

    final apiCity = TurkeyLocations.normalizeCityForApi(city);
    final apiDistrict = TurkeyLocations.normalizeDistrictForApi(
      apiCity,
      district,
    );

    final data = await _apiClient.getData(
      _path('/public/salons.php', {
        'view': 'map',
        'q': q,
        'city': apiCity,
        'district': apiDistrict,
        'category': category,
        'deposit': deposit,
        'lat': lat?.toStringAsFixed(6),
        'lng': lng?.toStringAsFixed(6),
        'north': north?.toStringAsFixed(6),
        'south': south?.toStringAsFixed(6),
        'east': east?.toStringAsFixed(6),
        'west': west?.toStringAsFixed(6),
        'limit': limit,
      }),
    );
    final items = data['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) => SalonSummary.fromJson(Map<String, Object?>.from(item)))
        .where((s) => s.latitude != null && s.longitude != null)
        .toList();
  }

  Future<SalonDetail> getSalonDetail({int? id, String? slug}) async {
    if (ApiConfig.useMockDiscovery) {
      final salon = id != null
          ? MockData.salonById('$id')
          : MockData.salons.firstWhere(
              (item) => item.id == slug,
              orElse: () => MockData.salons.first,
            );
      return _detailFromMock(salon);
    }

    final data = await _apiClient.getData(
      _path('/public/salon-detail.php', {'id': id, 'slug': slug}),
    );
    return SalonDetail.fromJson(data);
  }

  Future<List<SearchSuggestion>> suggest(String q) async {
    if (q.trim().isEmpty) return const [];
    if (ApiConfig.useMockDiscovery) {
      final needle = q.toLowerCase();
      return MockData.salons
          .where((salon) => salon.name.toLowerCase().contains(needle))
          .take(8)
          .map(
            (salon) => SearchSuggestion(
              type: 'salon',
              title: salon.name,
              subtitle: '${salon.district} / ${salon.city}',
              id: salon.id,
              slug: salon.id,
            ),
          )
          .toList();
    }

    final data = await _apiClient.getData(
      _path('/public/suggest.php', {'q': q}),
    );
    final items = data['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) => SearchSuggestion.fromJson(Map<String, Object?>.from(item)),
        )
        .toList();
  }

  String _path(String path, Map<String, Object?> query) {
    final params = <String, String>{};
    for (final entry in query.entries) {
      final value = entry.value;
      if (value == null) continue;
      final text = value.toString();
      if (text.isEmpty) continue;
      params[entry.key] = text;
    }
    final encoded = Uri(queryParameters: params).query;
    return encoded.isEmpty ? path : '$path?$encoded';
  }

  SalonSummary _summaryFromMock(Salon salon) {
    return SalonSummary(
      id: salon.id,
      slug: salon.id,
      name: salon.name,
      description: salon.description ?? salon.about,
      city: salon.city,
      district: salon.district,
      address: salon.address,
      coverImageUrl: salon.coverImage,
      rating: salon.rating,
      reviewCount: salon.reviewCount,
      minPrice: salon.minPrice,
      maxPrice: salon.maxPrice,
      depositRequired: salon.acceptsDeposit,
      depositAmount: salon.depositAmount,
      isOpenNow: salon.availableToday,
      nextAvailableText: salon.campaign,
      badges: salon.trustBadges,
      categorySlugs: salon.categoryIds,
      distanceKm: salon.distanceKm,
    );
  }

  SalonDetail _detailFromMock(Salon salon) {
    return SalonDetail(
      salon: _summaryFromMock(salon),
      gallery: salon.galleryImages,
      services: MockData.servicesForSalon(salon.id)
          .map(
            (service) => SalonServiceDetail(
              id: service.id,
              name: service.name,
              durationMin: service.durationMin,
              price: service.price,
              description: service.description,
            ),
          )
          .toList(),
      staff: MockData.staffForSalon(salon.id)
          .map(
            (staff) => SalonStaffDetail(
              id: staff.id,
              name: staff.name,
              phone: staff.phone,
              color:
                  '#${staff.color.toARGB32().toRadixString(16).padLeft(8, '0')}',
              isActive: staff.isActive,
            ),
          )
          .toList(),
      businessHours: salon.workingHours.entries
          .map(
            (entry) => BusinessHourDetail(
              day: entry.key,
              isOpen: !entry.value.toLowerCase().contains('kapalı'),
              openTime: entry.value,
            ),
          )
          .toList(),
      reviewSummary: ReviewSummaryDetail(
        rating: salon.rating,
        reviewCount: salon.reviewCount,
      ),
      depositPolicy: DepositPolicyDetail(
        required: salon.acceptsDeposit,
        amount: salon.depositAmount,
        description: salon.cancellationPolicy,
      ),
    );
  }
}
