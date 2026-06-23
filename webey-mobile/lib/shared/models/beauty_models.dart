import 'package:flutter/material.dart';

enum AppointmentStatus {
  pending,
  approved,
  completed,
  cancelled,
  cancellationRequested,
  noShow,
  rejected,
}

enum DepositStatus { none, pending, paid, refunded, failed }

enum UserRole { customer, businessOwner, staff, admin }

enum PaymentType { deposit, businessSubscription, promotionBoost }

enum PaymentStatus { pending, paid, failed, cancelled, refunded, manualReview }

class BeautyCategory {
  const BeautyCategory({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
}

class SalonService {
  const SalonService({
    required this.id,
    required this.businessId,
    required this.name,
    required this.categoryId,
    required this.durationMin,
    required this.price,
    required this.depositRequired,
    required this.depositAmount,
    this.description = '',
    this.imageUrl = '',
    this.isPopular = false,
    this.isActive = true,
  });

  final String id;
  final String businessId;
  final String name;
  final String categoryId;
  final int durationMin;
  final double price;
  final bool depositRequired;
  final double depositAmount;
  final String description;
  final String imageUrl;
  final bool isPopular;
  final bool isActive;
}

class StaffMember {
  const StaffMember({
    required this.id,
    required this.businessId,
    required this.name,
    required this.role,
    required this.phone,
    required this.color,
    required this.serviceIds,
    required this.workingHours,
    this.avatarUrl = '',
    this.rating = 4.8,
    this.availableDays = const ['Pzt', 'Sal', 'Car', 'Per', 'Cum', 'Cmt'],
    this.isActive = true,
    this.bio = '',
    this.completedAppointments = 0,
    this.portfolioImageUrls = const [],
    this.reviewCount = 0,
    this.averageRating = 0,
    this.specialties = const [],
    this.certificates = const [],
  });

  final String id;
  final String businessId;
  final String name;
  final String role;
  final String phone;
  final Color color;
  final List<String> serviceIds;
  final String workingHours;
  final String avatarUrl;
  final double rating;
  final List<String> availableDays;
  final bool isActive;
  final String bio;
  final int completedAppointments;
  final List<String> portfolioImageUrls;
  final int reviewCount;
  final double averageRating;
  final List<String> specialties;
  final List<String> certificates;

  String get title => role;
}

class Salon {
  const Salon({
    required this.id,
    required this.name,
    required this.type,
    required this.city,
    required this.district,
    required this.neighborhood,
    required this.rating,
    required this.reviewCount,
    required this.minPrice,
    required this.maxPrice,
    required this.coverColor,
    required this.categoryIds,
    required this.about,
    required this.cancellationPolicy,
    required this.availableSlots,
    required this.distanceKm,
    required this.openUntil,
    this.atelierNote = '',
    this.description,
    this.coverImage = '',
    this.galleryImages = const [],
    this.address,
    this.isPremium = false,
    this.acceptsDeposit = false,
    this.depositAmount = 0,
    this.workingHours = const {},
    this.campaign,
    this.isFavorite = false,
    this.availableToday = false,
    this.isPublished = true,
    this.isVerified = false,
    this.trustBadges = const [],
    this.brandsUsed = const [],
    this.certificates = const [],
    this.cancellationPolicyDetails,
    this.mapPoint,
    this.brandItems = const [],
    this.certificateItems = const [],
    this.campaignPackages = const [],
    this.favoriteCollectionIds = const [],
    this.smartSuggestions = const [],
    this.hasWaitlistEnabled = false,
    this.waitlistCount = 0,
    this.nextAvailableAt,
  });

  final String id;
  final String name;
  final String type;
  final String city;
  final String district;
  final String neighborhood;
  final double rating;
  final int reviewCount;
  final double minPrice;
  final double maxPrice;
  final Color coverColor;
  final List<String> categoryIds;
  final String about;

  /// İşletmenin kısa "Atölye notu" (vitrin). Boşsa müşteri detayında gizlenir.
  final String atelierNote;
  final String cancellationPolicy;
  final List<String> availableSlots;
  final double distanceKm;
  final String openUntil;
  final String? description;
  final String coverImage;
  final List<String> galleryImages;
  final String? address;
  final bool isPremium;
  final bool acceptsDeposit;
  final double depositAmount;
  final Map<String, String> workingHours;
  final String? campaign;
  final bool isFavorite;
  final bool availableToday;
  final bool isPublished;
  final bool isVerified;
  final List<String> trustBadges;
  final List<String> brandsUsed;
  final List<String> certificates;
  final CancellationPolicy? cancellationPolicyDetails;
  final SalonMapPoint? mapPoint;
  final List<BrandItem> brandItems;
  final List<CertificateItem> certificateItems;
  final List<CampaignPackage> campaignPackages;
  final List<String> favoriteCollectionIds;
  final List<SmartSlotSuggestion> smartSuggestions;
  final bool hasWaitlistEnabled;
  final int waitlistCount;
  final DateTime? nextAvailableAt;

  bool get isOpenToday => availableToday;
  double get distance => distanceKm;
  double get startingPrice => minPrice;
}

class Appointment {
  const Appointment({
    required this.id,
    required this.businessId,
    required this.salonName,
    required this.customerName,
    required this.serviceName,
    required this.staffName,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.depositStatus,
    required this.depositAmount,
    required this.total,
    required this.bookingSource,
    this.userId = 'u1',
    this.serviceId = '',
    this.staffId = '',
    DateTime? createdAt,
    this.notes,
    this.canCancel = true,
    this.canReschedule = true,
    this.cancellationRequested = false,
    this.rescheduleRequested = false,
    this.hasReview = false,
    this.cancellationPolicyText = '',
    this.cancelReason,
    this.userNote,
    this.cancelledAt,
    this.salonAddress,
    this.salonDistrict,
    this.salonCity,
    this.salonCoverImageUrl,
    this.depositInfo,
    this.cancellation,
  }) : createdAt = createdAt ?? startAt;

  final String id;
  final String businessId;
  final String salonName;
  final String customerName;
  final String serviceName;
  final String staffName;
  final DateTime startAt;
  final DateTime endAt;
  final AppointmentStatus status;
  final DepositStatus depositStatus;
  final double depositAmount;
  final double total;
  final String bookingSource;
  final String userId;
  final String serviceId;
  final String staffId;
  final DateTime createdAt;
  final String? notes;
  final bool canCancel;
  final bool canReschedule;
  final bool cancellationRequested;
  final bool rescheduleRequested;
  final bool hasReview;
  final String cancellationPolicyText;
  final String? cancelReason;
  final String? userNote;
  final DateTime? cancelledAt;
  final String? salonAddress;
  final String? salonDistrict;
  final String? salonCity;
  final String? salonCoverImageUrl;
  final DepositInfo? depositInfo;
  final CancellationFinancial? cancellation;

  double get remainingAmount {
    final remaining = total - depositAmount;
    return remaining < 0 ? 0 : remaining;
  }
}

class CancellationFinancial {
  const CancellationFinancial({
    required this.paidDeposit,
    required this.refundAmount,
    required this.retainedAmount,
    required this.ruleResult,
    this.manualRefund = false,
  });

  final double paidDeposit;
  final double refundAmount;
  final double retainedAmount;
  final String ruleResult;
  final bool manualRefund;

  static CancellationFinancial? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final data = Map<String, Object?>.from(raw);
    final rule = data['rule_result']?.toString() ?? '';
    if (rule.isEmpty) return null;
    return CancellationFinancial(
      paidDeposit: _doubleValue(data['paid_deposit']),
      refundAmount: _doubleValue(data['refund_amount']),
      retainedAmount: _doubleValue(data['retained_amount']),
      ruleResult: rule,
      manualRefund: data['manual_refund'] == true,
    );
  }

  static double _doubleValue(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class DepositSettings {
  const DepositSettings({
    required this.acceptsDeposit,
    required this.depositAmount,
    required this.description,
  });

  final bool acceptsDeposit;
  final double depositAmount;
  final String description;
}

/// MVP kapora bilgisi: para Webey'de toplanmaz; müşteri kaporayı doğrudan
/// salonun IBAN'ına gönderir. Backend `deposit` bloğundan parse edilir.
class DepositInfo {
  const DepositInfo({
    required this.required,
    this.amount,
    this.status = 'pending',
    this.referenceCode,
    this.paymentEnabled = false,
    this.hasIban = false,
    this.iban = '',
    this.ibanFormatted = '',
    this.accountHolder,
    this.bankName,
    this.instructions,
  });

  final bool required;
  final double? amount;
  final String status; // pending | paid | not_received | waived | refunded
  final String? referenceCode;
  final bool paymentEnabled;
  final bool hasIban;
  final String iban;
  final String ibanFormatted;
  final String? accountHolder;
  final String? bankName;
  final String? instructions;

  /// Salon kapora istiyor ama IBAN bilgisini henüz eklememiş.
  bool get awaitingIban => required && !hasIban;
  bool get isPaid => status == 'paid';
  bool get isNotReceived => status == 'not_received' || status == 'rejected';

  /// Müşteri "IBAN'a yolladım" dedi, işletme onayı bekleniyor.
  bool get isMarkedSent => status == 'customer_marked_sent';

  /// Müşteri "IBAN'a yolladım" diyebilir mi? Kapora gerekli, IBAN tanımlı ve
  /// henüz gönderildi/onaylandı işaretlenmemiş olmalı.
  bool get canMarkSent =>
      required &&
      hasIban &&
      (status == 'pending' || status == 'manual_pending' || status.isEmpty);

  DepositInfo copyWith({String? status, double? amount}) {
    return DepositInfo(
      required: required,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      referenceCode: referenceCode,
      paymentEnabled: paymentEnabled,
      hasIban: hasIban,
      iban: iban,
      ibanFormatted: ibanFormatted,
      accountHolder: accountHolder,
      bankName: bankName,
      instructions: instructions,
    );
  }

  static String? _nullableStr(Object? v) {
    final s = (v ?? '').toString();
    return s.isEmpty ? null : s;
  }

  static bool _bool(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().toLowerCase().trim();
    return s == '1' || s == 'true' || s == 'yes' || s == 'on';
  }

  static DepositInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    final required = _bool(json['required']);
    final payment = json['payment'];
    final pay = payment is Map
        ? Map<String, Object?>.from(payment)
        : const <String, Object?>{};
    double? amount;
    final a = json['amount'];
    if (a is num) {
      amount = a.toDouble();
    } else if (a != null) {
      amount = double.tryParse(a.toString());
    }
    return DepositInfo(
      required: required,
      amount: amount,
      status: json['status']?.toString() ?? 'pending',
      referenceCode: _nullableStr(json['reference_code']),
      paymentEnabled: _bool(pay['deposit_enabled']),
      hasIban: _bool(json['has_iban']) || _bool(pay['has_iban']),
      iban: json['iban']?.toString() ?? pay['iban']?.toString() ?? '',
      ibanFormatted:
          json['iban_formatted']?.toString() ??
          pay['iban_formatted']?.toString() ??
          '',
      accountHolder:
          _nullableStr(json['account_holder']) ??
          _nullableStr(pay['account_holder']),
      bankName:
          _nullableStr(json['bank_name']) ?? _nullableStr(pay['bank_name']),
      instructions:
          _nullableStr(json['instructions']) ??
          _nullableStr(pay['instructions']),
    );
  }
}

class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.priceMonthly,
    required this.description,
    required this.features,
    this.isRecommended = false,
    this.includesDepositFeature = false,
  });

  final String id;
  final String name;
  final double priceMonthly;
  final String description;
  final List<String> features;
  final bool isRecommended;
  final bool includesDepositFeature;
}

