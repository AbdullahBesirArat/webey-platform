class CustomerReviewItem {
  const CustomerReviewItem({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.rating,
    this.appointmentId,
    this.businessSlug,
    this.businessCity,
    this.businessDistrict,
    this.serviceName,
    this.staffId,
    this.staffName,
    this.targetType = 'business',
    this.comment,
    this.createdAt,
  });

  final String id;
  final String? appointmentId;
  final String businessId;
  final String? businessSlug;
  final String businessName;
  final String? businessCity;
  final String? businessDistrict;
  final String? serviceName;
  final String? staffId;
  final String? staffName;
  final String targetType;
  final int rating;
  final String? comment;
  final DateTime? createdAt;

  bool get isStaffReview => targetType == 'staff' || (staffId ?? '').isNotEmpty;

  factory CustomerReviewItem.fromJson(Map<String, Object?> json) {
    return CustomerReviewItem(
      id: _str(json['id']),
      appointmentId: _nullableStr(json['appointment_id']),
      businessId: _str(json['business_id']),
      businessSlug: _nullableStr(json['business_slug']),
      businessName: _str(json['business_name']),
      businessCity: _nullableStr(json['business_city']),
      businessDistrict: _nullableStr(json['business_district']),
      serviceName: _nullableStr(json['service_name']),
      staffId: _nullableStr(json['staff_id']),
      staffName: _nullableStr(json['staff_name']),
      targetType: _str(json['target_type']).isEmpty
          ? 'business'
          : _str(json['target_type']),
      rating: _int(json['rating']),
      comment: _nullableStr(json['comment']),
      createdAt: DateTime.tryParse(_str(json['created_at'])),
    );
  }
}

String _str(Object? value) => value?.toString() ?? '';

String? _nullableStr(Object? value) {
  final text = _str(value).trim();
  return text.isEmpty ? null : text;
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
