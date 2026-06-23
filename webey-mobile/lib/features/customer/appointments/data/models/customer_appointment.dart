import '../../../../../core/config/api_config.dart';
import '../../../../../shared/models/beauty_models.dart';

class CustomerAppointmentSalon {
  const CustomerAppointmentSalon({
    this.id,
    this.name,
    this.city,
    this.district,
    this.address,
    this.coverImageUrl,
  });

  final String? id;
  final String? name;
  final String? city;
  final String? district;
  final String? address;
  final String? coverImageUrl;

  factory CustomerAppointmentSalon.fromJson(Map<String, Object?> json) {
    return CustomerAppointmentSalon(
      id: _str(json['id']),
      name: _str(json['name']),
      city: _str(json['city']),
      district: _str(json['district']),
      address: _str(json['address']),
      coverImageUrl: ApiConfig.resolveUrl(
        _str(json['cover_image_url'] ?? json['image_url']),
      ),
    );
  }
}

class CustomerAppointmentService {
  const CustomerAppointmentService({
    required this.id,
    this.name,
    this.price,
    this.durationMinutes,
  });

  final String id;
  final String? name;
  final double? price;
  final int? durationMinutes;

  factory CustomerAppointmentService.fromJson(Map<String, Object?> json) {
    return CustomerAppointmentService(
      id: _str(json['id']) ?? '',
      name: _str(json['name']),
      price: _double(json['price']),
      durationMinutes: _int(json['duration_minutes']),
    );
  }
}

class CustomerAppointmentStaff {
  const CustomerAppointmentStaff({required this.id, this.name});

  final String id;
  final String? name;

  factory CustomerAppointmentStaff.fromJson(Map<String, Object?> json) {
    return CustomerAppointmentStaff(
      id: _str(json['id']) ?? '',
      name: _str(json['name']),
    );
  }
}

class CustomerAppointment {
  const CustomerAppointment({
    required this.id,
    required this.status,
    required this.startsAt,
    this.endsAt,
    required this.date,
    required this.time,
    this.durationMinutes,
    required this.salon,
    this.service,
    this.staff,
    this.canCancel = false,
    this.hasReview = false,
    this.deposit,
    this.originalAmount,
    this.finalAmount,
    this.remainingAmount,
    this.campaignTitle,
    this.cancellation,
  });

  final String id;
  final String status;
  final String startsAt;
  final String? endsAt;
  final String date;
  final String time;
  final int? durationMinutes;
  final CustomerAppointmentSalon salon;
  final CustomerAppointmentService? service;
  final CustomerAppointmentStaff? staff;
  final bool canCancel;
  final bool hasReview;
  final DepositInfo? deposit;

  /// Kampanya/fiyat snapshot (randevu oluşturulduğu andaki sabit değerler).
  final double? originalAmount;
  final double? finalAmount;
  final double? remainingAmount;
  final String? campaignTitle;
  final CancellationFinancial? cancellation;

  factory CustomerAppointment.fromJson(Map<String, Object?> json) {
    final salonJson = _map(json['salon']);
    final serviceJson = _map(json['service']);
    final staffJson = _map(json['staff']);
    return CustomerAppointment(
      id: _str(json['id']) ?? '',
      status: _str(json['status']) ?? 'pending',
      startsAt: _str(json['starts_at']) ?? '',
      endsAt: _str(json['ends_at']),
      date: _str(json['date']) ?? '',
      time: _str(json['time']) ?? '',
      durationMinutes: _int(json['duration_minutes']),
      salon: salonJson != null
          ? CustomerAppointmentSalon.fromJson(salonJson)
          : const CustomerAppointmentSalon(),
      service: serviceJson != null
          ? CustomerAppointmentService.fromJson(serviceJson)
          : null,
      staff: staffJson != null
          ? CustomerAppointmentStaff.fromJson(staffJson)
          : null,
      canCancel: _bool(json['can_cancel']),
      hasReview: _bool(json['has_review']),
      deposit: DepositInfo.fromJson(json['deposit']),
      originalAmount: _dblOrNull(json['original_amount']),
      finalAmount: _dblOrNull(json['final_amount']),
      remainingAmount: _dblOrNull(json['remaining_amount']),
      campaignTitle: _str(json['campaign_title']),
      cancellation: CancellationFinancial.fromJson(json['cancellation']),
    );
  }

  static double? _dblOrNull(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Appointment toAppointment() {
    DateTime startAt;
    try {
      startAt = startsAt.isNotEmpty
          ? DateTime.parse(startsAt)
          : DateTime.parse('$date ${time.isEmpty ? '00:00' : time}:00');
    } catch (_) {
      startAt = DateTime.now();
    }

    DateTime endAt;
    try {
      final e = endsAt;
      endAt = (e != null && e.isNotEmpty)
          ? DateTime.parse(e)
          : startAt.add(Duration(minutes: durationMinutes ?? 60));
    } catch (_) {
      endAt = startAt.add(Duration(minutes: durationMinutes ?? 60));
    }

    return Appointment(
      id: id,
      businessId: salon.id ?? '',
      salonName: salon.name ?? '',
      customerName: '',
      serviceName: service?.name ?? '',
      staffName: staff?.name ?? '',
      startAt: startAt,
      endAt: endAt,
      status: _mapStatus(status),
      depositStatus: DepositStatus.none,
      // Kapora tutarı (varsa) — salonda kalan = total - depositAmount.
      depositAmount: (deposit?.required ?? false) ? (deposit?.amount ?? 0) : 0,
      // İndirim sonrası final tutar tercih edilir; yoksa hizmet fiyatı.
      total: finalAmount ?? service?.price ?? 0,
      bookingSource: 'mobile',
      canCancel: canCancel,
      hasReview: hasReview,
      depositInfo: deposit,
      serviceId: service?.id ?? '',
      cancellationRequested: status == 'cancellation_requested',
      cancelReason: _cancelLabel(status),
      salonAddress: salon.address,
      salonDistrict: salon.district,
      salonCity: salon.city,
      salonCoverImageUrl: salon.coverImageUrl,
      cancellation: cancellation,
    );
  }

  static AppointmentStatus _mapStatus(String s) {
    return switch (s) {
      'approved' => AppointmentStatus.approved,
      'completed' => AppointmentStatus.completed,
      'cancelled' => AppointmentStatus.cancelled,
      'cancellation_requested' => AppointmentStatus.cancellationRequested,
      'no_show' => AppointmentStatus.noShow,
      'rejected' || 'declined' => AppointmentStatus.rejected,
      _ => AppointmentStatus.pending,
    };
  }

  static String? _cancelLabel(String s) {
    return switch (s) {
      'cancellation_requested' => 'İptal talebi bekliyor',
      'cancelled' => 'İptal edildi',
      'rejected' || 'declined' => 'Reddedildi',
      _ => null,
    };
  }
}

// Backend alanları int/string/null olarak dönebilir; tip drift'inde sessizce
// boş listeye düşmemek için güvenli parse helper'ları.
Map<String, Object?>? _map(Object? value) {
  if (value is Map) return Map<String, Object?>.from(value);
  return null;
}

String? _str(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

bool _bool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase().trim();
  return text == '1' || text == 'true' || text == 'yes' || text == 'on';
}