class BusinessPlan {
  const BusinessPlan({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.price,
    required this.features,
    this.highlight = false,
    this.includesDepositFeature = false,
  });

  final String id;
  final String label;
  final String subtitle;
  final double price;
  final List<String> features;
  final bool highlight;
  final bool includesDepositFeature;
}

// ── Faz 1: Yeni modeller ──────────────────────────────────────────────────────

class Review {
  const Review({
    required this.id,
    required this.salonId,
    required this.userId,
    required this.userName,
    required this.ratingOverall,
    required this.comment,
    required this.createdAt,
    this.appointmentId = '',
    this.userAvatarUrl = '',
    this.ratingHygiene = 0,
    this.ratingService = 0,
    this.ratingStaff = 0,
    this.ratingAmbience = 0,
    this.imageUrls = const [],
    this.isVerifiedAppointment = false,
    this.staffId = '',
    this.staffName = '',
    this.serviceId = '',
    this.serviceName = '',
    this.businessReply,
    this.businessReplyDate,
  });

  final String id;
  final String salonId;
  final String userId;
  final String userName;
  final double ratingOverall;
  final String comment;
  final DateTime createdAt;
  final String appointmentId;
  final String userAvatarUrl;
  final double ratingHygiene;
  final double ratingService;
  final double ratingStaff;
  final double ratingAmbience;
  final List<String> imageUrls;
  final bool isVerifiedAppointment;
  final String staffId;
  final String staffName;
  final String serviceId;
  final String serviceName;
  final String? businessReply;
  final DateTime? businessReplyDate;
}

