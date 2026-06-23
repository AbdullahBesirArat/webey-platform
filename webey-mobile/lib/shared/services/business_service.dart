import '../mock/mock_data.dart';
import '../models/beauty_models.dart';
import 'app_logger.dart';
import 'result.dart';

class BusinessDashboardData {
  const BusinessDashboardData({
    required this.appointments,
    required this.analytics,
    required this.noShowProtection,
    required this.actions,
  });

  final List<Appointment> appointments;
  final BusinessAnalyticsSummary analytics;
  final NoShowProtectionSummary noShowProtection;
  final List<BusinessActionItem> actions;
}

abstract class BusinessRepository {
  Future<Result<BusinessDashboardData>> getDashboard();

  Future<Result<List<Appointment>>> getBusinessAppointments();

  Future<Result<void>> updateDepositSettings(DepositSettings settings);

  Future<Result<List<BusinessCustomer>>> getCustomers();

  Future<Result<BusinessAnalyticsSummary>> getAnalytics();
}

class MockBusinessRepository implements BusinessRepository {
  const MockBusinessRepository();

  @override
  Future<Result<BusinessDashboardData>> getDashboard() async {
    return Result.ok(
      BusinessDashboardData(
        appointments: MockData.businessAppointments,
        analytics: MockData.analyticsSummary,
        noShowProtection: MockData.noShowProtection,
        actions: MockData.businessActions,
      ),
    );
  }

  @override
  Future<Result<List<Appointment>>> getBusinessAppointments() async {
    return Result.ok(MockData.businessAppointments);
  }

  @override
  Future<Result<void>> updateDepositSettings(DepositSettings settings) async {
    if (settings.acceptsDeposit && settings.depositAmount <= 0) {
      return Result.fail('Kapora tutarı 0 veya negatif olamaz.');
    }
    AppLogger.info('Mock deposit settings updated');
    return Result.empty();
  }

  @override
  Future<Result<List<BusinessCustomer>>> getCustomers() async {
    return Result.ok(MockData.businessCustomers);
  }

  @override
  Future<Result<BusinessAnalyticsSummary>> getAnalytics() async {
    return Result.ok(MockData.analyticsSummary);
  }
}
