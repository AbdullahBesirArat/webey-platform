import 'package:flutter/foundation.dart';

import '../../../../../core/config/api_config.dart';
import '../../../../../shared/services/api_client.dart';
import '../../../../../shared/services/result.dart';
import '../booking_date_format.dart';
import '../models/booking_models.dart';
import '../models/deposit_payment_models.dart';

class BookingRepository {
  const BookingRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? const ApiClient();

  static const instance = BookingRepository();

  final ApiClient _apiClient;

  Future<Result<BookingAvailabilityResult>> getAvailability({
    required int businessId,
    required int serviceId,
    required DateTime date,
    int? staffId,
    required int durationMinutes,
  }) async {
    if (ApiConfig.useMockBooking) {
      return Result.ok(
        _mockAvailability(
          businessId: businessId,
          serviceId: serviceId,
          date: date,
          staffId: staffId,
          durationMinutes: durationMinutes,
        ),
      );
    }

    try {
      final dateStr = BookingDateFormat.dateOnly(date);
      final query = <String, String>{
        'business_id': '$businessId',
        'service_id': '$serviceId',
        'date': dateStr,
        'duration_minutes': '$durationMinutes',
        if (staffId != null) 'staff_id': '$staffId',
      };
      final qs = query.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final data = await _apiClient.getData('/booking/availability.php?$qs');
      return Result.ok(BookingAvailabilityResult.fromJson(data));
    } on ApiException catch (error) {
      return Result.fail(error.message, statusCode: error.statusCode);
    } catch (_) {
      return Result.fail('Müsait saatler yüklenemedi. Lütfen tekrar deneyin.');
    }
  }

  Future<Result<BookingLockResult>> lockSlot({
    required int businessId,
    required int serviceId,
    required String startsAt,
    int? staffId,
    required int durationMinutes,
  }) async {
    if (ApiConfig.useMockBooking) {
      return Result.ok(
        _mockLock(startsAt: startsAt, durationMinutes: durationMinutes),
      );
    }

    try {
      final body = <String, Object?>{
        'business_id': businessId,
        'service_id': serviceId,
        'starts_at': startsAt,
        'duration_minutes': durationMinutes,
        'staff_id': ?staffId,
      };
      final data = await _apiClient.postData('/booking/lock.php', body: body);
      return Result.ok(BookingLockResult.fromJson(data));
    } on ApiException catch (error) {
      final message = error.statusCode == 409 || error.statusCode == 422
          ? 'Bu saat artık müsait değil. Lütfen başka bir saat seçin.'
          : error.message;
      return Result.fail(message, statusCode: error.statusCode);
    } catch (_) {
      return Result.fail(
        'Bu saat artık müsait değil. Lütfen başka bir saat seçin.',
      );
    }
  }

  Future<Result<void>> unlockSlot({required String lockToken}) async {
    if (ApiConfig.useMockBooking) {
      return Result.empty();
    }

    try {
      await _apiClient.postData(
        '/booking/unlock.php',
        body: {'lock_token': lockToken},
      );
      return Result.empty();
    } catch (_) {
      return Result.empty();
    }
  }

  Future<Result<BookingResult>> bookAppointment({
    required int businessId,
    required int serviceId,
    required String startsAt,
    int? staffId,
    required int durationMinutes,
    String? lockToken,
    String? notes,
    bool depositSent = false,
    String? depositReferenceCode,
  }) async {
    if (ApiConfig.useMockBooking) {
      return Result.ok(
        _mockBook(
          businessId: businessId,
          serviceId: serviceId,
          startsAt: startsAt,
          staffId: staffId,
          durationMinutes: durationMinutes,
        ),
      );
    }

    try {
      final body = <String, Object?>{
        'business_id': businessId,
        'service_id': serviceId,
        'starts_at': startsAt,
        'duration_minutes': durationMinutes,
        'staff_id': ?staffId,
        'lock_token': ?(lockToken != null && lockToken.isNotEmpty
            ? lockToken
            : null),
        'notes': ?(notes != null && notes.isNotEmpty ? notes : null),
        // Manuel IBAN akışı: müşteri "IBAN'a parayı attım" dedi; randevu bu
        // çağrıda customer_marked_sent ile oluşur. Aday açıklama kodu
        // backend'de doğrulanır/benzersizleştirilir.
        'deposit_sent': ?(depositSent ? true : null),
        'deposit_reference_code':
            ?(depositReferenceCode != null && depositReferenceCode.isNotEmpty
            ? depositReferenceCode
            : null),
      };
      final data = await _apiClient.postData('/booking/book.php', body: body);
      debugPrint('[BookingRepository] bookAppointment success: $data');
      return Result.ok(BookingResult.fromJson(data));
    } on ApiException catch (error) {
      final message = error.isUnauthorized
          ? 'Randevu oluşturmak için giriş yapmanız gerekiyor.'
          : (error.code == 'iban_missing'
                ? 'Salonun kapora ödeme bilgileri eksik. Lütfen daha sonra tekrar deneyin.'
                : (error.statusCode == 409
                      ? 'Bu saat artık müsait değil. Lütfen başka bir saat seçin.'
                      : 'Randevu oluşturulamadı. Lütfen tekrar deneyin.'));
      return Result.fail(message, statusCode: error.statusCode);
    } catch (_) {
      return Result.fail('Randevu oluşturulamadı. Lütfen tekrar deneyin.');
    }
  }

  Future<Result<DepositStartResult>> startDepositPayment({
    required int appointmentId,
  }) async {
    if (ApiConfig.useMockBooking) {
      return Result.ok(_mockDepositStart(appointmentId: appointmentId));
    }

    try {
      final data = await _apiClient.postData(
        '/payments/deposit/start.php',
        body: {'appointment_id': appointmentId},
      );
      return Result.ok(DepositStartResult.fromJson(data));
    } on ApiException catch (error) {
      return Result.fail(error.message, statusCode: error.statusCode);
    } catch (_) {
      return Result.fail('Ödeme başlatılamadı. Lütfen tekrar deneyin.');
    }
  }

