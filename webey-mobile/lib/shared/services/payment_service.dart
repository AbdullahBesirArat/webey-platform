import '../models/beauty_models.dart';
import 'app_config.dart';
import 'app_logger.dart';
import 'result.dart';

abstract class PaymentService {
  Future<Result<PaymentIntent>> createDepositPaymentIntent({
    required double amount,
    required String appointmentId,
    required String businessId,
    String description,
  });

  Future<Result<PaymentIntent>> createSubscriptionPaymentIntent({
    required double amount,
    required String businessId,
    required String planId,
  });

  Future<Result<PaymentIntent>> createBoostPaymentIntent({
    required double amount,
    required String businessId,
    required String packageId,
  });

  Future<Result<PaymentIntent>> confirmPaymentMock(String intentId);

  Future<Result<PaymentStatus>> getPaymentStatus(String intentId);
}

class MockPaymentService implements PaymentService {
  MockPaymentService._();

  static final instance = MockPaymentService._();

  final Map<String, PaymentIntent> _intents = {};

  @override
  Future<Result<PaymentIntent>> createDepositPaymentIntent({
    required double amount,
    required String appointmentId,
    required String businessId,
    String description = 'Randevu kapora ödemesi',
  }) async {
    if (amount <= 0) return Result.fail('Kapora tutarı 0 veya negatif olamaz.');
    return _createIntent(
      type: PaymentType.deposit,
      amount: amount,
      relatedAppointmentId: appointmentId,
      relatedBusinessId: businessId,
      description: description,
    );
  }

  @override
  Future<Result<PaymentIntent>> createSubscriptionPaymentIntent({
    required double amount,
    required String businessId,
    required String planId,
  }) async {
    if (amount < 0) return Result.fail('Abonelik tutarı negatif olamaz.');
    return _createIntent(
      type: PaymentType.businessSubscription,
      amount: amount,
      relatedBusinessId: businessId,
      description: '$planId abonelik ödeme niyeti',
    );
  }

  @override
  Future<Result<PaymentIntent>> createBoostPaymentIntent({
    required double amount,
    required String businessId,
    required String packageId,
  }) async {
    if (amount <= 0) {
      return Result.fail('Öne çıkarma tutarı 0 veya negatif olamaz.');
    }
    return _createIntent(
      type: PaymentType.promotionBoost,
      amount: amount,
      relatedBusinessId: businessId,
      description: '$packageId öne çıkarma ödeme niyeti',
    );
  }

  @override
  Future<Result<PaymentIntent>> confirmPaymentMock(String intentId) async {
    final intent = _intents[intentId];
    if (intent == null) return Result.fail('Ödeme niyeti bulunamadı.');
    final paid = intent.copyWith(status: PaymentStatus.paid);
    _intents[intentId] = paid;
    AppLogger.info('Mock payment confirmed: $intentId');
    return Result.ok(paid);
  }

  @override
  Future<Result<PaymentStatus>> getPaymentStatus(String intentId) async {
    final intent = _intents[intentId];
    if (intent == null) return Result.fail('Ödeme niyeti bulunamadı.');
    return Result.ok(intent.status);
  }

  Future<Result<PaymentIntent>> _createIntent({
    required PaymentType type,
    required double amount,
    required String description,
    String relatedAppointmentId = '',
    String relatedBusinessId = '',
  }) async {
    final id = 'pi_${DateTime.now().microsecondsSinceEpoch}';
    final intent = PaymentIntent(
      id: id,
      type: type,
      amount: amount,
      currency: 'TRY',
      status: PaymentStatus.pending,
      description: description,
      relatedAppointmentId: relatedAppointmentId,
      relatedBusinessId: relatedBusinessId,
      provider: AppConfig.current.paymentMode,
      checkoutUrlMock: 'https://checkout.mock.webey.beauty/$id',
      createdAt: DateTime.now(),
    );
    _intents[id] = intent;
    AppLogger.info('Mock payment intent created: $id');
    return Result.ok(intent);
  }
}
