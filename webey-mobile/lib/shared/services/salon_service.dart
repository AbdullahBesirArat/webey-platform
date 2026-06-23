import '../mock/mock_data.dart';
import '../models/beauty_models.dart';
import 'app_config.dart';
import 'result.dart';

abstract class SalonRepository {
  Future<Result<List<Salon>>> getSalons({
    String? categoryId,
    bool? premiumOnly,
  });

  Future<Result<Salon>> getSalonDetail(String id);

  Future<Result<List<SalonService>>> getSalonServices(String salonId);

  Future<Result<List<StaffMember>>> getSalonStaff(String salonId);
}

class MockSalonRepository implements SalonRepository {
  const MockSalonRepository({AppConfig? config}) : _config = config;

  final AppConfig? _config;

  AppConfig get config => _config ?? AppConfig.current;

  @override
  Future<Result<List<Salon>>> getSalons({
    String? categoryId,
    bool? premiumOnly,
  }) async {
    if (config.enableMockErrors) return Result.fail('Salonlar yüklenemedi.');
    var salons = MockData.salons.where((salon) => salon.isPublished);
    if (categoryId != null) {
      salons = salons.where((salon) => salon.categoryIds.contains(categoryId));
    }
    if (premiumOnly == true) {
      salons = salons.where((salon) => salon.isPremium);
    }
    return Result.ok(salons.toList());
  }

  @override
  Future<Result<Salon>> getSalonDetail(String id) async {
    if (config.enableMockErrors) {
      return Result.fail('Salon detayı yüklenemedi.');
    }
    return Result.ok(MockData.salonById(id));
  }

  @override
  Future<Result<List<SalonService>>> getSalonServices(String salonId) async {
    return Result.ok(MockData.servicesForSalon(salonId));
  }

  @override
  Future<Result<List<StaffMember>>> getSalonStaff(String salonId) async {
    return Result.ok(MockData.staffForSalon(salonId));
  }
}
