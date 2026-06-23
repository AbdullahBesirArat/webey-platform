import '../../../../../core/config/api_config.dart';
import '../../../../../shared/services/api_client.dart';
import '../models/customer_profile.dart';

class CustomerProfileRepository {
  const CustomerProfileRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? const ApiClient();

  static const instance = CustomerProfileRepository();

  final ApiClient _apiClient;

  Future<CustomerProfile?> getProfile() async {
    if (ApiConfig.useMockProfile) {
      return const CustomerProfile(
        id: 'mock_1',
        email: 'ayse.demir@gmail.com',
        fullName: 'Ayşe Demir',
        firstName: 'Ayşe',
        lastName: 'Demir',
        city: 'İstanbul',
        district: 'Kadıköy',
        neighborhood: 'Moda',
        addressLine: 'Moda, Kadıköy',
        latitude: 40.9869,
        longitude: 29.0252,
        stats: CustomerProfileStats(
          appointmentsCount: 24,
          completedCount: 21,
          cancelledCount: 3,
        ),
      );
    }

    try {
      final data = await _apiClient.getData('/customer/profile.php');
      return CustomerProfile.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<CustomerProfile?> saveProfile(Map<String, dynamic> body) async {
    if (ApiConfig.useMockProfile) return getProfile();

    try {
      final data = await _apiClient.postData(
        '/customer/profile-save.php',
        body: body,
      );
      return CustomerProfile.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    await _apiClient.postData('/customer/profile-save.php', body: data);
  }
}
