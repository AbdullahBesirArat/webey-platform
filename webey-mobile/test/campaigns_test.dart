import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webey_mobile/features/business/data/models/business_campaign.dart';
import 'package:webey_mobile/features/customer/appointments/data/models/customer_appointment.dart';
import 'package:webey_mobile/features/customer/booking/data/models/booking_models.dart';
import 'package:webey_mobile/features/customer/discovery/data/models/salon_campaign.dart';
import 'package:webey_mobile/features/customer/discovery/data/models/salon_summary.dart';
import 'package:webey_mobile/features/customer/widgets/campaign_widgets.dart';

void main() {
  group('SalonCampaign.fromJson', () {
    test('parses display payload', () {
      final c = SalonCampaign.fromJson({
        'id': '7',
        'title': 'Hafta içi fırsatı',
        'badge': 'Hafta içi %15',
        'summary': 'Hafta içi tüm hizmetlerde %15 indirim',
        'condition_type': 'weekday',
        'discount_kind': 'percent',
        'discount_value': 15,
        'days_of_week': [1, 2, 3, 4, 5],
        'applies_to_all_services': true,
        'service_ids': <String>[],
      });
      expect(c, isNotNull);
      expect(c!.id, '7');
      expect(c.badge, 'Hafta içi %15');
      expect(c.daysOfWeek, [1, 2, 3, 4, 5]);
      expect(c.appliesToAllServices, isTrue);
      expect(c.hasQuote, isFalse);
    });

    test('parses booking quote payload', () {
      final c = SalonCampaign.fromJson({
        'id': 3,
        'title': 'İndirim',
        'discount_kind': 'percent',
        'discount_value': 15,
        'discount_amount': 60,
        'original_price': 400,
        'final_price': 340,
      });
      expect(c!.hasQuote, isTrue);
      expect(c.discountAmount, 60);
      expect(c.finalPrice, 340);
    });

    test('returns null for missing id / non-map', () {
      expect(SalonCampaign.fromJson(null), isNull);
      expect(SalonCampaign.fromJson({'title': 'x'}), isNull);
      expect(SalonCampaign.fromJson('nope'), isNull);
    });

    test('shortLabel derives when badge empty', () {
      final fixed = SalonCampaign.fromJson({
        'id': '1',
        'title': 't',
        'discount_kind': 'fixed',
        'discount_value': 100,
      });
      expect(fixed!.shortLabel, '100 TL indirim');
    });
  });

  group('SalonSummary campaign', () {
    test('attaches campaign when present', () {
      final s = SalonSummary.fromJson({
        'id': '44',
        'slug': 'x',
        'name': 'Demo',
        'campaign': {
          'id': '1',
          'title': 'Kampanya',
          'badge': '%15 indirim',
          'summary': 'Tüm hizmetlerde %15 indirim',
        },
      });
      expect(s.hasCampaign, isTrue);
      expect(s.campaign!.badge, '%15 indirim');
    });

    test('no campaign when absent', () {
      final s = SalonSummary.fromJson({'id': '1', 'slug': 'a', 'name': 'b'});
      expect(s.hasCampaign, isFalse);
      expect(s.campaign, isNull);
    });
  });

  group('BusinessCampaign', () {
    test('fromJson + toSaveBody round trips key fields', () {
      final c = BusinessCampaign.fromJson({
        'id': 5,
        'title': 'Saat fırsatı',
        'condition_type': 'hourly',
        'discount_kind': 'fixed',
        'discount_value': 100,
        'scope_type': 'selected_services',
        'service_ids': ['10', '11'],
        'services': [
          {'id': '10', 'name': 'Manikür'},
          {'id': '11', 'name': 'Pedikür'},
        ],
        'start_time': '12:00',
        'end_time': '17:00',
        'status': 'active',
        'state': 'active',
        'badge': '12:00–17:00 100 TL',
      });
      expect(c.id, 5);
      expect(c.serviceIds, [10, 11]);
      expect(c.serviceNames, ['Manikür', 'Pedikür']);
      expect(c.isActive, isTrue);
      final body = c.toSaveBody();
      expect(body['id'], 5);
      expect(body['discount_kind'], 'fixed');
      expect(body['service_ids'], [10, 11]);
      expect(body['status'], 'active');
    });

    test('all_services scope sends empty service_ids', () {
      const c = BusinessCampaign(
        title: 'Genel',
        scopeType: 'all_services',
        serviceIds: [1, 2],
      );
      expect(c.toSaveBody()['service_ids'], isEmpty);
    });

    test('parses professional status + performance fields', () {
      final c = BusinessCampaign.fromJson({
        'id': 9,
        'title': 'Hafta içi',
        'status': 'active',
        'customer_visibility_status': 'waiting_for_condition',
        'customer_visibility_message': 'Yarın müşterilere gösterilecek.',
        'lifecycle_status': 'active',
        'is_currently_eligible': false,
        'next_eligible_at': '2026-06-22T00:00:00+03:00',
        'scope_summary': '2 seçili hizmette',
        'validity_summary': 'Pzt–Cum · 09:00–18:00',
        'selected_services_count': 2,
        'performance': {
          'has_data': true,
          'booking_count': 8,
          'completed_count': 5,
          'total_discount_amount': 1240,
          'net_revenue_amount': 7860,
          'last_booking_at': '2026-06-19 10:00:00',
        },
      });
      expect(c.customerVisibilityStatus, 'waiting_for_condition');
      expect(c.isCurrentlyEligible, isFalse);
      expect(c.nextEligibleAt, '2026-06-22T00:00:00+03:00');
      expect(c.scopeSummary, '2 seçili hizmette');
      expect(c.performance!.hasData, isTrue);
      expect(c.performance!.bookingCount, 8);
      expect(c.performance!.completedCount, 5);
      expect(c.performance!.totalDiscountAmount, 1240);
      expect(c.performance!.netRevenueAmount, 7860);
    });

    test('toDuplicate copies conditions, clears id/dates, suffixes title', () {
      const c = BusinessCampaign(
        id: 5,
        title: 'Yıldız Paket %15',
        discountKind: 'percent',
        discountValue: 15,
        scopeType: 'selected_services',
        serviceIds: [10, 11],
        startDate: '2026-06-01',
        endDate: '2026-06-30',
        status: 'paused',
      );
      final d = c.toDuplicate();
      expect(d.id, isNull);
      expect(d.title, 'Yıldız Paket %15 kopyası');
      expect(d.startDate, isNull);
      expect(d.endDate, isNull);
      expect(d.serviceIds, [10, 11]);
      expect(d.status, 'active');
    });
  });

  group('SalonCampaign professional fields', () {
    test('parses scope/validity/eligibility', () {
      final c = SalonCampaign.fromJson({
        'id': '1',
        'title': 'K',
        'badge': '%15 indirim',
        'scope_summary': 'Tüm hizmetlerde',
        'validity_summary': 'Pzt–Cum · 09:00–18:00',
        'eligibility_now': false,
      });
      expect(c!.scopeSummary, 'Tüm hizmetlerde');
      expect(c.validitySummary, 'Pzt–Cum · 09:00–18:00');
      expect(c.eligibilityNow, isFalse);
    });

    test('eligibility defaults true when absent', () {
      final c = SalonCampaign.fromJson({'id': '1', 'title': 'K'});
      expect(c!.eligibilityNow, isTrue);
    });
  });

  group('Booking models campaign', () {
    test('lock result parses campaign + reason', () {
      final r = BookingLockResult.fromJson({
        'locked': true,
        'lock_token': 'a' * 48,
        'campaign': {
          'id': '1',
          'title': 'X',
          'discount_amount': 60,
          'final_price': 340,
        },
        'campaign_reason': null,
      });
      expect(r.campaign, isNotNull);
      expect(r.campaign!.finalPrice, 340);
    });

    test('book result parses snapshot + remaining', () {
      final r = BookingResult.fromJson({
        'appointment': {
          'id': '99',
          'status': 'pending',
          'original_amount': 400,
          'final_amount': 340,
          'remaining_amount': 255,
          'campaign': {'id': '1', 'title': 'X', 'discount_amount': 60},
        },
      });
      expect(r.originalAmount, 400);
      expect(r.finalAmount, 340);
      expect(r.remainingAmount, 255);
      expect(r.campaign, isNotNull);
    });
  });

  group('Salonda kalan (remaining) — final üzerinden', () {
    test('CustomerAppointment final + deposit → remaining = final - deposit', () {
      final a = CustomerAppointment.fromJson({
        'id': '1',
        'status': 'approved',
        'starts_at': '2026-06-22 13:00:00',
        'service': {'id': '5', 'name': 'Saç', 'price': 400},
        'original_amount': 400,
        'final_amount': 340,
        'remaining_amount': 170,
        'deposit': {'required': true, 'amount': 170, 'status': 'paid'},
      }).toAppointment();
      // total = final (340), depositAmount = 170 → remaining = 170 (NOT 400-170=230)
      expect(a.total, 340);
      expect(a.depositAmount, 170);
      expect(a.remainingAmount, 170);
    });

    test('remaining asla negatif olmaz (final < deposit)', () {
      final a = CustomerAppointment.fromJson({
        'id': '2',
        'status': 'approved',
        'starts_at': '2026-06-22 13:00:00',
        'service': {'id': '5', 'name': 'X', 'price': 250},
        'final_amount': 150,
        'deposit': {'required': true, 'amount': 200, 'status': 'paid'},
      }).toAppointment();
      expect(a.total, 150);
      expect(a.remainingAmount, 0); // clamp, negatif değil
    });

    test('kampanyasız randevu: total = hizmet fiyatı, remaining = price - deposit', () {
      final a = CustomerAppointment.fromJson({
        'id': '3',
        'status': 'approved',
        'starts_at': '2026-06-22 13:00:00',
        'service': {'id': '5', 'name': 'X', 'price': 400},
        'deposit': {'required': true, 'amount': 200, 'status': 'paid'},
      }).toAppointment();
      expect(a.total, 400); // final_amount yok → service price
      expect(a.remainingAmount, 200);
    });
  });

  group('Campaign widgets', () {
    testWidgets('CampaignBadge renders label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CampaignBadge(label: '%15 indirim'))),
      );
      expect(find.text('%15 indirim'), findsOneWidget);
    });

    testWidgets('CampaignSalonCard shows name, badge, summary', (tester) async {
      const campaign = SalonCampaign(
        id: '1',
        title: 'K',
        badge: '%20 indirim',
        summary: 'Tüm hizmetlerde %20 indirim',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CampaignSalonCard(
              name: 'Villa Bay',
              coverImageUrl: '',
              campaign: campaign,
              district: 'Kadıköy',
              rating: 4.8,
              reviewCount: 12,
              minPrice: 350,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('Villa Bay'), findsOneWidget);
      expect(find.text('%20 indirim'), findsOneWidget);
      expect(find.text('Tüm hizmetlerde %20 indirim'), findsOneWidget);
    });
  });
}
