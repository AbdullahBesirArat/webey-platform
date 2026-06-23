import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../features/business/data/repositories/business_repository.dart';

@pragma('vm:entry-point')
Future<void> businessFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  debugPrint('[BusinessFcmService] background message id=${message.messageId}');
}

class BusinessFcmService {
  BusinessFcmService._();

  static final BusinessFcmService instance = BusinessFcmService._();

  final BusinessRepository _repository = BusinessRepository.instance;
  bool _initialized = false;
  String? _lastRegisteredToken;
  DateTime? _lastRegisterAttemptAt;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  Future<void> init() async {
    if (_initialized) {
      debugPrint('[BusinessFcmService] init skipped: already initialized.');
      return;
    }
    _initialized = true;
    debugPrint('[BusinessFcmService] init started.');

    try {
      final settings = await _messaging.requestPermission();
      debugPrint(
        '[BusinessFcmService] permission result: '
        '${settings.authorizationStatus.name}',
      );
      await registerCurrentToken(reason: 'init');

      _messaging.onTokenRefresh.listen((token) {
        debugPrint('[BusinessFcmService] token refresh received.');
        if (token.isEmpty) return;
        _registerToken(token, reason: 'refresh');
      });

      FirebaseMessaging.onMessage.listen((message) {
        debugPrint(
          '[BusinessFcmService] foreground message '
          'id=${message.messageId}, data=${message.data}',
        );
      });
    } catch (error) {
      debugPrint('[BusinessFcmService] init failed: $error');
    }
  }

  Future<void> registerCurrentToken({String reason = 'manual'}) async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[BusinessFcmService] token missing. reason=$reason');
        return;
      }
      debugPrint('[BusinessFcmService] token present. reason=$reason');
      await _registerToken(token, reason: reason);
    } catch (error) {
      debugPrint(
        '[BusinessFcmService] get/register current token failed. '
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
        '[BusinessFcmService] register skipped: token recently registered. '
        'reason=$reason',
      );
      return;
    }

    _lastRegisterAttemptAt = now;
    debugPrint(
      '[BusinessFcmService] register attempt. '
      'reason=$reason platform=${defaultTargetPlatform.name}',
    );
    try {
      await _repository.registerBusinessDeviceToken(
        token: token,
        platform: defaultTargetPlatform.name,
      );
      _lastRegisteredToken = token;
      debugPrint('[BusinessFcmService] register success. reason=$reason');
    } catch (error) {
      debugPrint(
        '[BusinessFcmService] register failure. '
        'reason=$reason error=$error',
      );
    }
  }
}
