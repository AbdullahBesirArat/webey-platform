import 'package:flutter/material.dart';

import '../core/theme/webey_theme.dart';
import '../features/customer/customer_start_flow.dart';

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Webey Beauty',
      theme: WebeyTheme.customer(),
      home: const CustomerStartFlow(),
    );
  }
}