class ReviewSummary {
  const ReviewSummary({
    required this.salonId,
    required this.averageRating,
    required this.reviewCount,
    required this.verifiedReviewCount,
    this.hygieneAverage = 0,
    this.serviceAverage = 0,
    this.staffAverage = 0,
    this.ambienceAverage = 0,
  });

  final String salonId;
  final double averageRating;
  final int reviewCount;
  final int verifiedReviewCount;
  final double hygieneAverage;
  final double serviceAverage;
  final double staffAverage;
  final double ambienceAverage;
}

class PortfolioItem {
  const PortfolioItem({
    required this.id,
    required this.salonId,
    required this.title,
    required this.category,
    required this.imageUrl,
    this.description = '',
    this.serviceId = '',
    this.staffId = '',
    this.staffName = '',
    this.isBeforeAfter = false,
    this.beforeImageUrl = '',
    this.afterImageUrl = '',
  });

  final String id;
  final String salonId;
  final String title;
  final String category;
  final String imageUrl;
  final String description;
  final String serviceId;
  final String staffId;
  final String staffName;
  final bool isBeforeAfter;
  final String beforeImageUrl;
  final String afterImageUrl;
}

class CancellationPolicy {
  const CancellationPolicy({
    required this.id,
    required this.salonId,
    required this.title,
    required this.description,
    required this.freeCancellationHours,
    required this.depositRefundableUntilHours,
    required this.noShowDepositRefundable,
    required this.policyItems,
  });

