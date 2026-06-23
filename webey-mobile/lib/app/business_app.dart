import 'package:flutter/material.dart';

import '../core/theme/webey_theme.dart';
import '../features/business/business_start_flow.dart';

class BusinessApp extends StatelessWidget {
  const BusinessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Webey Beauty Business',
      theme: WebeyTheme.business(),
      home: const BusinessStartFlow(),
    );
  }
}
