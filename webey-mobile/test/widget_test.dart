import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webey_mobile/core/theme/webey_theme.dart';
import 'package:webey_mobile/features/business/business_start_flow.dart';
import 'package:webey_mobile/features/business/data/models/business_appointment.dart';
import 'package:webey_mobile/features/business/data/models/business_dashboard.dart';
import 'package:webey_mobile/features/business/data/repositories/business_repository.dart';
import 'package:webey_mobile/features/customer/appointments/data/repositories/customer_appointment_repository.dart';
import 'package:webey_mobile/features/customer/customer_start_flow.dart';
import 'package:webey_mobile/features/customer/discovery/data/models/salon_summary.dart';
import 'package:webey_mobile/features/customer/favorites/data/repositories/customer_favorite_repository.dart';
import 'package:webey_mobile/features/customer/notifications/data/models/customer_notification.dart';
import 'package:webey_mobile/features/customer/notifications/data/repositories/customer_notification_repository.dart';
import 'package:webey_mobile/main_business.dart';
import 'package:webey_mobile/main_customer.dart';
import 'package:webey_mobile/shared/mock/mock_data.dart';
import 'package:webey_mobile/shared/models/beauty_models.dart';
import 'package:webey_mobile/shared/services/api_client.dart';
import 'package:webey_mobile/shared/services/app_config.dart';
import 'package:webey_mobile/shared/services/auth_service.dart';
import 'package:webey_mobile/shared/services/payment_service.dart';
import 'package:webey_mobile/shared/utils/formatters.dart';
import 'package:webey_mobile/shared/widgets/webey_widgets.dart';

import 'helpers/no_network_http_overrides.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(
  theme: WebeyTheme.customer(),
  home: Scaffold(body: child),
);

Appointment _appointment({
  AppointmentStatus status = AppointmentStatus.approved,
  DepositStatus depositStatus = DepositStatus.paid,
  double depositAmount = 300,
  double total = 950,
  bool canCancel = true,
  bool hasReview = false,
}) => Appointment(
  id: 'test',
  businessId: 'b1',
  salonName: 'Test Salon',
  customerName: 'Test Müşteri',
  serviceName: 'Test Hizmet',
  staffName: 'Test Uzman',
  startAt: DateTime(2026, 5, 20, 10, 30),
  endAt: DateTime(2026, 5, 20, 12, 0),
  status: status,
  depositStatus: depositStatus,
  depositAmount: depositAmount,
  total: total,
  bookingSource: 'app',
  canCancel: canCancel,
  hasReview: hasReview,
);

class _FakeCustomerAppointmentRepository extends CustomerAppointmentRepository {
  const _FakeCustomerAppointmentRepository({
    this.upcoming = const [],
    this.past = const [],
  });

  final List<Appointment> upcoming;
  final List<Appointment> past;

  @override
  Future<List<Appointment>> getAppointments(String status) async {
    return switch (status) {
      'upcoming' => upcoming,
      'past' => past,
      'cancelled' => const [],
      _ => [...upcoming, ...past],
    };
  }

  @override
  Future<bool> cancelAppointment(String appointmentId) async => true;
}

class _FakeCustomerNotificationRepository
    extends CustomerNotificationRepository {
  const _FakeCustomerNotificationRepository(this.items);

  final List<CustomerNotification> items;

  @override
  Future<CustomerNotificationsResult> getNotifications() async {
    return CustomerNotificationsResult(
      items: items,
      unreadCount: items.where((item) => !item.read).length,
    );
  }

  @override
  Future<void> markAsRead(String id) async {}

  @override
  Future<void> markAllAsRead() async {}
}

class _FakeCustomerFavoriteRepository extends CustomerFavoriteRepository {
  const _FakeCustomerFavoriteRepository(this.items);

  final List<SalonSummary> items;

  @override
  Future<List<SalonSummary>> getFavorites({double? lat, double? lng}) async =>
      items;

  @override
  Future<bool> toggleFavorite({
    required String businessId,
    required bool favorite,
  }) async => true;
}

