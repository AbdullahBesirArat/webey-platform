import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

@pragma('vm:entry-point')
Future<void> customerFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  debugPrint('[CustomerFcmService] background message id=${message.messageId}');
}

class CustomerFcmService {
  CustomerFcmService._();

  static final CustomerFcmService instance = CustomerFcmService._();

  final ApiClient _apiClient = const ApiClient();
  bool _initialized = false;
  String? _lastRegisteredToken;
  DateTime? _lastRegisterAttemptAt;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  Future<void> init() async {
    if (_initialized) {
      debugPrint('[CustomerFcmService] init skipped: already initialized.');
      return;
    }
    _initialized = true;
    debugPrint('[CustomerFcmService] init started.');

    try {
      final settings = await _messaging.requestPermission();
      debugPrint(
        '[CustomerFcmService] permission result: '
        '${settings.authorizationStatus.name}',
      );
      await registerCurrentToken(reason: 'init');

      _messaging.onTokenRefresh.listen((token) {
        debugPrint('[CustomerFcmService] token refresh received.');
        if (token.isEmpty) return;
        _registerToken(token, reason: 'refresh');
      });

      FirebaseMessaging.onMessage.listen((message) {
        debugPrint(
          '[CustomerFcmService] foreground message '
          'id=${message.messageId}, data=${message.data}',
        );
      });
    } catch (error) {
      debugPrint('[CustomerFcmService] init failed: $error');
    }
  }

  Future<void> registerCurrentToken({String reason = 'manual'}) async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[CustomerFcmService] token missing. reason=$reason');
        return;
      }
      debugPrint('[CustomerFcmService] token present. reason=$reason');
      await _registerToken(token, reason: reason);
    } catch (error) {
      debugPrint(
        '[CustomerFcmService] get/register current token failed. '
        'reason=$reason error=$error',
      );
    }
  }

  Future<void> _registerToken(String token, {required String reason}) async {
    final now = DateTime.now();
    final lastAttempt = _lastRegisterAttemptAt;
    if (_lastRegisteredToken == token &&
        lastAttempt != null &&
        now.difference(lastAttempt) < const Duration(minutes: 5)) {
      debugPrint(
        '[CustomerFcmService] register skipped: token recently registered. '
        'reason=$reason',
      );
      return;
    }

    _lastRegisterAttemptAt = now;
    debugPrint(
      '[CustomerFcmService] register attempt. '
      'reason=$reason platform=${defaultTargetPlatform.name}',
    );
    try {
      await _apiClient.postData(
        '/customer/device-token.php',
        body: {'token': token, 'platform': defaultTargetPlatform.name},
      );
      _lastRegisteredToken = token;
      debugPrint('[CustomerFcmService] register success. reason=$reason');
    } catch (error) {
      debugPrint(
        '[CustomerFcmService] register failure. '
        'reason=$reason error=$error',
      );
    }
  }
}
