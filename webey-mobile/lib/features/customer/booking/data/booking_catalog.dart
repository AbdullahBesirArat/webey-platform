import 'package:flutter/material.dart';

import 'booking_date_format.dart';
import 'models/booking_catalog_models.dart';
import '../../discovery/data/models/salon_detail.dart';

/// Salon-detail verisi + mock fallback birleşimi.
class BookingCatalog {
  BookingCatalog({
    List<BookingServiceOption>? services,
    List<BookingStaffOption>? staff,
  }) : services = services != null && services.isNotEmpty
           ? services
           : mockServices,
       staff = _composeStaff(staff),
       usesMockServices = services == null || services.isEmpty,
       usesMockStaff = staff == null || staff.isEmpty;

  factory BookingCatalog.fromSalonDetail(SalonDetail? detail) {
    if (detail == null) return BookingCatalog();

    final apiServices = detail.services
        .where((s) => s.name.isNotEmpty)
        .map(BookingServiceOption.fromSalonService)
        .toList();

    final apiStaff = detail.staff
        .where((s) => s.isActive && s.name.isNotEmpty)
        .map(BookingStaffOption.fromSalonStaff)
        .toList();

    return BookingCatalog(
      services: apiServices.isNotEmpty ? apiServices : null,
      staff: apiStaff.isNotEmpty ? apiStaff : null,
    );
  }

  final List<BookingServiceOption> services;
  final List<BookingStaffOption> staff;
  final bool usesMockServices;
  final bool usesMockStaff;

  BookingServiceOption? serviceByKey(String? key) {
    if (key == null) return null;
    for (final service in services) {
      if (service.key == key) return service;
    }
    return null;
  }

  BookingStaffOption? staffByKey(String? key) {
    if (key == null) return null;
    for (final member in staff) {
      if (member.key == key) return member;
    }
    return null;
  }

  BookingServiceOption get defaultService {
    final bookable = services.where((s) => s.isBookable);
    if (bookable.isNotEmpty) return bookable.first;
    return services.first;
  }

  BookingStaffOption get defaultStaff => staff.first;

  static List<BookingStaffOption> _composeStaff(
    List<BookingStaffOption>? staff,
  ) {
    if (staff != null && staff.isNotEmpty) {
      final hasAny = staff.any((s) => s.isAny);
      return hasAny ? staff : [BookingStaffOption.any(), ...staff];
    }
    return mockStaff;
  }

  static final List<BookingServiceOption> mockServices = [
    BookingServiceOption(
      key: 'sv1',
      id: BookingDateFormat.parseMockFallbackId('sv1'),
      name: 'Protez Tırnak + Kalıcı Oje',
      description: 'Premium jel uygulama ve kalıcı oje.',
      durationLabel: '90 dk',
      durationMinutes: 90,
      price: 1200,
      popular: true,
    ),
    BookingServiceOption(
      key: 'sv2',
      id: BookingDateFormat.parseMockFallbackId('sv2'),
      name: 'Kalıcı Oje',
      description: 'Uzun süre dayanıklı parlak görünüm.',
      durationLabel: '45 dk',
      durationMinutes: 45,
      price: 650,
    ),
    BookingServiceOption(
      key: 'sv3',
      id: BookingDateFormat.parseMockFallbackId('sv3'),
      name: 'Manikür',
      description: 'Klasik bakım ve şekillendirme.',
      durationLabel: '35 dk',
      durationMinutes: 35,
      price: 450,
    ),
    BookingServiceOption(
      key: 'sv4',
      id: BookingDateFormat.parseMockFallbackId('sv4'),
      name: 'Nail Art Tasarım',
      description: 'Kişiye özel desen ve detaylandırma.',
      durationLabel: '75 dk',
      durationMinutes: 75,
      price: 880,
    ),
  ];

  static final List<BookingStaffOption> mockStaff = [
    BookingStaffOption.any(),
    BookingStaffOption(
      key: 'st1',
      id: BookingDateFormat.parseMockFallbackId('st1'),
      name: 'Ece Yıldız',
      role: 'Nail Artist',
      rating: 4.9,
      count: 320,
      chips: const ['Protez Tırnak', 'Kalıcı Oje'],
      availability: 'Bugün 16:30 uygun',
      initials: 'EY',
      colorA: const Color(0xFFD4B574),
      colorB: const Color(0xFF8C6F38),
      isOnline: true,
    ),
    BookingStaffOption(
      key: 'st2',
      id: BookingDateFormat.parseMockFallbackId('st2'),
      name: 'Mina Acar',
      role: 'Kaş & Kirpik Uzmanı',
      rating: 4.8,
      count: 210,
      chips: const ['Kaş Tasarımı', 'Lifting'],
      availability: 'Yarın 11:00 uygun',
      initials: 'MA',
      colorA: const Color(0xFFB8964E),
      colorB: const Color(0xFF5d4a2c),
    ),
    BookingStaffOption(
      key: 'st3',
      id: BookingDateFormat.parseMockFallbackId('st3'),
      name: 'Selin Kara',
      role: 'Saç Tasarım Uzmanı',
      rating: 4.9,
      count: 460,
      chips: const ['Saç Kesim', 'Renk'],
      availability: 'Cuma 14:00 uygun',
      initials: 'SK',
      colorA: const Color(0xFFC7A26A),
      colorB: const Color(0xFF806440),
    ),
  ];
}
