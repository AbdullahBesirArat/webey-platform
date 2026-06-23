/// İşletme tarafı kampanya modeli (yönetim ekranı + form).
class BusinessCampaign {
  const BusinessCampaign({
    this.id,
    required this.title,
    this.description,
    this.conditionType = 'general',
    this.discountKind = 'percent',
    this.discountValue = 0,
    this.scopeType = 'all_services',
    this.serviceIds = const [],
    this.serviceNames = const [],
    this.startDate,
    this.endDate,
    this.startTime,
    this.endTime,
    this.daysOfWeek = const [],
    this.status = 'active',
    this.state = 'active',
    this.badge = '',
    this.summary = '',
    this.scopeSummary = '',
    this.validitySummary = '',
    this.selectedServicesCount = 0,
    this.customerVisibilityStatus = 'visible_now',
    this.customerVisibilityMessage = '',
    this.lifecycleStatus = 'active',
    this.isCurrentlyEligible = false,
    this.nextEligibleAt,
    this.performance,
  });

  final int? id;
  final String title;
  final String? description;

  /// general | weekday | hourly
  final String conditionType;

  /// percent | fixed
  final String discountKind;
  final double discountValue;

  /// all_services | selected_services
  final String scopeType;
  final List<int> serviceIds;
  final List<String> serviceNames;
  final String? startDate;
  final String? endDate;
  final String? startTime;
  final String? endTime;
  final List<int> daysOfWeek;

  /// active | paused (sunucu) — archived listede gelmez
  final String status;

  /// Türetilmiş durum: active | paused | upcoming | expired
  final String state;
  final String badge;
  final String summary;
  final String scopeSummary;
  final String validitySummary;
  final int selectedServicesCount;

  /// visible_now | waiting_for_condition | upcoming | paused | ended
  final String customerVisibilityStatus;
  final String customerVisibilityMessage;
  final String lifecycleStatus;
  final bool isCurrentlyEligible;
  final String? nextEligibleAt;
  final CampaignPerformance? performance;

  bool get isActive => status == 'active';
  bool get appliesToAllServices => scopeType == 'all_services';

  BusinessCampaign copyWith({String? status}) => BusinessCampaign(
        id: id,
        title: title,
        description: description,
        conditionType: conditionType,
        discountKind: discountKind,
        discountValue: discountValue,
        scopeType: scopeType,
        serviceIds: serviceIds,
        serviceNames: serviceNames,
        startDate: startDate,
        endDate: endDate,
        startTime: startTime,
        endTime: endTime,
        daysOfWeek: daysOfWeek,
        status: status ?? this.status,
        state: state,
        badge: badge,
        summary: summary,
        scopeSummary: scopeSummary,
        validitySummary: validitySummary,
        selectedServicesCount: selectedServicesCount,
        customerVisibilityStatus: customerVisibilityStatus,
        customerVisibilityMessage: customerVisibilityMessage,
        lifecycleStatus: lifecycleStatus,
        isCurrentlyEligible: isCurrentlyEligible,
        nextEligibleAt: nextEligibleAt,
        performance: performance,
      );

  /// Aynı koşullarla yeni kampanya (Kopyala): id/tarihler boş, başlık "… kopyası".
  BusinessCampaign toDuplicate() => BusinessCampaign(
        id: null,
        title: '$title kopyası',
        description: description,
        conditionType: conditionType,
        discountKind: discountKind,
        discountValue: discountValue,
        scopeType: scopeType,
        serviceIds: serviceIds,
        serviceNames: serviceNames,
        startDate: null,
        endDate: null,
        startTime: startTime,
        endTime: endTime,
        daysOfWeek: daysOfWeek,
        status: 'active',
      );

