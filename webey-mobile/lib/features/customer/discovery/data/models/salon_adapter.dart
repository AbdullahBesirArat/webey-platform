import 'package:flutter/material.dart';

import '../../../../../core/theme/webey_colors.dart';
import '../../../../../shared/models/beauty_models.dart';
import 'salon_detail.dart';
import 'salon_summary.dart';

extension SalonSummaryAdapter on SalonSummary {
  Salon toBeautySalon({Salon? fallback}) {
    final categories = categorySlugs.isNotEmpty
        ? categorySlugs
        : fallback?.categoryIds ?? const ['beauty_salon'];
    final min = minPrice ?? fallback?.minPrice ?? 0;
    final max = maxPrice ?? fallback?.maxPrice ?? min;
    final cover = coverImageUrl.isNotEmpty
        ? coverImageUrl
        : fallback?.coverImage ?? '';

    return Salon(
      id: id.isNotEmpty ? id : fallback?.id ?? '',
      name: name.isNotEmpty ? name : fallback?.name ?? 'Webey salon',
      type: categories.first,
      city: city ?? fallback?.city ?? '',
      district: district ?? fallback?.district ?? '',
      neighborhood: fallback?.neighborhood ?? '',
      rating: rating ?? fallback?.rating ?? 0,
      reviewCount: reviewCount,
      minPrice: min,
      maxPrice: max,
      coverColor: fallback?.coverColor ?? _coverColor(id),
      categoryIds: categories,
      about: description ?? fallback?.about ?? '',
      atelierNote: atelierNote ?? fallback?.atelierNote ?? '',
      cancellationPolicy: fallback?.cancellationPolicy ?? '',
      availableSlots: fallback?.availableSlots ?? const [],
      distanceKm: distanceKm ?? fallback?.distanceKm ?? 0,
      openUntil: fallback?.openUntil ?? '',
      description: description ?? fallback?.description,
      coverImage: cover,
      galleryImages: cover.isNotEmpty
          ? [cover]
          : fallback?.galleryImages ?? const [],
      address: address ?? fallback?.address,
      isPremium: isBoosted,
      acceptsDeposit: depositRequired,
      depositAmount: depositAmount ?? 0,
      workingHours: fallback?.workingHours ?? const {},
      campaign: nextAvailableText ?? fallback?.campaign,
      isFavorite: fallback?.isFavorite ?? false,
      availableToday: isOpenNow,
      isPublished: true,
      isVerified: fallback?.isVerified ?? false,
      trustBadges: badges,
      mapPoint: _validSalonMapPoint(latitude, longitude)
          ? SalonMapPoint(
              salonId: id,
              salonName: name,
              district: district ?? '',
              distance: distanceKm ?? 0,
              latitudeMock: latitude!,
              longitudeMock: longitude!,
              rating: rating ?? 0,
              startingPrice: min,
              acceptsDeposit: depositRequired,
              isPremium: isBoosted,
              isOpenToday: isOpenNow,
            )
          : fallback?.mapPoint,
    );
  }
}

/// 0,0 (Atlantik / "Null Island") veya null değerleri map marker olarak göstermez.
/// Türkiye sınırları yaklaşık 35.5..42.5 lat, 25.5..45 lng — bu aralık dışındakileri
/// de "konum bilgisi yok" sayarız.
bool _validSalonMapPoint(double? lat, double? lng) {
  if (lat == null || lng == null) return false;
  if (lat == 0 && lng == 0) return false;
  if (lat.abs() < 0.0001 && lng.abs() < 0.0001) return false;
  return true;
}

extension SalonDetailAdapter on SalonDetail {
  Salon toBeautySalon({Salon? fallback}) {
    final base = salon.toBeautySalon(fallback: fallback);
    final galleryImages = <String>[
      if (salon.coverImageUrl.isNotEmpty) salon.coverImageUrl,
      ...gallery,
    ].where((url) => url.isNotEmpty).toSet().toList();

    final hours = <String, String>{};
    for (final hour in businessHours) {
      hours[_dayLabel(hour.day)] = hour.isOpen
          ? '${hour.openTime ?? ''} - ${hour.closeTime ?? ''}'.trim()
          : 'Kapalı';
    }

    return Salon(
      id: base.id,
      name: base.name,
      type: base.type,
      city: location?.city ?? base.city,
      district: location?.district ?? base.district,
      neighborhood: base.neighborhood,
      rating: reviewSummary.rating ?? base.rating,
      reviewCount: reviewSummary.reviewCount,
      minPrice: base.minPrice,
      maxPrice: base.maxPrice,
      coverColor: base.coverColor,
      categoryIds: base.categoryIds,
      about: base.about,
      atelierNote: base.atelierNote,
      cancellationPolicy: depositPolicy.description ?? base.cancellationPolicy,
      availableSlots: base.availableSlots,
      distanceKm: base.distanceKm,
      openUntil: base.openUntil,
      description: base.description,
      coverImage: galleryImages.isNotEmpty
          ? galleryImages.first
          : base.coverImage,
      galleryImages: galleryImages,
      address: location?.address ?? base.address,
      isPremium: base.isPremium,
      acceptsDeposit: depositPolicy.required,
      depositAmount: depositPolicy.amount ?? base.depositAmount,
      workingHours: hours.isNotEmpty ? hours : base.workingHours,
      campaign: base.campaign,
      isFavorite: base.isFavorite,
      availableToday: base.availableToday,
      isPublished: base.isPublished,
      isVerified: base.isVerified,
      trustBadges: base.trustBadges,
      mapPoint: _validSalonMapPoint(location?.latitude, location?.longitude)
          ? SalonMapPoint(
              salonId: base.id,
              salonName: base.name,
              district: location?.district ?? base.district,
              distance: base.distanceKm,
              latitudeMock: location!.latitude!,
              longitudeMock: location!.longitude!,
              rating: base.rating,
              startingPrice: base.minPrice,
              acceptsDeposit: base.acceptsDeposit,
              isPremium: base.isPremium,
              isOpenToday: base.availableToday,
            )
          : base.mapPoint,
    );
  }

  String _dayLabel(String day) {
    return switch (day) {
      'mon' => 'Pzt',
      'tue' => 'Sal',
      'wed' => 'Çar',
      'thu' => 'Per',
      'fri' => 'Cum',
      'sat' => 'Cmt',
      'sun' => 'Paz',
      _ => day,
    };
  }
}

Color _coverColor(String id) {
  final colors = [
    WebeyColors.blushRose,
    WebeyColors.goldLight,
    WebeyColors.warmCream,
    WebeyColors.borderSand,
  ];
  final hash = id.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
  return colors[hash % colors.length];
}
