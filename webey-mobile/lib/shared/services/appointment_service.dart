import '../mock/mock_data.dart';
import '../models/beauty_models.dart';
import 'app_logger.dart';
import 'result.dart';

abstract class AppointmentRepository {
  Future<Result<List<Appointment>>> getMyAppointments();

  Future<Result<Appointment>> createAppointment({
    required Salon salon,
    required SalonService service,
    StaffMember? staff,
    required DateTime date,
    required String slot,
  });

  Future<Result<void>> cancelAppointment(String appointmentId, {String reason});

  Future<Result<void>> requestReschedule(
    String appointmentId, {
    required DateTime newDate,
    required String newSlot,
  });
}

class MockAppointmentRepository implements AppointmentRepository {
  const MockAppointmentRepository();

  @override
  Future<Result<List<Appointment>>> getMyAppointments() async {
    return Result.ok(MockData.customerAppointments);
  }

  @override
  Future<Result<Appointment>> createAppointment({
    required Salon salon,
    required SalonService service,
    StaffMember? staff,
    required DateTime date,
    required String slot,
  }) async {
    if (slot.isEmpty) return Result.fail('Tarih ve saat seçilmelidir.');
    final appointment = Appointment(
      id: 'appt_mock_${DateTime.now().millisecondsSinceEpoch}',
      businessId: salon.id,
      salonName: salon.name,
      customerName: 'Ayşe Demir',
      serviceName: service.name,
      staffName: staff?.name ?? 'Fark etmez',
      startAt: date,
      endAt: date.add(Duration(minutes: service.durationMin)),
      status: AppointmentStatus.approved,
      depositStatus: salon.acceptsDeposit
          ? DepositStatus.paid
          : DepositStatus.none,
      depositAmount: salon.acceptsDeposit ? salon.depositAmount : 0,
      total: service.price,
      bookingSource: 'app',
    );
    AppLogger.info('Mock appointment created: ${appointment.id}');
    return Result.ok(appointment);
  }

  @override
  Future<Result<void>> cancelAppointment(
    String appointmentId, {
    String reason = '',
  }) async {
    AppLogger.info('Mock appointment cancellation requested: $appointmentId');
    return Result.empty();
  }

  @override
  Future<Result<void>> requestReschedule(
    String appointmentId, {
    required DateTime newDate,
    required String newSlot,
  }) async {
    AppLogger.info('Mock appointment reschedule requested: $appointmentId');
    return Result.empty();
  }
}
