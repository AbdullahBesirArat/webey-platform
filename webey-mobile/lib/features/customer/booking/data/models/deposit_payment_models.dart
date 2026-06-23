class DepositStartResult {
  const DepositStartResult({
    required this.appointmentId,
    required this.alreadyPaid,
    required this.depositRequired,
    this.amount,
    this.checkoutToken,
    this.checkoutUrl,
    this.paidAt,
  });

  final int appointmentId;
  final bool alreadyPaid;
  final bool depositRequired;
  final double? amount;
  final String? checkoutToken;
  final String? checkoutUrl;
  final String? paidAt;

  factory DepositStartResult.fromJson(Map<String, Object?> json) {
    return DepositStartResult(
      appointmentId: _int(json['appointment_id']) ?? 0,
      alreadyPaid: json['already_paid'] == true,
      depositRequired: json['deposit_required'] == true,
      amount: _double(json['amount']),
      checkoutToken: json['checkout_token']?.toString(),
      checkoutUrl: json['checkout_url']?.toString(),
      paidAt: json['paid_at']?.toString(),
    );
  }
}

class DepositStatusResult {
  const DepositStatusResult({
    required this.appointmentId,
    required this.depositStatus,
    required this.depositRequired,
    this.amount,
    this.paidAt,
  });

  final int appointmentId;

  /// not_required | not_started | pending | paid | failed | refunded | cancelled
  final String depositStatus;
  final bool depositRequired;
  final double? amount;
  final String? paidAt;

  bool get isPaid => depositStatus == 'paid';
  bool get isFailed => depositStatus == 'failed';
  bool get isCancelled => depositStatus == 'cancelled';
  bool get isTerminal =>
      isPaid || isFailed || isCancelled || depositStatus == 'refunded';

  factory DepositStatusResult.fromJson(Map<String, Object?> json) {
    return DepositStatusResult(
      appointmentId: _int(json['appointment_id']) ?? 0,
      depositStatus: json['deposit_status']?.toString() ?? 'pending',
      depositRequired: json['deposit_required'] == true,
      amount: _double(json['amount']),
      paidAt: json['paid_at']?.toString(),
    );
  }
}

int? _int(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

double? _double(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString());
}
