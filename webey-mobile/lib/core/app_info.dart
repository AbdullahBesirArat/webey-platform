// lib/core/app_info.dart
//
// Uygulama sürümünü platform paket bilgisinden okuyan tek kaynak.
// `main_customer` / `main_business` içinde [load] çağrılır; sonra [version]
// senkron olarak okunabilir. pubspec `version:` değeri (örn. 1.0.0) otomatik
// yansır, böylece sürüm string'leri elle güncellenmek zorunda kalmaz.

import 'package:package_info_plus/package_info_plus.dart';

class AppInfo {
  const AppInfo._();

  static String version = '1.0.0';
  static String buildNumber = '1';

  static String get fullVersion =>
      buildNumber.isEmpty ? version : '$version+$buildNumber';

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) version = info.version;
      if (info.buildNumber.isNotEmpty) buildNumber = info.buildNumber;
    } catch (_) {
      // Paket bilgisi okunamazsa varsayılan sürüm kullanılır (örn. testlerde).
    }
  }
}
