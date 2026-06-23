import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'app/business_app.dart';
import 'core/app_info.dart';
import 'shared/services/app_config.dart';
import 'shared/services/business_fcm_service.dart';

/// Build izi — yeni APK'nın gerçekten kurulduğunu logcat'ten doğrulamak için.
const String kWebeyBusinessBuildStamp = '2026-06-05 onboarding-modal-rework';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppInfo.load();
  debugPrint('[WebeyBuild] flavor=business build=$kWebeyBusinessBuildStamp');
  AppConfig.configure(
    kReleaseMode ? AppConfig.production() : AppConfig.development(),
  );
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(
    businessFirebaseMessagingBackgroundHandler,
  );
  await BusinessFcmService.instance.init();
  runApp(const WebeyBeautyBusinessEntry());
}

class WebeyBeautyBusinessEntry extends StatelessWidget {
  const WebeyBeautyBusinessEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return const BusinessApp();
  }
}
