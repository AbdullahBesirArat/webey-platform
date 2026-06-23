import 'package:flutter/foundation.dart';

class AppLogger {
  const AppLogger._();

  static void debug(String message) => _log('DEBUG', message);

  static void info(String message) => _log('INFO', message);

  static void warning(String message) => _log('WARN', message);

  static void error(String message, [Object? error]) {
    _log('ERROR', error == null ? message : '$message: $error');
  }

  static void _log(String level, String message) {
    assert(() {
      debugPrint('[Webey][$level] $message');
      return true;
    }());
    // Production builds can route this abstraction to Crashlytics/Sentry later.
  }
}
