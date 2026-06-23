/// Müşteri tarafı kampanya modeli.
///
/// İki farklı backend payload'ını da güvenle parse eder:
///  - Vitrin (salons.php / salon-detail.php `campaign`): badge, summary, koşullar
///  - Booking teklifi (lock.php / book.php `campaign`): discount_amount,
///    original_price, final_price
///
/// Eski backend response'ları (alan yoksa) için tamamen null-safe; alan
/// gelmezse UI kampanya göstermez.
class SalonCampaign {
  const SalonCampaign({
    required this.id,
    required this.title,
    this.description,
    this.badge = '',
    this.summary = '',
    this.conditionType = 'general',
    this.discountKind = 'percent',
    this.discountValue = 0,
    this.startDate,
    this.endDate,
    this.startTime,
    this.endTime,
    this.daysOfWeek = const [],
    this.appliesToAllServices = true,
    this.serviceIds = const [],
    this.scopeSummary = '',
    this.validitySummary = '',
    this.eligibilityNow = true,
    this.discountAmount,
    this.originalPrice,
    this.finalPrice,
  });

  final String id;
  final String title;
  final String? description;
  final String badge;
  final String summary;
  final String conditionType;
  final String discountKind;
  final double discountValue;
  final String? startDate;
  final String? endDate;
  final String? startTime;
  final String? endTime;
  final List<int> daysOfWeek;
  final bool appliesToAllServices;
  final List<String> serviceIds;

  /// "Tüm hizmetlerde" / "2 seçili hizmette" (backend hesaplar).
  final String scopeSummary;

  /// "Pzt–Cum · 09:00–18:00" gibi koşul özeti (backend hesaplar).
  final String validitySummary;

  /// Şu an gerçekten geçerli mi (backend otoritesi).
  final bool eligibilityNow;

  // Booking teklifi alanları (yalnız lock/book yanıtında dolu)
  final double? discountAmount;
  final double? originalPrice;
  final double? finalPrice;

  bool get hasQuote => discountAmount != null && finalPrice != null;

  /// Kısa indirim etiketi (badge boşsa türet).
  String get shortLabel {
    if (badge.isNotEmpty) return badge;
    if (discountKind == 'fixed') {
      return '${_money(discountValue)} TL indirim';
    }
    return '%${_money(discountValue)} indirim';
  }

  static String _money(double v) {
    if ((v - v.roundToDouble()).abs() < 0.005) return v.round().toString();
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }

  static SalonCampaign? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return SalonCampaign(
      id: id,
      title: json['title']?.toString() ?? '',
      description: _nullableString(json['description']),
      badge: json['badge']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      conditionType: json['condition_type']?.toString() ?? 'general',
      discountKind: json['discount_kind']?.toString() ?? 'percent',
      discountValue: _double(json['discount_value']) ?? 0,
      startDate: _nullableString(json['start_date']),
      endDate: _nullableString(json['end_date']),
      startTime: _nullableString(json['start_time']),
      endTime: _nullableString(json['end_time']),
      daysOfWeek: _intList(json['days_of_week']),
      appliesToAllServices: json['applies_to_all_services'] != false,
      serviceIds: _stringList(json['service_ids']),
      scopeSummary: json['scope_summary']?.toString() ?? '',
      validitySummary: json['validity_summary']?.toString() ?? '',
      eligibilityNow: json['eligibility_now'] != false,
      discountAmount: _double(json['discount_amount']),
      originalPrice: _double(json['original_price']),
      finalPrice: _double(json['final_price']),
    );
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString() ?? '';
    return text.isEmpty ? null : text;
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static List<int> _intList(Object? value) {
    if (value is! List) return const [];
    final out = <int>[];
    for (final v in value) {
      final n = int.tryParse(v.toString());
      if (n != null) out.add(n);
    }
    return out;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