  /// Manuel IBAN kapora: müşteri "IBAN'a yolladım" der.
  /// Randevunun deposit_status'unu 'customer_marked_sent' yapar ve işletmeye
  /// bildirim gönderir. İyzico/online ödeme akışını etkilemez.
  Future<Result<String>> markDepositSent({required int appointmentId}) async {
    if (ApiConfig.useMockBooking) {
      return Result.ok('customer_marked_sent');
    }

    try {
      final data = await _apiClient.postData(
        '/customer/appointments/deposit-sent.php',
        body: {'appointment_id': appointmentId},
      );
      final status =
          data['deposit_status']?.toString() ?? 'customer_marked_sent';
      return Result.ok(status);
    } on ApiException catch (error) {
      return Result.fail(error.message, statusCode: error.statusCode);
    } catch (_) {
      return Result.fail(
        'Ödeme bildirimi gönderilemedi. Lütfen tekrar deneyin.',
      );
    }
  }

  Future<Result<DepositStatusResult>> getDepositStatus({
    required int appointmentId,
  }) async {
    if (ApiConfig.useMockBooking) {
      return Result.ok(_mockDepositStatus(appointmentId: appointmentId));
    }

    try {
      final data = await _apiClient.getData(
        '/payments/deposit/status.php?appointment_id=$appointmentId',
      );
      return Result.ok(DepositStatusResult.fromJson(data));
    } on ApiException catch (error) {
      return Result.fail(error.message, statusCode: error.statusCode);
    } catch (_) {
      return Result.fail('Ödeme durumu alınamadı.');
    }
  }

  static BookingAvailabilityResult _mockAvailability({
    required int businessId,
    required int serviceId,
    required DateTime date,
    int? staffId,
    required int durationMinutes,
  }) {
    final dateStr = BookingDateFormat.dateOnly(date);
    final times = <String>[
      '09:00',
      '09:30',
      '10:30',
      '11:30',
      '12:00',
      '13:30',
      '14:00',
      '15:00',
      '16:30',
      '17:30',
      '18:00',
      '19:00',
    ];
    const unavailable = {'12:00', '19:00'};
    final items = times.map((time) {
      final parts = time.split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final endTotal = h * 60 + m + durationMinutes;
      final eh = endTotal ~/ 60;
      final em = endTotal % 60;
      return BookingAvailabilitySlot(
        time: time,
        startsAt: '$dateStr ${parts[0]}:${parts[1]}:00',
        endsAt:
            '$dateStr ${eh.toString().padLeft(2, '0')}:${em.toString().padLeft(2, '0')}:00',
        available: !unavailable.contains(time),
      );
    }).toList();

    return BookingAvailabilityResult(
      date: dateStr,
      businessId: businessId,
      serviceId: serviceId,
      staffId: staffId,
      durationMinutes: durationMinutes,
      items: items,
    );
  }

  static BookingLockResult _mockLock({
    required String startsAt,
    required int durationMinutes,
  }) {
    final day = startsAt.length >= 10 ? startsAt.substring(0, 10) : startsAt;
    final timePart = startsAt.length >= 16
        ? startsAt.substring(11, 16)
        : '10:00';
    final parts = timePart.split(':');
    final h = int.tryParse(parts[0]) ?? 10;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final endTotal = h * 60 + m + durationMinutes;
    final eh = endTotal ~/ 60;
    final em = endTotal % 60;
    final expires = DateTime.now().add(const Duration(minutes: 5));
    return BookingLockResult(
      locked: true,
      lockToken: 'a' * 48,
      expiresAt: BookingDateFormat.dateTime(expires),
      expiresIn: 300,
      startsAt: startsAt,
      endsAt:
          '$day ${eh.toString().padLeft(2, '0')}:${em.toString().padLeft(2, '0')}:00',
    );
  }

  static BookingResult _mockBook({
    required int businessId,
    required int serviceId,
    required String startsAt,
    int? staffId,
    required int durationMinutes,
  }) {
    final day = startsAt.length >= 10 ? startsAt.substring(0, 10) : startsAt;
    final timePart = startsAt.length >= 16
        ? startsAt.substring(11, 16)
        : '10:00';
    final parts = timePart.split(':');
    final h = int.tryParse(parts[0]) ?? 10;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final endTotal = h * 60 + m + durationMinutes;
    final eh = endTotal ~/ 60;
    final em = endTotal % 60;
    return BookingResult(
      appointmentId: '900001',
      status: 'pending',
      startsAt: startsAt,
      endsAt:
          '$day ${eh.toString().padLeft(2, '0')}:${em.toString().padLeft(2, '0')}:00',
      businessId: businessId,
      serviceId: serviceId,
      staffId: staffId,
      depositRequired: true,
      depositAmount: 150.0,
    );
  }

  static DepositStartResult _mockDepositStart({required int appointmentId}) {
    final token = 'dep_checkout_mock${appointmentId}abcdef';
    return DepositStartResult(
      appointmentId: appointmentId,
      alreadyPaid: false,
      depositRequired: true,
      amount: 150.0,
      checkoutToken: token,
      checkoutUrl: 'https://sandbox-cpp.iyzipay.com/?token=$token',
    );
  }

  static DepositStatusResult _mockDepositStatus({required int appointmentId}) {
    return DepositStatusResult(
      appointmentId: appointmentId,
      depositStatus: 'paid',
      depositRequired: true,
      amount: 150.0,
      paidAt: DateTime.now().toIso8601String(),
    );
  }
}