  final String id;
  final String salonId;
  final String title;
  final String description;
  final int freeCancellationHours;
  final int depositRefundableUntilHours;
  final bool noShowDepositRefundable;
  final List<String> policyItems;
}

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    this.isRead = false,
    this.relatedAppointmentId = '',
    this.relatedSalonId = '',
  });

  final String id;
  final String title;
  final String message;
  final String type;
  final DateTime createdAt;
  final bool isRead;
  final String relatedAppointmentId;
  final String relatedSalonId;
}

class WaitlistEntry {
  const WaitlistEntry({
    required this.id,
    required this.userId,
    required this.userName,
    required this.salonId,
    required this.serviceId,
    required this.serviceName,
    required this.staffId,
    required this.staffName,
    required this.preferredDate,
    required this.preferredTimeRange,
    required this.status,
    required this.createdAt,
    this.note = '',
  });

  final String id;
  final String userId;
  final String userName;
  final String salonId;
  final String serviceId;
  final String serviceName;
  final String staffId;
  final String staffName;
  final DateTime preferredDate;
  final String preferredTimeRange;
  final String status;
  final DateTime createdAt;
  final String note;
}

class SmartSlotSuggestion {
  const SmartSlotSuggestion({
    required this.id,
    required this.salonId,
    required this.serviceId,
    required this.staffId,
    required this.staffName,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.label,
    required this.description,
    required this.score,
    required this.type,
  });

  final String id;
  final String salonId;
  final String serviceId;
  final String staffId;
  final String staffName;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String label;
  final String description;
  final double score;
  final String type;
}

class SalonMapPoint {
  const SalonMapPoint({
    required this.salonId,
    required this.salonName,
    required this.district,
    required this.distance,
    required this.latitudeMock,
    required this.longitudeMock,
    required this.rating,
    required this.startingPrice,
    required this.acceptsDeposit,
    required this.isPremium,
    required this.isOpenToday,
  });

