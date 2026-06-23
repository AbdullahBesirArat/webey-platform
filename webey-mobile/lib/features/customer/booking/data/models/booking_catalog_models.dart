import 'package:flutter/material.dart';

import '../../../../../core/theme/webey_colors.dart';
import '../../../discovery/data/models/salon_detail.dart';

/// Hizmet seçeneği — salon-detail API veya mock fallback.
class BookingServiceOption {
  const BookingServiceOption({
    required this.key,
    this.id,
    required this.name,
    this.description = '',
    this.durationLabel = '',
    required this.durationMinutes,
    required this.price,
    this.popular = false,
    this.fromApi = false,
  });

  final String key;
  final int? id;
  final String name;
  final String description;
  final String durationLabel;
  final int durationMinutes;
  final double price;
  final bool popular;
  final bool fromApi;

  bool get isBookable => id != null && id! > 0;

  factory BookingServiceOption.fromSalonService(SalonServiceDetail service) {
    final parsedId = int.tryParse(service.id);
    final duration = service.durationMin ?? 60;
    return BookingServiceOption(
      key: service.id.isNotEmpty ? service.id : 'service_${service.name}',
      id: parsedId,
      name: service.name,
      description: service.description ?? '',
      durationLabel: service.durationMin != null ? '$duration dk' : '',
      durationMinutes: duration,
      price: service.price ?? 0,
      fromApi: true,
    );
  }
}

/// Personel seçeneği — `any` için id null.
class BookingStaffOption {
  const BookingStaffOption({
    required this.key,
    this.id,
    required this.name,
    required this.role,
    this.rating,
    this.count,
    this.chips = const [],
    this.availability,
    this.initials = '',
    this.colorA = WebeyColors.primaryGold,
    this.colorB = const Color(0xFF8C6F38),
    this.isOnline = false,
    this.isAny = false,
    this.fromApi = false,
    this.profilePhotoUrl,
    this.profilePhotoVersion,
  });

  final String key;
  final int? id;
  final String name;
  final String role;
  final double? rating;
  final int? count;
  final List<String> chips;
  final String? availability;
  final String initials;
  final Color colorA;
  final Color colorB;
  final bool isOnline;
  final bool isAny;
  final bool fromApi;
  final String? profilePhotoUrl;
  final String? profilePhotoVersion;

  factory BookingStaffOption.any() {
    return const BookingStaffOption(
      key: 'any',
      name: 'Farketmez',
      role: 'Salon sizin için uygun bir uzman atar',
      isAny: true,
    );
  }

  factory BookingStaffOption.fromSalonStaff(SalonStaffDetail staff) {
    final parsedId = int.tryParse(staff.id);
    return BookingStaffOption(
      key: staff.id.isNotEmpty ? staff.id : 'staff_${staff.name}',
      id: parsedId,
      name: staff.name,
      role: 'Uzman',
      initials: _initials(staff.name),
      colorA: _colorFromHex(staff.color) ?? WebeyColors.primaryGold,
      colorB: WebeyColors.darkEspresso,
      fromApi: true,
      profilePhotoUrl: staff.profilePhotoUrl,
      profilePhotoVersion: staff.profilePhotoVersion,
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts
        .take(2)
        .map((part) => part.isEmpty ? '' : part.substring(0, 1).toUpperCase())
        .join();
  }

  static Color? _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var value = hex.replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return null;
    return Color(parsed);
  }
}
