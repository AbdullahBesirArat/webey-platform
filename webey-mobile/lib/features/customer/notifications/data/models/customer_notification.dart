class CustomerNotification {
  const CustomerNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.appointmentId,
    this.businessName,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final bool read;
  final String createdAt;
  final String? appointmentId;
  final String? businessName;

  factory CustomerNotification.fromJson(Map<String, Object?> json) {
    final data = json['data'] as Map<String, Object?>? ?? {};
    return CustomerNotification(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'info',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      read: json['read'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
      appointmentId: data['appointment_id'] as String?,
      businessName: data['business_name'] as String?,
    );
  }
}

class CustomerNotificationsResult {
  const CustomerNotificationsResult({
    required this.items,
    required this.unreadCount,
  });

  final List<CustomerNotification> items;
  final int unreadCount;

  static const empty = CustomerNotificationsResult(items: [], unreadCount: 0);

  factory CustomerNotificationsResult.fromJson(Map<String, Object?> json) {
    final rawItems = json['items'] as List? ?? [];
    final items = rawItems
        .whereType<Map>()
        .map(
          (item) =>
              CustomerNotification.fromJson(Map<String, Object?>.from(item)),
        )
        .toList();
    return CustomerNotificationsResult(
      items: items,
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }
}
