import '../../../../../shared/models/beauty_models.dart';
import '../../../discovery/data/models/salon_campaign.dart';

class BookingAvailabilitySlot {
  const BookingAvailabilitySlot({
    required this.time,
    required this.startsAt,
    required this.endsAt,
    required this.available,
  });

  final String time;
  final String startsAt;
  final String endsAt;
  final bool available;

  factory BookingAvailabilitySlot.fromJson(Map<String, Object?> json) {
    return BookingAvailabilitySlot(
      time: json['time']?.toString() ?? '',
      startsAt: json['starts_at']?.toString() ?? '',
      endsAt: json['ends_at']?.toString() ?? '',
      available: json['available'] == true,
    );
  }
}

class BookingAvailabilityResult {
  const BookingAvailabilityResult({
    required this.date,
    required this.businessId,
    required this.serviceId,
    required this.durationMinutes,
    required this.items,
    this.staffId,
  });

  final String date;
  final int businessId;
  final int serviceId;
  final int? staffId;
  final int durationMinutes;
  final List<BookingAvailabilitySlot> items;

  factory BookingAvailabilityResult.fromJson(Map<String, Object?> json) {
    final itemsList = json['items'];
    return BookingAvailabilityResult(
      date: json['date']?.toString() ?? '',
      businessId: _int(json['business_id']) ?? 0,
      serviceId: _int(json['service_id']) ?? 0,
      staffId: _int(json['staff_id']),
      durationMinutes: _int(json['duration_minutes']) ?? 0,
      items: itemsList is List
          ? itemsList
                .whereType<Map>()
                .map(
                  (e) => BookingAvailabilitySlot.fromJson(
                    Map<String, Object?>.from(e),
                  ),
                )
                .toList()
          : const [],
    );
  }
}

class BookingLockResult {
  const BookingLockResult({
    required this.locked,
    required this.lockToken,
    required this.expiresAt,
    required this.expiresIn,
    required this.startsAt,
    required this.endsAt,
    this.campaign,
    this.campaignReason,
  });

  final bool locked;
  final String lockToken;
  final String expiresAt;
  final int expiresIn;
  final String startsAt;
  final String endsAt;

  /// Seçilen hizmet+slot için sunucunun hesapladığı kampanya teklifi (varsa).
  final SalonCampaign? campaign;

  /// Kampanya adayı var ama slot koşula uymuyorsa açıklama (varsa).
  final String? campaignReason;

  factory BookingLockResult.fromJson(Map<String, Object?> json) {
    return BookingLockResult(
      locked: json['locked'] == true,
      lockToken: json['lock_token']?.toString() ?? '',
      expiresAt: json['expires_at']?.toString() ?? '',
      expiresIn: _int(json['expires_in']) ?? 300,
      startsAt: json['starts_at']?.toString() ?? '',
      endsAt: json['ends_at']?.toString() ?? '',
      campaign: SalonCampaign.fromJson(json['campaign']),
      campaignReason: json['campaign_reason']?.toString(),
    );
  }
}

class BookingResult {
  const BookingResult({
    required this.appointmentId,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.businessId,
    required this.serviceId,
    this.staffId,
    this.depositRequired = false,
    this.depositAmount,
    this.deposit,
    this.campaign,
    this.originalAmount,
    this.finalAmount,
    this.remainingAmount,
  });

  final String appointmentId;
  final String status;
  final String startsAt;
  final String endsAt;
  final int businessId;
  final int serviceId;
  final int? staffId;
  final bool depositRequired;
  final double? depositAmount;
  final DepositInfo? deposit;

  /// Uygulanan kampanya (varsa) — snapshot.
  final SalonCampaign? campaign;
  final double? originalAmount;
  final double? finalAmount;

  /// Salonda kalan = max(0, final - kapora). Backend otoriter hesaplar.
  final double? remainingAmount;

  factory BookingResult.fromJson(Map<String, Object?> json) {
    final appt = json['appointment'];
    final apptMap = appt is Map ? Map<String, Object?>.from(appt) : json;
    final deposit = DepositInfo.fromJson(apptMap['deposit']);
    return BookingResult(
      appointmentId: apptMap['id']?.toString() ?? '',
      status: apptMap['status']?.toString() ?? 'pending',
      startsAt: apptMap['starts_at']?.toString() ?? '',
      endsAt: apptMap['ends_at']?.toString() ?? '',
      businessId: _int(apptMap['business_id']) ?? 0,
      serviceId: _int(apptMap['service_id']) ?? 0,
      staffId: _int(apptMap['staff_id']),
      depositRequired: deposit?.required ?? _bool(apptMap['deposit_required']),
      depositAmount: deposit?.amount ?? _dbl(apptMap['deposit_amount']),
      deposit: deposit,
      campaign: SalonCampaign.fromJson(apptMap['campaign']),
      originalAmount: _dbl(apptMap['original_amount']),
      finalAmount: _dbl(apptMap['final_amount']),
      remainingAmount: _dbl(apptMap['remaining_amount']),
    );
  }
}

bool _bool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase().trim();
  return text == '1' || text == 'true' || text == 'yes' || text == 'on';
}

double? _dbl(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString());
}

int? _int(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}
