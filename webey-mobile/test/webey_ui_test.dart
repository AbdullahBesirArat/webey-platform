import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webey_mobile/core/theme/webey_theme.dart';
import 'package:webey_mobile/features/business/business_start_flow.dart';
import 'package:webey_mobile/features/business/data/repositories/business_repository.dart';

import 'helpers/no_network_http_overrides.dart';

Widget _wrapBusiness(Widget child) =>
    MaterialApp(theme: WebeyTheme.business(), home: child);

class _FakeBusinessRepository extends BusinessRepository {
  const _FakeBusinessRepository();

  @override
  Future<Map<String, dynamic>> getBusinessNotifications({
    int page = 1,
    int limit = 20,
    bool unreadOnly = false,
  }) async {
    return {
      'items': [
        {
          'id': 1,
          'type': 'appointment',
          'title': 'Yeni randevu',
          'body': 'Derya A. onay bekliyor',
          'created_at': DateTime.now().toIso8601String(),
          'is_read': false,
        },
      ],
    };
  }

  @override
  Future<int> markBusinessNotificationRead({
    int? notificationId,
    bool markAll = false,
  }) async {
    return 0;
  }

  @override
  Future<Map<String, dynamic>> getDepositHistory() async {
    return {
      'summary': {
        'month_total_collected': 12400,
        'month_deposit_collected': 4200,
        'pending_amount': 900,
        'refunded_amount': 0,
        'month_change_percent': 12,
      },
      'items': [
        {
          'label': 'Kapora alındı',
          'customer_name': 'Derya A.',
          'service_name': 'Kalici Oje',
          'amount': 300,
          'status': 'paid',
          'created_at': DateTime.now().toIso8601String(),
        },
      ],
    };
  }
}

void main() {
  installNoNetworkHttpOverrides();

  group('Business BottomNavigationBar', () {
    testWidgets('does not show Kapora tab', (tester) async {
      await tester.pumpWidget(_wrapBusiness(const BusinessShell()));
      final bottomNav = find.byType(BottomNavigationBar);
      expect(bottomNav, findsOneWidget);
      expect(
        find.descendant(of: bottomNav, matching: find.text('Kapora')),
        findsNothing,
      );
    });

    testWidgets('shows current primary tabs', (tester) async {
      await tester.pumpWidget(_wrapBusiness(const BusinessShell()));
      final bottomNav = find.byType(BottomNavigationBar);
      expect(bottomNav, findsOneWidget);
      expect(
        find.descendant(of: bottomNav, matching: find.text('Ana Sayfa')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bottomNav, matching: find.text('Takvim')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bottomNav, matching: find.text('Isletme')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bottomNav, matching: find.text('Bildirimler')),
        findsNothing,
      );
    });
  });

  group('BusinessNotificationsScreen', () {
    testWidgets('shows Tumunu okundu isaretle button', (tester) async {
      await tester.pumpWidget(
        _wrapBusiness(
          const BusinessNotificationsScreen(
            repository: _FakeBusinessRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tümünü okundu işaretle'), findsOneWidget);
    });
  });

  group('BusinessRevenueDepositScreen filters', () {
    testWidgets('shows 1 Gun filter', (tester) async {
      await tester.pumpWidget(
        _wrapBusiness(
          const BusinessRevenueDepositScreen(
            repository: _FakeBusinessRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kapora'), findsWidgets);
    });

    testWidgets('shows 1 Hafta filter', (tester) async {
      await tester.pumpWidget(
        _wrapBusiness(
          const BusinessRevenueDepositScreen(
            repository: _FakeBusinessRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bekleyen'), findsWidgets);
    });

    testWidgets('shows 1 Ay filter', (tester) async {
      await tester.pumpWidget(
        _wrapBusiness(
          const BusinessRevenueDepositScreen(
            repository: _FakeBusinessRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('İade'), findsWidgets);
    });
  });

  group('BusinessCalendarScreen', () {
    testWidgets('renders current calendar chrome', (tester) async {
      await tester.pumpWidget(
        _wrapBusiness(const Scaffold(body: BusinessCalendarScreen())),
      );
      expect(find.text('Takvim'), findsOneWidget);
      expect(find.text('Liste'), findsNothing);
    });
  });
}