  final String salonId;
  final String salonName;
  final String district;
  final double distance;
  final double latitudeMock;
  final double longitudeMock;
  final double rating;
  final double startingPrice;
  final bool acceptsDeposit;
  final bool isPremium;
  final bool isOpenToday;
}

class BrandItem {
  const BrandItem({
    required this.id,
    required this.name,
    required this.category,
    required this.logoUrl,
    required this.description,
    this.isPremium = false,
  });

  final String id;
  final String name;
  final String category;
  final String logoUrl;
  final String description;
  final bool isPremium;
}

class CertificateItem {
  const CertificateItem({
    required this.id,
    required this.title,
    required this.issuer,
    required this.issuedYear,
    required this.description,
    this.imageUrl = '',
  });

  final String id;
  final String title;
  final String issuer;
  final int issuedYear;
  final String description;
  final String imageUrl;
}

class CampaignPackage {
  const CampaignPackage({
    required this.id,
    required this.salonId,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.originalPrice,
    required this.discountedPrice,
    required this.discountLabel,
    required this.serviceIds,
    required this.serviceNames,
    required this.validUntil,
    this.isFeatured = false,
    this.isNewCustomerOnly = false,
    this.requiresDeposit = false,
    this.depositAmount = 0,
  });

  final String id;
  final String salonId;
  final String title;
  final String description;
  final String imageUrl;
  final double originalPrice;
  final double discountedPrice;
  final String discountLabel;
  final List<String> serviceIds;
  final List<String> serviceNames;
  final DateTime validUntil;
  final bool isFeatured;
  final bool isNewCustomerOnly;
  final bool requiresDeposit;
  final double depositAmount;
}

