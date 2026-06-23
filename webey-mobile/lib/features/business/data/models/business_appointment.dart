import '../../../../shared/models/beauty_models.dart';

class BusinessAppointment {
  const BusinessAppointment({
    required this.id,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.date,
    required this.time,
    required this.customerName,
    this.customerPhone,
    this.serviceName,
    this.staffName,
    this.price,
    this.durationMinutes,
    this.note,
    this.depositRequired = false,
    this.depositAmount,
    this.depositStatus,
    this.depositReferenceCode,
    this.cancellation,
  });

  final String id;
  final String status;
  final DateTime startsAt;
  final DateTime endsAt;
  final String date;
  final String time;
  final String customerName;
  final String? customerPhone;
  final String? serviceName;
  final String? staffName;
  final double? price;
  final int? durationMinutes;
  final String? note;
  final bool depositRequired;
  final double? depositAmount;
  final String? depositStatus;

  /// Banka açıklama kodu (WEBEY-{ISLETME}-{RASTGELE}) — işletme banka
  /// hareketlerini bu kodla eşleştirir.
  final String? depositReferenceCode;
  final CancellationFinancial? cancellation;

  factory BusinessAppointment.fromJson(Map<String, Object?> json) {
    final depositRaw = json['deposit'];
    final deposit = depositRaw is Map
        ? Map<String, Object?>.from(depositRaw)
        : const <String, Object?>{};

    return BusinessAppointment(
      id: _string(json['id']),
      status: _string(json['status'], fallback: 'pending'),
      startsAt: _dateTime(json['starts_at']),
      endsAt: _dateTime(json['ends_at']),
      date: _string(json['date']),
      time: _string(json['time']),
      customerName: _string(json['customer_name']),
      customerPhone: _nullableString(json['customer_phone']),
      serviceName: _nullableString(json['service_name']),
      staffName: _nullableString(json['staff_name']),
      price: _double(json['price']),
      durationMinutes: _int(json['duration_minutes']),
      note: _nullableString(json['note']),
      depositRequired: _bool(deposit['required']),
      depositAmount: _double(deposit['amount']),
      depositStatus: _nullableString(deposit['status']),
      depositReferenceCode: _nullableString(deposit['reference_code']),
      cancellation: CancellationFinancial.fromJson(json['cancellation']),
    );
  }

  bool get isPendingAction =>
      status == 'pending' || status == 'cancellation_requested';

  bool get canMarkCustomerOutcome {
    if (status != 'approved') return false;
    return startsAt.isBefore(DateTime.now()) ||
        startsAt.isAtSameMomentAs(DateTime.now());
  }

  static DateTime _dateTime(Object? value) {
    final text = value?.toString().trim() ?? '';
    return DateTime.tryParse(text) ?? DateTime(2000);
  }

  static String _string(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _double(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().toLowerCase().trim();
    return text == '1' || text == 'true' || text == 'yes' || text == 'on';
  }
}
