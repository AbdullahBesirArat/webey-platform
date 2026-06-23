import '../../../../../core/config/api_config.dart';
import '../../../../../shared/services/api_client.dart';
import '../models/customer_review_item.dart';

class CustomerReviewRepository {
  const CustomerReviewRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? const ApiClient();

  static const instance = CustomerReviewRepository();

  final ApiClient _apiClient;

  Future<List<CustomerReviewItem>> getMyReviews() async {
    if (ApiConfig.useMockProfile) return const [];

    try {
      final data = await _apiClient.getData('/customer/my-reviews.php');
      final items = data['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map(
            (item) =>
                CustomerReviewItem.fromJson(Map<String, Object?>.from(item)),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