class FavoriteCollection {
  const FavoriteCollection({
    required this.id,
    required this.title,
    required this.description,
    required this.salonIds,
    required this.coverImageUrl,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String description;
  final List<String> salonIds;
  final String coverImageUrl;
  final DateTime createdAt;
}

class UserFavorite {
  const UserFavorite({
    required this.salonId,
    required this.addedAt,
    required this.collectionIds,
  });

  final String salonId;
  final DateTime addedAt;
  final List<String> collectionIds;
}

class BusinessCustomer {
  const BusinessCustomer({
    required this.id,
    this.detailKey,
    required this.name,
    required this.phoneMasked,
    required this.emailMasked,
    this.avatarUrl = '',
    this.tags = const [],
    required this.firstVisitDate,
    required this.lastVisitDate,
    required this.totalAppointments,
    required this.completedAppointments,
    required this.cancelledAppointments,
    required this.noShowCount,
    required this.totalSpent,
    required this.depositPaidTotal,
    this.favoriteServices = const [],
    this.preferredStaffId = '',
    this.preferredStaffName = '',
    this.notes = '',
    this.isVip = false,
    this.upcomingAppointmentId = '',
  });

  final String id;

  /// customer-detail.php'nin beklediği self-describing anahtar
  /// (`u<id>` | `p<phone>` | `n<name>`). Yoksa id'ye düşülür.
  final String? detailKey;
  final String name;
  final String phoneMasked;
  final String emailMasked;
  final String avatarUrl;
  final List<String> tags;
  final DateTime firstVisitDate;
  final DateTime lastVisitDate;
  final int totalAppointments;
  final int completedAppointments;
  final int cancelledAppointments;
  final int noShowCount;
  final double totalSpent;
  final double depositPaidTotal;
  final List<String> favoriteServices;
  final String preferredStaffId;
  final String preferredStaffName;
  final String notes;
  final bool isVip;
  final String upcomingAppointmentId;

  factory BusinessCustomer.fromJson(Map<String, Object?> json) {
    DateTime parseDate(Object? v) {
      final s = v?.toString().trim() ?? '';
      return DateTime.tryParse(s) ?? DateTime(2000);
    }

    int asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    double asDouble(Object? v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }

    String asStr(Object? v) => v?.toString() ?? '';

    List<String> asStrList(Object? v) {
      if (v is List) {
        return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
      final s = asStr(v);
      return s.isEmpty ? const [] : [s];
    }

    return BusinessCustomer(
      id: asStr(json['id']),
      detailKey: asStr(json['detail_key']).isEmpty
          ? null
          : asStr(json['detail_key']),
      name: asStr(json['name']).isEmpty ? 'Müşteri' : asStr(json['name']),
      phoneMasked: asStr(json['phone'] ?? json['phone_masked']),
      emailMasked: asStr(json['email'] ?? json['email_masked']),
      avatarUrl: asStr(json['avatar_url']),
      tags: asStrList(json['tags']),
      firstVisitDate: parseDate(json['first_visit_at'] ?? json['first_visit']),
      lastVisitDate: parseDate(json['last_visit_at'] ?? json['last_visit']),
      totalAppointments: asInt(json['total_appointments']),
      completedAppointments: asInt(json['completed_appointments']),
      cancelledAppointments: asInt(json['cancelled_appointments']),
      noShowCount: asInt(json['no_show_count']),
      totalSpent: asDouble(json['total_spent']),
      depositPaidTotal: asDouble(json['deposit_paid_total']),
      favoriteServices: asStrList(
        json['favorite_service'] ?? json['favorite_services'],
      ),
      preferredStaffId: asStr(json['preferred_staff_id']),
      preferredStaffName: asStr(json['preferred_staff_name']),
      notes: asStr(json['notes']),
      isVip: json['is_vip'] == true || json['is_vip'] == 1,
      upcomingAppointmentId: asStr(json['upcoming_appointment_id']),
    );
  }
}

class CustomerNote {
  const CustomerNote({
    required this.id,
    required this.customerId,
    required this.author,
    required this.note,
    required this.createdAt,
    this.isPrivate = false,
  });

  final String id;
  final String customerId;
  final String author;
  final String note;
  final DateTime createdAt;
  final bool isPrivate;
}

class BusinessAnalyticsSummary {
  const BusinessAnalyticsSummary({
    required this.monthLabel,
    required this.totalAppointments,
    required this.completedAppointments,
    required this.cancelledAppointments,
    required this.noShowAppointments,
    required this.depositAppointments,
    required this.totalRevenueEstimate,
    required this.totalDepositCollected,
    required this.protectedRevenue,
    required this.profileViews,
    required this.favoritesCount,
    required this.repeatCustomerRate,
    required this.averageRating,
    required this.occupancyRate,
  });

  final String monthLabel;
  final int totalAppointments;
  final int completedAppointments;
  final int cancelledAppointments;
  final int noShowAppointments;
  final int depositAppointments;
  final double totalRevenueEstimate;
  final double totalDepositCollected;
  final double protectedRevenue;
  final int profileViews;
  final int favoritesCount;
  final double repeatCustomerRate;
  final double averageRating;
  final double occupancyRate;
}

class AnalyticsTrendPoint {
  const AnalyticsTrendPoint({
    required this.label,
    required this.value,
    this.secondaryValue = 0,
  });

  final String label;
  final double value;
  final double secondaryValue;
}

class ServicePerformance {
  const ServicePerformance({
    required this.serviceId,
    required this.serviceName,
    required this.bookingCount,
    required this.revenueEstimate,
    required this.averageRating,
    required this.cancellationRate,
    required this.averageDurationMinutes,
  });

  final String serviceId;
  final String serviceName;
  final int bookingCount;
  final double revenueEstimate;
  final double averageRating;
  final double cancellationRate;
  final int averageDurationMinutes;
}

class StaffPerformance {
  const StaffPerformance({
    required this.staffId,
    required this.staffName,
    required this.title,
    this.avatarUrl = '',
    required this.completedAppointments,
    required this.revenueEstimate,
    required this.averageRating,
    required this.cancellationRate,
    required this.repeatCustomerCount,
    required this.occupancyRate,
    required this.depositAppointments,
  });

  final String staffId;
  final String staffName;
  final String title;
  final String avatarUrl;
  final int completedAppointments;
  final double revenueEstimate;
  final double averageRating;
  final double cancellationRate;
  final int repeatCustomerCount;
  final double occupancyRate;
  final int depositAppointments;
}

class NoShowProtectionSummary {
  const NoShowProtectionSummary({
    required this.depositSecuredAppointments,
    required this.estimatedProtectedRevenue,
    required this.noShowRateBeforeDeposit,
    required this.noShowRateAfterDeposit,
    required this.cancelledWithDeposit,
    required this.depositEnabled,
    required this.recommendationText,
  });

  final int depositSecuredAppointments;
  final double estimatedProtectedRevenue;
  final double noShowRateBeforeDeposit;
  final double noShowRateAfterDeposit;
  final int cancelledWithDeposit;
  final bool depositEnabled;
  final String recommendationText;
}

class PromotionBoostPackage {
  const PromotionBoostPackage({
    required this.id,
    required this.title,
    required this.description,
    required this.priceMonthly,
    required this.features,
    required this.badgeText,
    this.isRecommended = false,
    this.isActive = false,
  });

  final String id;
  final String title;
  final String description;
  final double priceMonthly;
  final List<String> features;
  final String badgeText;
  final bool isRecommended;
  final bool isActive;
}

class BusinessActionItem {
  const BusinessActionItem({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.priority,
    required this.ctaText,
    required this.relatedScreen,
    this.isCompleted = false,
  });

  final String id;
  final String title;
  final String description;
  final String type;
  final String priority;
  final String ctaText;
  final String relatedScreen;
  final bool isCompleted;
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.fullName,
    this.phone = '',
    this.email = '',
    this.avatarUrl = '',
    required this.role,
    this.isPhoneVerified = false,
    this.isEmailVerified = false,
    this.businessOnboardingCompleted,
    this.adminOnboardingCompleted,
    this.onboardingStep,
    required this.createdAt,
  });

  final String id;
  final String fullName;
  final String phone;
  final String email;
  final String avatarUrl;
  final UserRole role;
  final bool isPhoneVerified;
  final bool isEmailVerified;
  final bool? businessOnboardingCompleted;
  final bool? adminOnboardingCompleted;
  final int? onboardingStep;
  final DateTime createdAt;
}

class AuthSession {
  const AuthSession({
    required this.accessTokenMock,
    required this.refreshTokenMock,
    required this.expiresAt,
    required this.user,
  });

