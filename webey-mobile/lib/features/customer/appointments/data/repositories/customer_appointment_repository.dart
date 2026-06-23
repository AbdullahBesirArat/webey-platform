import '../../../../../core/config/api_config.dart';
import '../../../../../shared/mock/mock_data.dart';
import '../../../../../shared/models/beauty_models.dart';
import '../../../../../shared/services/api_client.dart';
import '../models/customer_appointment.dart';

class CustomerAppointmentRepository {
  const CustomerAppointmentRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? const ApiClient();

  static const instance = CustomerAppointmentRepository();

  final ApiClient _apiClient;

  Future<List<Appointment>> getAppointments(String status) async {
    if (ApiConfig.useMockAppointments) {
      return _mockForStatus(status);
    }

    try {
      final data = await _apiClient.getData(
        '/customer/appointments.php?status=$status',
      );
      final items = data['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map(
            (item) => CustomerAppointment.fromJson(
              Map<String, Object?>.from(item),
            ).toAppointment(),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> cancelAppointment(String appointmentId) async {
    if (ApiConfig.useMockAppointments) return true;

    try {
      await _apiClient.postData(
        '/customer/appointments/cancel.php',
        body: {'appointment_id': int.tryParse(appointmentId) ?? 0},
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> previewCancellation(
    String appointmentId,
  ) async {
    if (ApiConfig.useMockAppointments) return null;

    try {
      final data = await _apiClient.postData(
        '/customer/appointments/cancel.php',
        body: {
          'appointment_id': int.tryParse(appointmentId) ?? 0,
          'preview': true,
        },
      );
      final cancellation = data['cancellation'];
      if (cancellation is Map) {
        return cancellation.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Geçmiş/tamamlanmış randevu için değerlendirme gönderir.
  /// Başarısızlıkta [ApiException] fırlatır (çağıran tarafta mesaj gösterilir).
  Future<void> submitReview({
    required String appointmentId,
    required int rating,
    String? comment,
  }) async {
    if (ApiConfig.useMockAppointments) return;

    final trimmed = comment?.trim() ?? '';
    await _apiClient.postData(
      '/customer/reviews.php',
      body: {
        'appointment_id': int.tryParse(appointmentId) ?? 0,
        'rating': rating,
        if (trimmed.isNotEmpty) 'comment': trimmed,
      },
    );
  }

  static List<Appointment> _mockForStatus(String status) {
    final all = MockData.customerAppointments;
    return switch (status) {
      'upcoming' =>
        all
            .where(
              (a) =>
                  a.status == AppointmentStatus.approved ||
                  a.status == AppointmentStatus.pending,
            )
            .toList(),
      'past' =>
        all.where((a) => a.status == AppointmentStatus.completed).toList(),
      'cancelled' =>
        all
            .where(
              (a) =>
                  a.status == AppointmentStatus.cancelled ||
                  a.status == AppointmentStatus.cancellationRequested,
            )
            .toList(),
      _ => all,
    };
  }
}
