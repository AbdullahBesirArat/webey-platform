import '../../../../../shared/services/api_client.dart';

/// Müşteri kapora cüzdanı — tek kapora hareketi.
class DepositWalletItem {
  const DepositWalletItem({
    required this.appointmentId,
    required this.status,
    required this.label,
    required this.amount,
    required this.currency,
    required this.businessName,
    this.serviceName,
    this.appointmentStart,
    this.eventAt,
  });

  final int appointmentId;
  final String status;
  final String label;
  final double amount;
  final String currency;
  final String businessName;
  final String? serviceName;
  final DateTime? appointmentStart;
  final DateTime? eventAt;

  static double _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int _asInt(Object? v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static DateTime? _asDate(Object? v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    return DateTime.tryParse(s.replaceFirst(' ', 'T'));
  }

  factory DepositWalletItem.fromJson(Map<String, Object?> json) {
    return DepositWalletItem(
      appointmentId: _asInt(json['appointment_id']),
      status: (json['status'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      amount: _asDouble(json['amount']),
      currency: (json['currency'] ?? 'TRY').toString(),
      businessName: (json['business_name'] ?? '').toString(),
      serviceName: (json['service_name']?.toString().isNotEmpty ?? false)
          ? json['service_name'].toString()
          : null,
      appointmentStart: _asDate(json['appointment_start']),
      eventAt: _asDate(json['event_at']),
    );
  }
}

/// Müşteri kapora cüzdanı — özet + hareketler.
class DepositWallet {
  const DepositWallet({
    required this.paidTotal,
    required this.pendingTotal,
    required this.refundedTotal,
    required this.currency,
    required this.items,
  });

  final double paidTotal;
  final double pendingTotal;
  final double refundedTotal;
  final String currency;
  final List<DepositWalletItem> items;

  static const empty = DepositWallet(
    paidTotal: 0,
    pendingTotal: 0,
    refundedTotal: 0,
    currency: 'TRY',
    items: [],
  );

  factory DepositWallet.fromJson(Map<String, Object?> json) {
    final summary = (json['summary'] as Map?)?.cast<String, Object?>() ?? {};
    final rawItems = (json['items'] as List?) ?? const [];
    return DepositWallet(
      paidTotal: DepositWalletItem._asDouble(summary['paid_total']),
      pendingTotal: DepositWalletItem._asDouble(summary['pending_total']),
      refundedTotal: DepositWalletItem._asDouble(summary['refunded_total']),
      currency: (summary['currency'] ?? 'TRY').toString(),
      items: rawItems
          .whereType<Map>()
          .map((e) => DepositWalletItem.fromJson(e.cast<String, Object?>()))
          .toList(),
    );
  }
}

class CustomerWalletRepository {
  const CustomerWalletRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? const ApiClient();

  static const instance = CustomerWalletRepository();

  final ApiClient _apiClient;

  /// Giriş yapan müşterinin kapora & cüzdan özetini getirir.
  Future<DepositWallet> getWallet() async {
    final data = await _apiClient.getData('/customer/deposit-wallet.php');
    return DepositWallet.fromJson(data);
  }
}
