import 'business_appointment.dart';

class BusinessDashboard {
  const BusinessDashboard({
    required this.summary,
    required this.todayItems,
    required this.pendingItems,
  });

  final BusinessDashboardSummary summary;
  final List<BusinessAppointment> todayItems;
  final List<BusinessAppointment> pendingItems;

  factory BusinessDashboard.fromJson(Map<String, Object?> json) {
    final summaryJson = _map(json['summary']);
    final todayJson = _map(json['today']);
    final pendingJson = _map(json['pending']);

    return BusinessDashboard(
      summary: BusinessDashboardSummary.fromJson(summaryJson),
      todayItems: _appointments(todayJson['items']),
      pendingItems: _appointments(pendingJson['items']),
    );
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is Map) return Map<String, Object?>.from(value);
    return const {};
  }

  static List<BusinessAppointment> _appointments(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (item) =>
              BusinessAppointment.fromJson(Map<String, Object?>.from(item)),
        )
        .toList();
  }
}

class BusinessDashboardSummary {
  const BusinessDashboardSummary({
    required this.todayAppointments,
    required this.pendingAppointments,
    required this.upcomingAppointments,
    required this.completedThisMonth,
    required this.cancelledThisMonth,
    required this.monthlyRevenueEstimate,
  });

  final int todayAppointments;
  final int pendingAppointments;
  final int upcomingAppointments;
  final int completedThisMonth;
  final int cancelledThisMonth;
  final double monthlyRevenueEstimate;

  factory BusinessDashboardSummary.fromJson(Map<String, Object?> json) {
    return BusinessDashboardSummary(
      todayAppointments: _int(json['today_appointments']),
      pendingAppointments: _int(json['pending_appointments']),
      upcomingAppointments: _int(json['upcoming_appointments']),
      completedThisMonth: _int(json['completed_this_month']),
      cancelledThisMonth: _int(json['cancelled_this_month']),
      monthlyRevenueEstimate: _double(json['monthly_revenue_estimate']),
    );
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _double(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
