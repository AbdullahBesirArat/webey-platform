import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'app/customer_app.dart';
import 'core/app_info.dart';
import 'shared/services/app_config.dart';
import 'shared/services/customer_fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppInfo.load();
  AppConfig.configure(
    kReleaseMode ? AppConfig.production() : AppConfig.development(),
  );
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(
    customerFirebaseMessagingBackgroundHandler,
  );
  await CustomerFcmService.instance.init();
  runApp(const WebeyBeautyCustomerEntry());
}

class WebeyBeautyCustomerEntry extends StatelessWidget {
  const WebeyBeautyCustomerEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomerApp();
  }
}