  final String accessTokenMock;
  final String refreshTokenMock;
  final DateTime expiresAt;
  final AuthUser user;
}

class PaymentIntent {
  const PaymentIntent({
    required this.id,
    required this.type,
    required this.amount,
    required this.currency,
    required this.status,
    required this.description,
    this.relatedAppointmentId = '',
    this.relatedBusinessId = '',
    required this.provider,
    this.checkoutUrlMock = '',
    required this.createdAt,
  });

  final String id;
  final PaymentType type;
  final double amount;
  final String currency;
  final PaymentStatus status;
  final String description;
  final String relatedAppointmentId;
  final String relatedBusinessId;
  final String provider;
  final String checkoutUrlMock;
  final DateTime createdAt;

  PaymentIntent copyWith({PaymentStatus? status}) {
    return PaymentIntent(
      id: id,
      type: type,
      amount: amount,
      currency: currency,
      status: status ?? this.status,
      description: description,
      relatedAppointmentId: relatedAppointmentId,
      relatedBusinessId: relatedBusinessId,
      provider: provider,
      checkoutUrlMock: checkoutUrlMock,
      createdAt: createdAt,
    );
  }
}

class AdminSalonReviewItem {
  const AdminSalonReviewItem({
    required this.salonId,
    required this.salonName,
    required this.ownerName,
    required this.status,
    required this.submittedAt,
    this.missingFields = const [],
    this.riskFlags = const [],
  });

  final String salonId;
  final String salonName;
  final String ownerName;
  final String status;
  final DateTime submittedAt;
  final List<String> missingFields;
  final List<String> riskFlags;
}

class AdminPaymentRecord {
  const AdminPaymentRecord({
    required this.paymentId,
    required this.userName,
    required this.businessName,
    required this.type,
    required this.amount,
    required this.status,
    required this.provider,
    required this.createdAt,
  });

  final String paymentId;
  final String userName;
  final String businessName;
  final PaymentType type;
  final double amount;
  final PaymentStatus status;
  final String provider;
  final DateTime createdAt;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.userName,
    required this.userRole,
    required this.subject,
    required this.message,
    required this.status,
    required this.priority,
    required this.createdAt,
  });

  final String id;
  final String userName;
  final UserRole userRole;
  final String subject;
  final String message;
  final String status;
  final String priority;
  final DateTime createdAt;
}