  factory BusinessCampaign.fromJson(Map<String, Object?> json) {
    return BusinessCampaign(
      id: _int(json['id']),
      title: json['title']?.toString() ?? '',
      description: _nullableString(json['description']),
      conditionType: json['condition_type']?.toString() ?? 'general',
      discountKind: json['discount_kind']?.toString() ?? 'percent',
      discountValue: _double(json['discount_value']) ?? 0,
      scopeType: json['scope_type']?.toString() ?? 'all_services',
      serviceIds: _intList(json['service_ids']),
      serviceNames: _serviceNames(json['services']),
      startDate: _nullableString(json['start_date']),
      endDate: _nullableString(json['end_date']),
      startTime: _nullableString(json['start_time']),
      endTime: _nullableString(json['end_time']),
      daysOfWeek: _intList(json['days_of_week']),
      status: json['status']?.toString() ?? 'active',
      state: json['state']?.toString() ?? 'active',
      badge: json['badge']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      scopeSummary: json['scope_summary']?.toString() ?? '',
      validitySummary: json['validity_summary']?.toString() ?? '',
      selectedServicesCount: _int(json['selected_services_count']) ?? 0,
      customerVisibilityStatus:
          json['customer_visibility_status']?.toString() ?? 'visible_now',
      customerVisibilityMessage:
          json['customer_visibility_message']?.toString() ?? '',
      lifecycleStatus: json['lifecycle_status']?.toString() ?? 'active',
      isCurrentlyEligible: json['is_currently_eligible'] == true,
      nextEligibleAt: _nullableString(json['next_eligible_at']),
      performance: json['performance'] is Map
          ? CampaignPerformance.fromJson(
              Map<String, Object?>.from(json['performance'] as Map))
          : null,
    );
  }

  /// campaign-save.php gövdesi.
  Map<String, Object?> toSaveBody() => {
        if (id != null) 'id': id,
        'title': title,
        if (description != null && description!.isNotEmpty)
          'description': description,
        'condition_type': conditionType,
        'discount_kind': discountKind,
        'discount_value': discountValue,
        'scope_type': scopeType,
        'service_ids': scopeType == 'selected_services' ? serviceIds : <int>[],
        if (startDate != null && startDate!.isNotEmpty) 'start_date': startDate,
        if (endDate != null && endDate!.isNotEmpty) 'end_date': endDate,
        if (startTime != null && startTime!.isNotEmpty) 'start_time': startTime,
        if (endTime != null && endTime!.isNotEmpty) 'end_time': endTime,
        'days_of_week': daysOfWeek,
        'status': status,
      };

  static int? _int(Object? v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  static double? _double(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }

  static String? _nullableString(Object? v) {
    final t = v?.toString() ?? '';
    return t.isEmpty ? null : t;
  }

  static List<int> _intList(Object? v) {
    if (v is! List) return const [];
    final out = <int>[];
    for (final e in v) {
      final n = int.tryParse(e.toString());
      if (n != null) out.add(n);
    }
    return out;
  }

  static List<String> _serviceNames(Object? v) {
    if (v is! List) return const [];
    final out = <String>[];
    for (final e in v) {
      if (e is Map) {
        final name = e['name']?.toString() ?? '';
        if (name.isNotEmpty) out.add(name);
      }
    }
    return out;
  }
}

/// Gerçek kampanya performansı (appointment snapshot'larından).
class CampaignPerformance {
  const CampaignPerformance({
    this.hasData = false,
    this.bookingCount = 0,
    this.completedCount = 0,
    this.totalDiscountAmount = 0,
    this.netRevenueAmount = 0,
    this.lastBookingAt,
  });

  final bool hasData;
  final int bookingCount;
  final int completedCount;
  final double totalDiscountAmount;
  final double netRevenueAmount;
  final String? lastBookingAt;

  factory CampaignPerformance.fromJson(Map<String, Object?> json) {
    double d(Object? v) =>
        v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0);
    int i(Object? v) =>
        v is int ? v : (int.tryParse(v?.toString() ?? '') ?? 0);
    return CampaignPerformance(
      hasData: json['has_data'] == true,
      bookingCount: i(json['booking_count']),
      completedCount: i(json['completed_count']),
      totalDiscountAmount: d(json['total_discount_amount']),
      netRevenueAmount: d(json['net_revenue_amount']),
      lastBookingAt: json['last_booking_at']?.toString(),
    );
  }
}
