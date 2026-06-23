import 'package:flutter/material.dart';

import 'app/business_app.dart';
import 'app/customer_app.dart';
import 'shared/services/app_config.dart';

void main() {
  AppConfig.configure(AppConfig.development());
  const appMode = String.fromEnvironment('APP_MODE', defaultValue: 'customer');
  runApp(appMode == 'business' ? const BusinessApp() : const CustomerApp());
}