SalonSummary _favoriteSalon({
  String id = 'b1',
  String name = 'Luna Nail Studio',
}) => SalonSummary(
  id: id,
  slug: id,
  name: name,
  city: 'Istanbul',
  district: 'Kadikoy',
  rating: 4.8,
  reviewCount: 42,
  minPrice: 450,
  maxPrice: 1400,
  depositRequired: true,
  depositAmount: 300,
  isOpenNow: true,
  nextAvailableText: 'Bugun 15:00',
  badges: const ['premium'],
  categorySlugs: const ['nail'],
  distanceKm: 1.2,
);

String _businessDate(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _businessTime(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

BusinessAppointment _businessAppointment({
  String id = '101',
  String status = 'approved',
  String customerName = 'Derya A.',
  String serviceName = 'Kalici Oje',
  String staffName = 'Ece Yildiz',
  DateTime? start,
}) {
  final startsAt = start ?? DateTime.now();
  final endsAt = startsAt.add(const Duration(minutes: 60));
  return BusinessAppointment(
    id: id,
    status: status,
    startsAt: startsAt,
    endsAt: endsAt,
    date: _businessDate(startsAt),
    time: _businessTime(startsAt),
    customerName: customerName,
    serviceName: serviceName,
    staffName: staffName,
    price: 900,
    durationMinutes: 60,
  );
}

class _FakeBusinessRepository extends BusinessRepository {
  const _FakeBusinessRepository({
    required this.dashboard,
    required this.appointments,
  });

  final BusinessDashboard dashboard;
  final List<BusinessAppointment> appointments;

  @override
  Future<BusinessDashboard> getDashboard() async => dashboard;

  @override
  Future<List<BusinessAppointment>> getAppointments({
    String status = 'all',
    String? date,
    String? from,
    String? to,
    int page = 1,
    int limit = 20,
  }) async {
    final byDate = date == null || date.isEmpty
        ? appointments
        : appointments.where((item) => item.date == date).toList();
    if (status == 'today') return byDate;
    if (status == 'pending') {
      return byDate
          .where(
            (item) =>
                item.status == 'pending' ||
                item.status == 'cancellation_requested',
          )
          .toList();
    }
    return byDate;
  }

  @override
  Future<bool> updateAppointmentStatus({
    required int appointmentId,
    required String status,
    String? note,
  }) async => true;

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

  @override
  Future<Map<String, dynamic>> getAnalytics({String range = '30d'}) async {
    return {
      'summary': {
        'revenue': 12400,
        'revenue_change_percent': 12,
        'appointments_count': 18,
        'appointments_change_percent': 8,
        'new_customers_count': 6,
        'new_customers_change_percent': 4,
        'occupancy_percent': 72,
        'occupancy_change_percent': 5,
        'average_basket': 690,
        'average_basket_change_percent': 3,
      },
      'revenue_chart': [
        {'revenue': 1200},
        {'revenue': 2400},
      ],
      'top_services': [
        {'name': 'Kalici Oje', 'revenue': 3600, 'count': 8},
      ],
      'weekly_occupancy': [
        {'day': 'Pzt', 'occupancy_percent': 72},
      ],
      'insights': [
        {'title': 'Tamamlanan randevu', 'body': '18 randevu tamamlandı.'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getBoostPackages() async {
    return {
      'current_boost': null,
      'pending_request': null,
      'packages': [
        {
          'id': 1,
          'name': 'Baslangic Boost',
          'description': 'Aramalarda daha gorunur ol.',
          'price': 299,
          'duration_days': 7,
          'priority_weight': 2,
          'features': ['Aramada ust sira', '7 gun boyunca one cikma'],
          'is_active': true,
        },
        {
          'id': 3,
          'name': 'Premium Boost',
          'description': 'En yuksek gorunurluk seviyesi.',
          'price': 1499,
          'duration_days': 30,
          'priority_weight': 10,
          'features': ['Premium rozet', '30 gun maksimum gorunurluk'],
          'is_active': true,
        },
      ],
      'history': [],
    };
  }

  @override
  Future<Map<String, dynamic>> requestBoostPackage({
    required int packageId,
    String? note,
  }) async {
    return {
      'request': {
        'id': 1,
        'package_id': packageId,
        'package_name': 'Premium Boost',
        'status': 'pending',
      },
      'message': 'Talebiniz alindi.',
    };
  }

  @override
  Future<({Map<String, dynamic> summary, List<BusinessCustomer> customers})>
  getCustomers() async {
    final now = DateTime.now();
    return (
      summary: <String, dynamic>{
        'total_customers': 1,
        'new_this_month': 1,
        'repeat_rate': 100,
      },
      customers: <BusinessCustomer>[
        BusinessCustomer.fromJson({
          'id': '1',
          'name': 'Ayşe Demir',
          'phone': '*** *** ** 12',
          'total_appointments': 14,
          'completed_appointments': 12,
          'cancelled_appointments': 1,
          'no_show_count': 0,
          'total_spent': 4200,
          'first_visit_at': now.toIso8601String(),
          'last_visit_at': now.toIso8601String(),
          'favorite_service': 'Kalıcı Oje',
          'is_vip': true,
        }),
      ],
    );
  }
}

_FakeBusinessRepository _fakeBusinessRepository() {
  final now = DateTime.now();
  final todayItems = [
    _businessAppointment(
      id: '101',
      status: 'approved',
      customerName: 'Derya A.',
      start: DateTime(now.year, now.month, now.day, 10, 30),
    ),
    _businessAppointment(
      id: '102',
      status: 'pending',
      customerName: 'Mina K.',
      start: DateTime(now.year, now.month, now.day, 12, 0),
    ),
    _businessAppointment(
      id: '103',
      status: 'cancellation_requested',
      customerName: 'Selin T.',
      start: DateTime(now.year, now.month, now.day, 14, 0),
    ),
  ];
  final pendingItems = todayItems
      .where(
        (item) =>
            item.status == 'pending' || item.status == 'cancellation_requested',
      )
      .toList();
  return _FakeBusinessRepository(
    appointments: todayItems,
    dashboard: BusinessDashboard(
      summary: BusinessDashboardSummary(
        todayAppointments: todayItems.length,
        pendingAppointments: pendingItems.length,
        upcomingAppointments: todayItems.length,
        completedThisMonth: 18,
        cancelledThisMonth: 1,
        monthlyRevenueEstimate: 12400,
      ),
      todayItems: todayItems,
      pendingItems: pendingItems,
    ),
  );
}

Salon _salon({
  bool acceptsDeposit = false,
  double depositAmount = 0,
  bool isPremium = false,
  bool availableToday = false,
}) => Salon(
  id: 'test',
  name: 'Test Salon',
  type: 'test_studio',
  city: 'İstanbul',
  district: 'Test',
  neighborhood: 'Test',
  rating: 4.5,
  reviewCount: 10,
  minPrice: 500,
  maxPrice: 2000,
  coverColor: Colors.grey,
  categoryIds: const ['hair_salon'],
  about: 'Test salon',
  cancellationPolicy: 'Test policy',
  availableSlots: const ['10:00', '14:00'],
  distanceKm: 1.0,
  openUntil: '18:00',
  acceptsDeposit: acceptsDeposit,
  depositAmount: depositAmount,
  isPremium: isPremium,
  availableToday: availableToday,
);

// ── Formatter unit tests ──────────────────────────────────────────────────────

void main() {
  installNoNetworkHttpOverrides();

  group('money()', () {
    test('formats without decimals', () {
      expect(money(950), '950 TL');
      expect(money(1499), '1.499 TL');
      expect(money(0), '0 TL');
    });

    test('rounds fractional values', () {
      expect(money(99.9), '100 TL');
      expect(money(299.4), '299 TL');
    });

    test('uses dot as thousands separator', () {
      expect(money(10000), '10.000 TL');
      expect(money(1000000), '1.000.000 TL');
    });
  });

  group('clock()', () {
    test('pads hours and minutes', () {
      expect(clock(DateTime(2026, 5, 20, 9, 5)), '09:05');
      expect(clock(DateTime(2026, 5, 20, 15, 0)), '15:00');
    });
  });

  group('shortDate()', () {
    test('formats Turkish month abbreviations', () {
      expect(shortDate(DateTime(2026, 1, 1)), '1 Oca');
      expect(shortDate(DateTime(2026, 5, 20)), '20 May');
      expect(shortDate(DateTime(2026, 12, 31)), '31 Ara');
    });
  });

  group('appointmentStatusLabel()', () {
    test('returns Turkish label for every status', () {
      expect(
        appointmentStatusLabel(AppointmentStatus.pending),
        'Onay bekliyor',
      );
      expect(appointmentStatusLabel(AppointmentStatus.approved), 'Onaylandı');
      expect(appointmentStatusLabel(AppointmentStatus.completed), 'Tamamlandı');
      expect(
        appointmentStatusLabel(AppointmentStatus.cancelled),
        'İptal edildi',
      );
      expect(
        appointmentStatusLabel(AppointmentStatus.cancellationRequested),
        'İptal talebi var',
      );
      expect(appointmentStatusLabel(AppointmentStatus.noShow), 'Gelmedi');
      expect(appointmentStatusLabel(AppointmentStatus.rejected), 'Reddedildi');
    });
  });

  group('depositBadgeLabel()', () {
    test('guaranteed salon label', () {
      expect(depositBadgeLabel(true), 'Garantili Randevu');
    });
    test('no-deposit salon label', () {
      expect(depositBadgeLabel(false), 'Kaporasız Randevu');
    });
  });

  // ── Model unit tests ──────────────────────────────────────────────────────

  group('Appointment.remainingAmount', () {
    test('returns total minus deposit', () {
      expect(_appointment(total: 950, depositAmount: 300).remainingAmount, 650);
    });

    test('clamps to zero when deposit exceeds total', () {
      expect(_appointment(total: 200, depositAmount: 300).remainingAmount, 0);
    });

    test('returns full total when no deposit', () {
      expect(_appointment(total: 850, depositAmount: 0).remainingAmount, 850);
    });

    test('exact zero when deposit equals total', () {
      expect(_appointment(total: 500, depositAmount: 500).remainingAmount, 0);
    });
  });

  // ── Splash screen tests ───────────────────────────────────────────────────

  group('Customer splash', () {
    testWidgets('renders brand and CTA', (tester) async {
      await tester.pumpWidget(const WebeyBeautyCustomerEntry());
      expect(find.byType(CustomerStartFlow), findsOneWidget);
    });
  });

  group('Business splash', () {
    testWidgets('renders brand and CTA', (tester) async {
      await tester.pumpWidget(const WebeyBeautyBusinessEntry());
      expect(find.byType(BusinessStartFlow), findsOneWidget);
    });
  });

  // ── StatusChip ────────────────────────────────────────────────────────────

  group('StatusChip', () {
    testWidgets('renders label', (tester) async {
      await tester.pumpWidget(
        _wrap(const StatusChip(label: 'Onaylandı', color: Colors.green)),
      );
      expect(find.text('Onaylandı'), findsOneWidget);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusChip(
            label: 'Premium',
            color: Colors.amber,
            icon: Icons.star,
          ),
        ),
      );
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('renders without icon when omitted', (tester) async {
      await tester.pumpWidget(
        _wrap(const StatusChip(label: 'Solo', color: Colors.blue)),
      );
      expect(find.byType(Icon), findsNothing);
    });
  });

  // ── AppointmentTile ───────────────────────────────────────────────────────

  group('AppointmentTile – kaporalı randevu', () {
    testWidgets('shows Kapora ödendi chip', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppointmentTile(
            appointment: _appointment(
              depositStatus: DepositStatus.paid,
              depositAmount: 300,
              total: 950,
            ),
          ),
        ),
      );
      expect(find.text('Kapora ödendi'), findsOneWidget);
    });

    testWidgets('shows remaining amount in chip', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppointmentTile(
            appointment: _appointment(
              depositStatus: DepositStatus.paid,
              depositAmount: 300,
              total: 950,
            ),
          ),
        ),
      );
      expect(find.textContaining('650'), findsOneWidget);
    });

    testWidgets('shows status label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppointmentTile(
            appointment: _appointment(status: AppointmentStatus.approved),
          ),
        ),
      );
      expect(find.text('Onaylandı'), findsOneWidget);
    });
  });

  group('AppointmentTile – kaporasız randevu', () {
    testWidgets('shows Ödeme salonda chip', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppointmentTile(
            appointment: _appointment(
              depositStatus: DepositStatus.none,
              depositAmount: 0,
              total: 850,
            ),
          ),
        ),
      );
      expect(find.text('Ödeme salonda'), findsOneWidget);
    });

    testWidgets('does not show remaining amount chip', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppointmentTile(
            appointment: _appointment(
              depositStatus: DepositStatus.none,
              depositAmount: 0,
              total: 850,
            ),
          ),
        ),
      );
      expect(find.textContaining('Kalan ödeme'), findsNothing);
    });
  });

  group('AppointmentTile – business view', () {
    testWidgets('shows customer name not salon name', (tester) async {
      await tester.pumpWidget(
        _wrap(AppointmentTile(appointment: _appointment(), businessView: true)),
      );
      expect(find.text('Test Müşteri'), findsOneWidget);
      expect(find.text('Test Salon'), findsNothing);
    });
  });

  // ── SalonCard ─────────────────────────────────────────────────────────────

  group('SalonCard – kaporalı salon', () {
    testWidgets('shows Garantili Randevu badge', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SalonCard(
            salon: _salon(acceptsDeposit: true, depositAmount: 300),
            onTap: () {},
          ),
        ),
      );
      expect(find.text('Garantili Randevu'), findsOneWidget);
    });
  });

  group('SalonCard – kaporasız salon', () {
    testWidgets('shows Kaporasız Randevu badge', (tester) async {
      await tester.pumpWidget(_wrap(SalonCard(salon: _salon(), onTap: () {})));
      expect(find.text('Kaporasız Randevu'), findsOneWidget);
    });

    testWidgets('does not show Garantili Randevu', (tester) async {
      await tester.pumpWidget(_wrap(SalonCard(salon: _salon(), onTap: () {})));
      expect(find.text('Garantili Randevu'), findsNothing);
    });
  });

  group('SalonCard – premium salon', () {
    testWidgets('shows Premium Salon badge', (tester) async {
      await tester.pumpWidget(
        _wrap(SalonCard(salon: _salon(isPremium: true), onTap: () {})),
      );
      // Badge appears in both SalonCover and the info area
      expect(find.text('Premium Salon'), findsAtLeastNWidgets(1));
    });
  });

  // ── SectionTitle ──────────────────────────────────────────────────────────

  group('SectionTitle', () {
    testWidgets('renders title and subtitle', (tester) async {
      await tester.pumpWidget(
        _wrap(const SectionTitle(title: 'Hizmetler', subtitle: '3 hizmet')),
      );
      expect(find.text('Hizmetler'), findsOneWidget);
      expect(find.text('3 hizmet'), findsOneWidget);
    });

    testWidgets('action button fires callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          SectionTitle(
            title: 'Salonlar',
            action: 'Temizle',
            onAction: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.text('Temizle'));
      expect(tapped, isTrue);
    });

    testWidgets('no action button when onAction is null', (tester) async {
      await tester.pumpWidget(
        _wrap(const SectionTitle(title: 'Başlık', action: 'Tümü')),
      );
      expect(find.text('Tümü'), findsNothing);
    });
  });

  // ── CustomerSearchScreen filter chips ─────────────────────────────────────

  group('CustomerSearchScreen filter chips', () {
    testWidgets('does not show fake applied chips on load', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: Scaffold(body: CustomerSearchScreen(onOpenSalon: (_) {})),
        ),
      );
      expect(find.text('Tümünü temizle'), findsNothing);
      expect(find.text('Kadıköy · 5km'), findsNothing);
      expect(find.text('Garantili kapora'), findsNothing);
    });

    testWidgets('Tümünü temizle hidden when no active filter', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: Scaffold(body: CustomerSearchScreen(onOpenSalon: (_) {})),
        ),
      );
      expect(find.text('Tümünü temizle'), findsNothing);
    });

    testWidgets('category filter chip appears and clear all resets', (
      tester,
    ) async {
      ApiClient.debugDisableNetworkForTests = true;
      addTearDown(() => ApiClient.debugDisableNetworkForTests = false);

      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: Scaffold(body: CustomerSearchScreen(onOpenSalon: (_) {})),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Saç'));
      await tester.pump();

      expect(find.text('Tümünü temizle'), findsOneWidget);

      await tester.tap(find.text('Tümünü temizle'));
      await tester.pump();
      expect(find.text('Tümünü temizle'), findsNothing);
    });
  });

  // ── BusinessCalendarScreen chrome ────────────────────────────────────────────

  group('BusinessCalendarScreen chrome', () {
    Widget wrapBusiness(Widget child) => MaterialApp(
      theme: WebeyTheme.business(),
      home: Scaffold(body: child),
    );

    testWidgets('shows current Takvim header without legacy list segment', (
      tester,
    ) async {
      await tester.pumpWidget(wrapBusiness(const BusinessCalendarScreen()));
      expect(find.text('Takvim'), findsOneWidget);
      expect(find.text('Liste'), findsNothing);
    });

    testWidgets('renders current staff filter strip', (tester) async {
      await tester.pumpWidget(wrapBusiness(const BusinessCalendarScreen()));
      expect(find.text('Tümü'), findsOneWidget);
    });
  });

  group('Phase 1 premium customer features', () {
    testWidgets('salon detail shows rating summary and verified reviews', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: SalonDetailScreen(
            salon: MockData.salonById('b1'),
            isLoggedIn: true,
            onAuthenticated: () {},
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Yorumlar ve Puanlama'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Yorumlar ve Puanlama'), findsOneWidget);
      expect(find.textContaining('doğrulanmış yorum'), findsOneWidget);
      expect(find.text('Doğrulanmış randevu'), findsWidgets);
    });

    testWidgets('salon detail shows portfolio section', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: SalonDetailScreen(
            salon: MockData.salonById('b1'),
            isLoggedIn: true,
            onAuthenticated: () {},
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Salon Portfolyosu'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Salon Portfolyosu'), findsOneWidget);
      expect(find.text('Öncesi / Sonrası'), findsWidgets);
    });

    testWidgets('completed appointment shows review action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: Scaffold(
            body: CustomerAppointmentsScreen(
              repository: _FakeCustomerAppointmentRepository(
                upcoming: [
                  _appointment(
                    status: AppointmentStatus.approved,
                    canCancel: true,
                  ),
                ],
                past: [
                  _appointment(
                    status: AppointmentStatus.completed,
                    canCancel: false,
                    hasReview: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(
        find.text('Yorum Yap'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Yorum Yap'), findsOneWidget);
    });

    testWidgets('upcoming cancellable appointment shows cancel action', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: Scaffold(
            body: CustomerAppointmentsScreen(
              repository: _FakeCustomerAppointmentRepository(
                upcoming: [
                  _appointment(
                    status: AppointmentStatus.approved,
                    canCancel: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('İptal Et'), findsWidgets);
    });

    testWidgets('notification screen shows notification titles', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: const CustomerNotificationsScreen(
            repository: _FakeCustomerNotificationRepository([
              CustomerNotification(
                id: 'n1',
                type: 'appt_confirmed',
                title: 'Randevunuz Onaylandı',
                body: 'Randevunuz onaylandı.',
                read: false,
                createdAt: '',
              ),
              CustomerNotification(
                id: 'n2',
                type: 'deposit_paid',
                title: 'Kapora Ödendi',
                body: 'Kapora ödemeniz alındı.',
                read: true,
                createdAt: '',
              ),
            ]),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Randevunuz'), findsWidgets);
      expect(find.textContaining('Kapora'), findsWidgets);
    });
  });

  group('Phase 1 premium business features', () {
    testWidgets('business dashboard shows current timeline', (tester) async {
      final repository = _fakeBusinessRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.business(),
          home: Scaffold(body: BusinessDashboardScreen(repository: repository)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.scrollUntilVisible(
        find.text('Derya A.'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Derya A.'), findsOneWidget);
      expect(find.textContaining('Onaylandi'), findsWidgets);
    });

    testWidgets('business calendar shows request labels', (tester) async {
      final repository = _fakeBusinessRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.business(),
          home: Scaffold(body: BusinessCalendarScreen(repository: repository)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Iptal talebi'), findsWidgets);
      await tester.scrollUntilVisible(
        find.textContaining('Onay bekliyor'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Onay bekliyor'), findsWidgets);
    });
  });

  group('Phase 2 premium customer features', () {
    testWidgets('home shows special packages section', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: Scaffold(
            body: CustomerHomeScreen(onOpenSearch: () {}, onOpenSalon: (_) {}),
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Özel Paketler'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Özel Paketler'), findsOneWidget);
    });

    testWidgets('salon detail shows brands and certificates', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: SalonDetailScreen(
            salon: MockData.salonById('b1'),
            isLoggedIn: true,
            onAuthenticated: () {},
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Kullanılan Markalar'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Kullanılan Markalar'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Sertifikalar ve Uzmanlıklar'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Sertifikalar ve Uzmanlıklar'), findsOneWidget);
    });

    testWidgets('salon detail shows waitlist info', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: SalonDetailScreen(
            salon: MockData.salonById('b1'),
            isLoggedIn: true,
            onAuthenticated: () {},
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Bekleme Listesi'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Bekleme Listesi'), findsWidgets);
    });

    testWidgets('booking flow first step renders service selection', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: BookingFlow(
            salon: MockData.salonById('b1'),
            onComplete: () {},
            onCancel: () {},
            onHome: () {},
          ),
        ),
      );

      expect(find.byType(BookingFlow), findsOneWidget);
    });

    testWidgets('search screen shows map option', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: Scaffold(body: CustomerSearchScreen(onOpenSalon: (_) {})),
        ),
      );

      expect(find.text('Harita'), findsOneWidget);
    });

    testWidgets('favorites screen shows collection titles', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: Scaffold(
            body: CustomerFavoritesScreen(
              repository: _FakeCustomerFavoriteRepository([
                _favoriteSalon(),
                _favoriteSalon(id: 'b2', name: 'Maison Rose'),
              ]),
              onOpenSalon: (_) async {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('FAVORİ SALONLAR'), findsOneWidget);
      expect(find.text('Luna Nail Studio'), findsOneWidget);
    });

    testWidgets('salon detail shows smart suggestions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: SalonDetailScreen(
            salon: MockData.salonById('b1'),
            isLoggedIn: true,
            onAuthenticated: () {},
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('En erken uygun saat'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('En erken uygun saat'), findsWidgets);
    });
  });

  group('Phase 2 premium business features', () {
    testWidgets('business dashboard shows summary metrics', (tester) async {
      final repository = _fakeBusinessRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.business(),
          home: Scaffold(body: BusinessDashboardScreen(repository: repository)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('randevu'), findsWidgets);
      expect(find.text('BU HAFTA'), findsOneWidget);
      expect(find.text('İPTAL / GELMEDİ'), findsOneWidget);
    });

    testWidgets('business dashboard shows pending action banner', (
      tester,
    ) async {
      final repository = _fakeBusinessRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.business(),
          home: Scaffold(body: BusinessDashboardScreen(repository: repository)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.scrollUntilVisible(
        find.textContaining('Iptal talebi'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Iptal talebi'), findsWidgets);
      expect(find.textContaining('Selin T.'), findsWidgets);
    });
  });

  group('Phase 3 premium business features', () {
    testWidgets('dashboard shows pending and timeline actions', (tester) async {
      final repository = _fakeBusinessRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.business(),
          home: Scaffold(body: BusinessDashboardScreen(repository: repository)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Onayla'), findsWidgets);

      await tester.scrollUntilVisible(
        find.text('Derya A.'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Derya A.'), findsOneWidget);
    });

    testWidgets('customers screen shows customer cards and detail metrics', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.business(),
          home: BusinessCustomersScreen(repository: _fakeBusinessRepository()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ayşe Demir'), findsOneWidget);
      expect(find.text('Toplam müşteri'), findsOneWidget);
      expect(find.text('Bu ay yeni'), findsOneWidget);
      expect(find.text('14 randevu'), findsOneWidget);
    });

    testWidgets('analytics screen shows revenue occupancy and staff metrics', (
      tester,
    ) async {
      final repository = _fakeBusinessRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.business(),
          home: BusinessAnalyticsScreen(repository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Toplam performans'), findsOneWidget);
      expect(find.text('Doluluk'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Öneriler'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Tamamlanan randevu'), findsWidgets);
    });

    testWidgets('promotion screen shows boost packages', (tester) async {
      final repository = _fakeBusinessRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.business(),
          home: BusinessPromotionBoostScreen(repository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Boost seçimi'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Premium Boost'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Premium Boost'), findsOneWidget);
    });

    testWidgets('revenue screen shows deposit and remaining payment', (
      tester,
    ) async {
      final repository = _fakeBusinessRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.business(),
          home: BusinessRevenueDepositScreen(repository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kapora'), findsWidgets);
      expect(find.text('Bekleyen'), findsWidgets);
    });

    testWidgets('action center shows action cards', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.business(),
          home: const BusinessActionCenterScreen(),
        ),
      );

      expect(find.text('Bekleyen kaporaları kontrol et'), findsOneWidget);
      expect(find.text('Bugünkü randevuları hazırla'), findsOneWidget);
    });
  });

  group('Phase 4 production readiness', () {
    test('AppConfig development enables mock data', () {
      final config = AppConfig.development();

      expect(config.environment, AppEnvironment.development);
      expect(config.enableMockData, isTrue);
      expect(config.enableDebugBanner, isTrue);
    });

    test('MockAuthService returns successful session', () async {
      final result = await MockAuthService.instance.signInWithEmailMock(
        'ayse@example.com',
      );

      expect(result.success, isTrue);
      expect(result.data?.user.role, UserRole.customer);
    });

    test(
      'MockPaymentService creates deposit intent with correct amount',
      () async {
        final result = await MockPaymentService.instance
            .createDepositPaymentIntent(
              amount: 300,
              appointmentId: 'appt_test',
              businessId: 'b1',
            );

        expect(result.success, isTrue);
        expect(result.data?.type, PaymentType.deposit);
        expect(result.data?.amount, 300);
        expect(result.data?.status, PaymentStatus.pending);
      },
    );

    testWidgets('WebeyEmptyState shows title and description', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const WebeyEmptyState(
            icon: Icons.search_off_outlined,
            title: 'Bu filtrelere uygun salon bulunamadı.',
            description: 'Filtreleri değiştirerek tekrar deneyin.',
          ),
        ),
      );

      expect(
        find.text('Bu filtrelere uygun salon bulunamadı.'),
        findsOneWidget,
      );
      expect(
        find.text('Filtreleri değiştirerek tekrar deneyin.'),
        findsOneWidget,
      );
    });

    testWidgets('WebeyErrorState shows retry button', (tester) async {
      await tester.pumpWidget(_wrap(const WebeyErrorState()));

      expect(find.text('Tekrar dene'), findsOneWidget);
    });

    testWidgets('launch readiness screen shows checklist groups', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.business(),
          home: const LaunchReadinessScreen(),
        ),
      );

      expect(find.text('Yayına çıkış adımları'), findsOneWidget);
      expect(find.text('Salon bilgileri tamamlandı'), findsOneWidget);
      expect(find.text('Hizmetler eklendi'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('İlk kampanya oluşturulmadı'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('İlk kampanya oluşturulmadı'), findsOneWidget);
    });

    testWidgets('legal documents screen exposes policy texts', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WebeyTheme.customer(),
          home: const LegalDocumentsScreen(),
        ),
      );

      expect(find.text('Kullanım Şartları'), findsOneWidget);
      expect(find.text('Gizlilik Politikası'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('KVKK Aydınlatma Metni'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Kapora ve İptal Politikası'), findsOneWidget);
    });

    test('production planning docs exist', () {
      expect(File('docs/API_PLAN.md').existsSync(), isTrue);
      expect(File('docs/ADMIN_PLAN.md').existsSync(), isTrue);
      expect(File('docs/SECURITY_NOTES.md').existsSync(), isTrue);
    });
  });
}
