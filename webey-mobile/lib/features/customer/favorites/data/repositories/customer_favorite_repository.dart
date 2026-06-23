import '../../../../../shared/services/api_client.dart';
import '../../../discovery/data/models/salon_summary.dart';

class CustomerFavoriteRepository {
  const CustomerFavoriteRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? const ApiClient();

  static const instance = CustomerFavoriteRepository();

  final ApiClient _apiClient;

  Future<List<SalonSummary>> getFavorites({double? lat, double? lng}) async {
    try {
      final path = _path('/customer/favorites.php', {
        'lat': lat?.toStringAsFixed(6),
        'lng': lng?.toStringAsFixed(6),
      });
      final data = await _apiClient.getData(path);
      final items = data['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map((item) => SalonSummary.fromJson(Map<String, Object?>.from(item)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> toggleFavorite({
    required String businessId,
    required bool favorite,
  }) async {
    try {
      await _apiClient.postData(
        '/customer/favorite-toggle.php',
        body: {
          'business_id': int.tryParse(businessId) ?? 0,
          'favorite': favorite,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> checkIsFavorite(String businessId) async {
    try {
      final data = await _apiClient.getData(
        '/customer/favorite-check.php?business_id=${Uri.encodeQueryComponent(businessId)}',
      );
      return data['is_favorite'] == true;
    } catch (_) {
      return false;
    }
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
}
