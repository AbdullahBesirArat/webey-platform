import 'package:flutter/foundation.dart';

import '../../../../../core/config/api_config.dart';
import '../../../../../shared/mock/mock_data.dart';
import '../../../../../shared/models/beauty_models.dart';
import '../../../../../shared/services/api_client.dart';
import '../models/business_appointment.dart';
import '../models/business_campaign.dart';
import '../models/business_dashboard.dart';
import '../models/business_service_category.dart';
import '../models/business_service_item.dart';
import '../models/business_staff_item.dart';

class BusinessRepository {
  const BusinessRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? const ApiClient();

  static const instance = BusinessRepository();

  final ApiClient _apiClient;

  Future<BusinessDashboard> getDashboard() async {
    if (ApiConfig.useMockBusiness) {
      return _mockDashboard();
    }

    final data = await _apiClient.getData('/business/dashboard.php');
    return BusinessDashboard.fromJson(data);
  }

  Future<List<BusinessAppointment>> getAppointments({
    String status = 'all',
    String? date,
    String? from,
    String? to,
    int page = 1,
    int limit = 20,
  }) async {
    if (ApiConfig.useMockBusiness) {
      return _mockAppointments(status: status, date: date);
    }

    final query = <String, String>{
      'status': status,
      'page': '$page',
      'limit': '$limit',
      if (date != null && date.isNotEmpty) 'date': date,
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
    };
    final uri = Uri(path: '/business/appointments.php', queryParameters: query);
    final data = await _apiClient.getData(uri.toString());
    final items = data['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) =>
              BusinessAppointment.fromJson(Map<String, Object?>.from(item)),
        )
        .toList();
  }

  Future<BusinessAppointment> createAppointment({
    required String customerName,
    String? customerPhone,
    required int serviceId,
    int? staffId,
    required String appointmentDate,
    required String appointmentTime,
    String? notes,
  }) async {
    final body = <String, Object?>{
      'customer_name': customerName,
      'service_id': serviceId,
      'appointment_date': appointmentDate,
      'appointment_time': appointmentTime,
      'starts_at': '$appointmentDate $appointmentTime:00',
    };
    if (customerPhone != null && customerPhone.trim().isNotEmpty) {
      body['customer_phone'] = customerPhone.trim();
    }
    if (staffId != null) {
      body['staff_id'] = staffId;
      body['specialist_id'] = staffId;
    }
    if (notes != null && notes.trim().isNotEmpty) {
      body['notes'] = notes.trim();
    }
    final data = await _apiClient.postData(
      '/business/appointment-create.php',
      body: body,
    );
    final appointment = data['appointment'];
    if (appointment is Map) {
      return BusinessAppointment.fromJson(
        Map<String, Object?>.from(appointment),
      );
    }
    throw const FormatException('Sunucu yanitinda appointment alani yok.');
  }

  Future<bool> updateAppointmentStatus({
    required int appointmentId,
    required String status,
    String? note,
  }) async {
    if (ApiConfig.useMockBusiness) return true;

    await _apiClient.postData(
      '/business/appointment-update.php',
      body: {
        'appointment_id': appointmentId,
        'status': status,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return true;
  }

  Future<List<BusinessServiceItem>> getServices({
    bool includeInactive = false,
  }) async {
    if (ApiConfig.useMockBusiness) {
      return _mockServices(includeInactive: includeInactive);
    }

    final uri = Uri(
      path: '/business/services.php',
      queryParameters: {'include_inactive': includeInactive ? '1' : '0'},
    );
    final data = await _apiClient.getData(uri.toString());
    final items = data['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) =>
              BusinessServiceItem.fromJson(Map<String, Object?>.from(item)),
        )
        .toList();
  }

  Future<BusinessServiceItem> saveService(BusinessServiceItem item) async {
    if (ApiConfig.useMockBusiness) {
      return _saveMockService(item);
    }

    final data = await _apiClient.postData(
      '/business/service-save.php',
      body: item.toJson(),
    );
    final service = data['service'];
    if (service is Map) {
      return BusinessServiceItem.fromJson(Map<String, Object?>.from(service));
    }
    return item;
  }

  Future<bool> deleteService(int id) async {
    if (ApiConfig.useMockBusiness) {
      _mockServicesStore.removeWhere((item) => item.id == id);
      return true;
    }

    await _apiClient.postData('/business/service-delete.php', body: {'id': id});
    return true;
  }

  /// Sistem + işletmeye özel hizmet kategorileri (service_count dahil).
  Future<List<BusinessServiceCategory>> getServiceCategories() async {
    if (ApiConfig.useMockBusiness) {
      return _mockServiceCategories;
    }

    final data = await _apiClient.getData('/business/service-categories.php');
    final items = data['categories'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) =>
              BusinessServiceCategory.fromJson(Map<String, Object?>.from(item)),
        )
        .where((category) => category.id > 0 && category.name.isNotEmpty)
        .toList();
  }

  /// İşletmeye özel kategori oluşturur/günceller; kayıtlı halini döndürür.
  Future<BusinessServiceCategory> saveServiceCategory({
    int? id,
    required String name,
    String? iconKey,
    int sortOrder = 0,
  }) async {
    if (ApiConfig.useMockBusiness) {
      return BusinessServiceCategory(
        id: id ?? DateTime.now().millisecondsSinceEpoch % 100000,
        name: name,
        slug: name.toLowerCase(),
      );
    }

    final data = await _apiClient.postData(
      '/business/service-category-save.php',
      body: {
        if (id != null && id > 0) 'id': id,
        'name': name,
        'icon_key': iconKey,
        'sort_order': sortOrder,
      },
    );
    final category = data['category'];
    if (category is Map) {
      return BusinessServiceCategory.fromJson(
        Map<String, Object?>.from(category),
      );
    }
    throw const ApiException('Kategori kaydedilemedi.');
  }

  Future<bool> deleteServiceCategory(int id) async {
    if (ApiConfig.useMockBusiness) return true;
    await _apiClient.postData(
      '/business/service-category-delete.php',
      body: {'id': id},
    );
    return true;
  }

  static const _mockServiceCategories = [
    BusinessServiceCategory(
      id: 1,
      name: 'Tırnak Stüdyosu',
      slug: 'nail_studio',
      isSystem: true,
    ),
    BusinessServiceCategory(
      id: 3,
      name: 'Cilt Bakımı',
      slug: 'skin_care',
      isSystem: true,
    ),
    BusinessServiceCategory(
      id: 7,
      name: 'Spa ve Masaj',
      slug: 'spa_massage',
      isSystem: true,
    ),
  ];

  Future<List<BusinessStaffItem>> getStaff({
    bool includeInactive = false,
  }) async {
    if (ApiConfig.useMockBusiness) {
      final items = includeInactive
          ? _mockStaffStore
          : _mockStaffStore.where((item) => item.isActive);
      return List<BusinessStaffItem>.unmodifiable(items);
    }

    final data = await _apiClient.getData('/business/staff.php');
    final items = data['items'] ?? data['staff'];
    if (items is! List) return const [];
    final parsed = items.whereType<Map>().map(
      (item) => BusinessStaffItem.fromJson(Map<String, Object?>.from(item)),
    );
    final filtered = includeInactive
        ? parsed
        : parsed.where((item) => item.isActive);
    return filtered.toList();
  }

  Future<BusinessStaffItem> saveStaff(BusinessStaffItem item) async {
    if (ApiConfig.useMockBusiness) {
      return _saveMockStaff(item);
    }

    final data = await _apiClient.postData(
      '/business/staff-save.php',
      body: item.toJson(),
    );
    final staff = data['staff'];
    if (staff is Map) {
      return BusinessStaffItem.fromJson(Map<String, Object?>.from(staff));
    }
    return item;
  }

  Future<bool> deleteStaff(int id) async {
    if (ApiConfig.useMockBusiness) {
      _mockStaffStore.removeWhere((item) => item.id == id);
      return true;
    }

    await _apiClient.postData('/business/staff-delete.php', body: {'id': id});
    return true;
  }

  Future<Map<String, dynamic>> markOnboardingComplete({int step = 7}) async {
    if (step < 1 || step > 7) {
      throw ArgumentError.value(step, 'step', 'Must be between 1 and 7.');
    }

    if (ApiConfig.useMockBusiness) {
      return {'id': 1, 'onboarding_completed': true, 'onboarding_step': step};
    }

    final data = await _apiClient.postData(
      '/business/onboarding-complete.php',
      body: {'step': step},
    );
    final business = data['business'];
    if (business is Map) {
      return Map<String, dynamic>.from(business);
    }
    return {'onboarding_completed': true, 'onboarding_step': step};
  }

  Future<Map<String, dynamic>> getBusinessProfile() async {
    if (ApiConfig.useMockBusiness) {
      return {
        'id': 1,
        'name': 'Demo Salon',
        'description': null,
        'phone': null,
        'city': 'İstanbul',
        'district': 'Kadıköy',
        'address': null,
        'latitude': null,
        'longitude': null,
        'map_url': null,
        'is_active': true,
        'owner_name': 'Demo',
      };
    }
    final data = await _apiClient.getData('/business/profile.php');
    final business = data['business'];
    if (business is Map) {
      final profile = _normalizeBusinessProfile(
        Map<String, dynamic>.from(business),
      );
      // Onboarding'de seçilen ana hizmet kategorileri (top-level alan).
      if (data['category_slugs'] is List) {
        profile['category_slugs'] = (data['category_slugs'] as List)
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return profile;
    }
    return const {};
  }

  Future<Map<String, dynamic>> saveBusinessProfile(
    Map<String, dynamic> body,
  ) async {
    final payload = _businessProfilePayload(body);
    if (ApiConfig.useMockBusiness) return _normalizeBusinessProfile(payload);
    final data = await _apiClient.postData(
      '/business/profile-save.php',
      body: payload,
    );
    final business = data['business'];
    if (business is Map) {
      return _normalizeBusinessProfile(Map<String, dynamic>.from(business));
    }
    return _normalizeBusinessProfile(payload);
  }

  static Map<String, dynamic> _normalizeBusinessProfile(
    Map<String, dynamic> profile,
  ) {
    final normalized = Map<String, dynamic>.from(profile);
    normalized['about'] ??= normalized['description'];
    normalized['description'] ??= normalized['about'];
    normalized['address_line'] ??= normalized['address'];
    normalized['address'] ??= normalized['address_line'];
    return normalized;
  }

  static Map<String, dynamic> _businessProfilePayload(
    Map<String, dynamic> profile,
  ) {
    final normalized = _normalizeBusinessProfile(profile);
    return {
      'name': normalized['name'],
      'owner_name': normalized['owner_name'],
      'phone': normalized['phone'],
      'city': normalized['city'],
      'district': normalized['district'],
      'address_line': normalized['address_line'],
      'about': normalized['about'],
      'map_url': normalized['map_url'],
      'latitude': normalized['latitude'],
      'longitude': normalized['longitude'],
      'building_no': normalized['building_no'],
      'street_name': normalized['street_name'],
      'neighborhood': normalized['neighborhood'],
      if (normalized.containsKey('min_price'))
        'min_price': normalized['min_price'],
      if (normalized.containsKey('max_price'))
        'max_price': normalized['max_price'],
      if (normalized.containsKey('atelier_note'))
        'atelier_note': normalized['atelier_note'],
      // Yalnızca gönderildiyse iletilir; backend de yalnızca o zaman işler.
      if (normalized['category_slugs'] is List &&
          (normalized['category_slugs'] as List).isNotEmpty)
        'category_slugs': normalized['category_slugs'],
    };
  }

  Future<List<Map<String, dynamic>>> getBusinessHours() async {
    if (ApiConfig.useMockBusiness) return const [];
    final data = await _apiClient.getData('/business/hours.php');
    final items = data['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<Map<String, dynamic>>> saveBusinessHours(
    List<Map<String, dynamic>> items,
  ) async {
    if (ApiConfig.useMockBusiness) return items;
    final data = await _apiClient.postData(
      '/business/hours-save.php',
      body: {'items': items},
    );
    final saved = data['items'];
    if (saved is! List) return items;
    return saved
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> getNotificationPreferences() async {
    final data = await _apiClient.getData(
      '/business/notification-preferences.php',
    );
    final raw = data['prefs'];
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  Future<void> saveNotificationPreferences(Map<String, dynamic> prefs) async {
    await _apiClient.postData(
      '/business/notification-preferences.php',
      body: {'prefs': prefs},
    );
  }

  Future<Map<String, dynamic>> getRevenueReport({String? month}) async {
    final query = <String, String>{
      if (month != null && month.isNotEmpty) 'month': month,
    };
    final uri = Uri(
      path: '/business/revenue-report.php',
      queryParameters: query.isEmpty ? null : query,
    );
    final data = await _apiClient.getData(uri.toString());
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> getBusinessNotifications({
    int page = 1,
    int limit = 20,
    bool unreadOnly = false,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (unreadOnly) 'unread_only': '1',
    };
    final uri = Uri(
      path: '/business/notifications.php',
      queryParameters: query,
    );
    final data = await _apiClient.getData(uri.toString());
    debugPrint('[BusinessRepository] getBusinessNotifications raw: $data');
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> getBusinessReviews({int limit = 30}) async {
    final uri = Uri(
      path: '/business/reviews.php',
      queryParameters: {'limit': '$limit'},
    );
    final data = await _apiClient.getData(uri.toString());
    return Map<String, dynamic>.from(data);
  }

  Future<int> markBusinessNotificationRead({
    int? notificationId,
    bool markAll = false,
  }) async {
    final body = <String, Object?>{};
    if (notificationId != null) body['notification_id'] = notificationId;
    if (markAll) body['mark_all'] = true;
    final data = await _apiClient.postData(
      '/business/notifications/read.php',
      body: body,
    );
    final value = data['unread_count'];
    if (value is num) return value.toInt();
    return 0;
  }

  Future<void> registerBusinessDeviceToken({
    required String token,
    required String platform,
    String? deviceId,
  }) async {
    if (ApiConfig.useMockBusiness) return;
    final data = await _apiClient.postData(
      '/business/device-token.php',
      body: {
        'token': token,
        'platform': platform,
        if (deviceId != null && deviceId.trim().isNotEmpty)
          'device_id': deviceId.trim(),
      },
    );
    debugPrint('[BusinessRepository] device-token response: $data');
  }

  Future<Map<String, dynamic>> getDepositPolicy() async {
    if (ApiConfig.useMockBusiness) {
      return {'rate_pct': 25, 'per_service': false, 'cancel_policy': 'esnek'};
    }
    final data = await _apiClient.getData('/business/deposit.php');
    final policy = data['policy'];
    if (policy is Map) return Map<String, dynamic>.from(policy);
    return {'rate_pct': 25, 'per_service': false, 'cancel_policy': 'esnek'};
  }

  Future<void> saveDepositPolicy(Map<String, dynamic> body) async {
    if (ApiConfig.useMockBusiness) return;
    await _apiClient.postData('/business/deposit-save.php', body: body);
  }

  /// Salonun kapora IBAN ayarlarını döner.
  Future<Map<String, dynamic>> getActionCenter() async {
    if (ApiConfig.useMockBusiness) {
      return const {
        'summary': {'total': 0, 'urgent': 0, 'today': 0, 'done': 0},
        'items': [],
      };
    }
    final data = await _apiClient.getData('/business/action-center.php');
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> getPaymentSettings() async {
    final data = await _apiClient.getData('/business/payment-settings.php');
    final settings = data['payment_settings'];
    if (settings is Map) return Map<String, dynamic>.from(settings);
    return const {};
  }

  /// Salonun kapora geçmişi (gerçek randevu kayıtları). Mock fallback yok.
  Future<Map<String, dynamic>> getDepositHistory() async {
    final data = await _apiClient.getData('/business/deposit-history.php');
    return Map<String, dynamic>.from(data);
  }

  /// Analitik özeti — gerçek DB hesaplarından. Mock fallback yok.
  Future<Map<String, dynamic>> getAnalytics({String range = '30d'}) async {
    final uri = Uri(
      path: '/business/analytics.php',
      queryParameters: {'range': range},
    );
    final data = await _apiClient.getData(uri.toString());
    return Map<String, dynamic>.from(data);
  }

  /// Webey komisyon ve fatura geçmişi (MVP: çoğunlukla boş liste).
  Future<Map<String, dynamic>> getInvoices() async {
    final data = await _apiClient.getData('/business/invoices.php');
    return Map<String, dynamic>.from(data);
  }

  /// Dashboard arama — randevu/müşteri/hizmet/personel araması.
  Future<Map<String, dynamic>> dashboardSearch(String query) async {
    final q = query.trim();
    if (q.length < 2) {
      return const {
        'appointments': [],
        'customers': [],
        'services': [],
        'staff': [],
      };
    }
    final uri = Uri(path: '/business/search.php', queryParameters: {'q': q});
    final data = await _apiClient.getData(uri.toString());
    return Map<String, dynamic>.from(data);
  }

  /// Kapora IBAN ayarlarını kaydeder (upsert). Başarısızlıkta [ApiException] fırlatır.
  Future<Map<String, dynamic>> savePaymentSettings({
    required bool depositEnabled,
    required String iban,
    required String accountHolder,
    String? bankName,
    String? instructions,
  }) async {
    final data = await _apiClient.postData(
      '/business/payment-settings.php',
      body: {
        'deposit_enabled': depositEnabled,
        'iban': iban,
        'account_holder': accountHolder,
        'bank_name': ?bankName,
        'instructions': ?instructions,
      },
    );
    final settings = data['payment_settings'];
    if (settings is Map) return Map<String, dynamic>.from(settings);
    return const {};
  }

  /// Randevunun kapora durumunu manuel işaretler
  /// (status: pending | paid | not_received | waived | refunded).
  /// İşletmenin gerçek müşteri listesi (randevulardan türetilir).
  /// Döner: (summary: {total_customers,new_this_month,repeat_rate}, customers).
  Future<({Map<String, dynamic> summary, List<BusinessCustomer> customers})>
  getCustomers() async {
    final data = await _apiClient.getData('/business/customers.php');
    final summaryRaw = data['summary'];
    final summary = summaryRaw is Map
        ? Map<String, dynamic>.from(summaryRaw)
        : <String, dynamic>{};
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => BusinessCustomer.fromJson(Map<String, Object?>.from(m)))
        .toList();
    return (summary: summary, customers: items);
  }

  /// Tek müşterinin detay + istatistik + randevu geçmişi (gerçek veri).
  Future<Map<String, dynamic>> getCustomerDetail(String customerId) async {
    final uri = Uri(
      path: '/business/customer-detail.php',
      queryParameters: {'id': customerId},
    );
    final data = await _apiClient.getData(uri.toString());
    return Map<String, dynamic>.from(data);
  }

  /// Bir yoruma cevap yazar/günceller (boş reply → cevabı temizler).
  Future<void> replyToReview({
    required int reviewId,
    required String reply,
  }) async {
    await _apiClient.postData(
      '/business/review-reply.php',
      body: {'review_id': reviewId, 'reply': reply},
    );
  }

  /// Bir yorumu beğenir / beğeniyi kaldırır.
  Future<void> likeReview({required int reviewId, required bool liked}) async {
    await _apiClient.postData(
      '/business/review-like.php',
      body: {'review_id': reviewId, 'liked': liked},
    );
  }

  /// Boost paketleri + mevcut/geçmiş boost durumu (gerçek veriden).
  Future<Map<String, dynamic>> getBoostPackages() async {
    final data = await _apiClient.getData('/business/boost-packages.php');
    return Map<String, dynamic>.from(data);
  }

  /// Bir boost paketi için talep oluşturur (ödeme yok; gerçek kayıt).
  Future<Map<String, dynamic>> requestBoostPackage({
    required int packageId,
    String? note,
  }) async {
    final data = await _apiClient.postData(
      '/business/boost-request.php',
      body: {
        'package_id': packageId,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return Map<String, dynamic>.from(data);
  }

  /// Webey işletme aboneliği durumu (YALNIZCA GÖSTERİM).
  /// Ödeme/IBAN/satın alma CTA yok; eski iyzico aboneliğine bakmaz.
  Future<Map<String, dynamic>> getSubscription() async {
    final data = await _apiClient.getData('/business/subscription.php');
    return Map<String, dynamic>.from(data);
  }

  Future<void> markAppointmentDeposit({
    required int appointmentId,
    required String status,
  }) async {
    await _apiClient.postData(
      '/business/appointment-deposit.php',
      body: {'appointment_id': appointmentId, 'status': status},
    );
  }

  /// Manuel IBAN kapora: müşterinin "IBAN'a yolladım" bildirimini onaylar/reddeder.
  /// action: 'confirm' → kapora paid + randevu approved; 'reject' → not_received.
  /// İyzico/online ödeme akışını etkilemez.
  Future<Map<String, dynamic>> confirmAppointmentDeposit({
    required int appointmentId,
    required String action,
  }) async {
    final data = await _apiClient.postData(
      '/business/appointment-deposit-confirm.php',
      body: {'appointment_id': appointmentId, 'action': action},
    );
    return data;
  }

  // ── Kampanyalar ─────────────────────────────────────────────────────────
  /// İşletmenin kampanyaları (archived hariç) + durum özeti.
  Future<({List<BusinessCampaign> items, Map<String, int> summary})>
  getCampaigns() async {
    if (ApiConfig.useMockBusiness) {
      return (items: <BusinessCampaign>[], summary: <String, int>{});
    }
    final data = await _apiClient.getData('/business/campaigns.php');
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => BusinessCampaign.fromJson(Map<String, Object?>.from(m)))
        .toList();
    final summaryRaw = data['summary'];
    final summary = <String, int>{};
    if (summaryRaw is Map) {
      summaryRaw.forEach((k, v) {
        final n = v is num ? v.toInt() : int.tryParse(v.toString());
        if (n != null) summary[k.toString()] = n;
      });
    }
    return (items: items, summary: summary);
  }

  /// Kampanya oluşturur/günceller; kaydedilen kampanyayı + (varsa) çakışma
  /// uyarısını döner. Çakışma uyarısı engel değildir (en avantajlı uygulanır).
  Future<({BusinessCampaign campaign, String? conflictWarning})> saveCampaign(
    BusinessCampaign campaign,
  ) async {
    final data = await _apiClient.postData(
      '/business/campaign-save.php',
      body: campaign.toSaveBody(),
    );
    final saved = data['campaign'];
    final warning = data['conflict_warning']?.toString();
    final result = saved is Map
        ? BusinessCampaign.fromJson(Map<String, Object?>.from(saved))
        : campaign;
    return (
      campaign: result,
      conflictWarning: (warning != null && warning.isNotEmpty) ? warning : null,
    );
  }

  /// Kampanyayı aktif/pasif yapar.
  Future<void> setCampaignStatus({
    required int id,
    required bool active,
  }) async {
    await _apiClient.postData(
      '/business/campaign-status.php',
      body: {'id': id, 'status': active ? 'active' : 'paused'},
    );
  }

  /// Kampanyayı güvenli biçimde arşivler (hard delete yok).
  Future<void> deleteCampaign(int id) async {
    await _apiClient.postData('/business/campaign-delete.php', body: {'id': id});
  }

  static BusinessDashboard _mockDashboard() {
    final todayItems = MockData.businessAppointments
        .take(6)
        .map(_fromSharedAppointment)
        .toList();
    final pendingItems = MockData.businessAppointments
        .where(
          (item) =>
              item.status == AppointmentStatus.pending ||
              item.status == AppointmentStatus.cancellationRequested,
        )
        .map(_fromSharedAppointment)
        .toList();

    return BusinessDashboard(
      summary: BusinessDashboardSummary(
        todayAppointments: todayItems.length,
        pendingAppointments: pendingItems.length,
        upcomingAppointments: MockData.businessAppointments
            .where(
              (item) =>
                  item.status == AppointmentStatus.approved ||
                  item.status == AppointmentStatus.pending,
            )
            .length,
        completedThisMonth: MockData.analyticsSummary.completedAppointments,
        cancelledThisMonth: MockData.analyticsSummary.cancelledAppointments,
        monthlyRevenueEstimate: MockData.analyticsSummary.totalRevenueEstimate,
      ),
      todayItems: todayItems,
      pendingItems: pendingItems,
    );
  }

  static List<BusinessAppointment> _mockAppointments({
    required String status,
    String? date,
  }) {
    Iterable<Appointment> items = MockData.businessAppointments;
    items = switch (status) {
      'today' => items.take(6),
      'upcoming' => items.where(
        (item) =>
            item.status == AppointmentStatus.approved ||
            item.status == AppointmentStatus.pending,
      ),
      'pending' => items.where(
        (item) =>
            item.status == AppointmentStatus.pending ||
            item.status == AppointmentStatus.cancellationRequested,
      ),
      'completed' => items.where(
        (item) => item.status == AppointmentStatus.completed,
      ),
      'cancelled' => items.where(
        (item) =>
            item.status == AppointmentStatus.cancelled ||
            item.status == AppointmentStatus.rejected ||
            item.status == AppointmentStatus.noShow,
      ),
      _ => items,
    };

    final mapped = items.map(_fromSharedAppointment).toList();
    if (date == null || date.isEmpty) return mapped;
    return mapped.where((item) => item.date == date).toList();
  }

  static BusinessAppointment _fromSharedAppointment(Appointment appointment) {
    final start = appointment.startAt;
    final end = appointment.endAt;
    return BusinessAppointment(
      id: appointment.id,
      status: _statusName(appointment.status),
      startsAt: start,
      endsAt: end,
      date: _date(start),
      time: _time(start),
      customerName: appointment.customerName,
      customerPhone: null,
      serviceName: appointment.serviceName,
      staffName: appointment.staffName,
      price: appointment.total,
      durationMinutes: end.difference(start).inMinutes,
      note: appointment.notes ?? appointment.userNote,
    );
  }

  static String _statusName(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.approved => 'approved',
      AppointmentStatus.completed => 'completed',
      AppointmentStatus.cancelled => 'cancelled',
      AppointmentStatus.cancellationRequested => 'cancellation_requested',
      AppointmentStatus.noShow => 'no_show',
      AppointmentStatus.rejected => 'rejected',
      AppointmentStatus.pending => 'pending',
    };
  }

  static String _date(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static String _time(DateTime value) {
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  static List<BusinessServiceItem> _mockServicesStore = [
    const BusinessServiceItem(
      id: 1,
      name: 'Protez Tirnak + Kalici Oje',
      description: 'Premium jel uygulama ve kalici oje.',
      price: 1200,
      durationMinutes: 90,
      category: 'nail',
      sortOrder: 1,
    ),
    const BusinessServiceItem(
      id: 2,
      name: 'Kalici Oje',
      description: 'Uzun sure dayanikli parlak gorunum.',
      price: 650,
      durationMinutes: 45,
      category: 'nail',
      sortOrder: 2,
    ),
    const BusinessServiceItem(
      id: 3,
      name: 'Manikur',
      description: 'Klasik bakim ve sekillendirme.',
      price: 450,
      durationMinutes: 35,
      category: 'nail',
      sortOrder: 3,
    ),
    const BusinessServiceItem(
      id: 4,
      name: 'Pedikur',
      description: 'Topuk bakimi ve kalici oje.',
      price: 620,
      durationMinutes: 60,
      category: 'spa',
      sortOrder: 4,
    ),
    const BusinessServiceItem(
      id: 5,
      name: 'Lazer Epilasyon',
      description: 'Bolgesel lazer epilasyon seansi.',
      price: 500,
      durationMinutes: 45,
      category: 'skin',
      isActive: false,
      sortOrder: 5,
    ),
  ];

  static List<BusinessStaffItem> _mockStaffStore = [
    const BusinessStaffItem(
      id: 1,
      name: 'Ece Yildiz',
      role: 'Nail Artist',
      phone: '+90 555 000 10 01',
      isActive: true,
      serviceIds: [1, 2, 3],
    ),
    const BusinessStaffItem(
      id: 2,
      name: 'Mina Acar',
      role: 'Kas & Kirpik Uzmani',
      phone: '+90 555 000 10 02',
      isActive: true,
      serviceIds: [2, 3],
    ),
    const BusinessStaffItem(
      id: 3,
      name: 'Lara Demir',
      role: 'Nail Art Uzmani',
      isActive: false,
      serviceIds: [1],
    ),
  ];

  static List<BusinessServiceItem> _mockServices({
    required bool includeInactive,
  }) {
    final items = includeInactive
        ? _mockServicesStore
        : _mockServicesStore.where((item) => item.isActive);
    return List<BusinessServiceItem>.unmodifiable(items);
  }

  static BusinessServiceItem _saveMockService(BusinessServiceItem item) {
    final next = item.id == null ? item.copyWith(id: _nextServiceId()) : item;
    final index = _mockServicesStore.indexWhere((entry) => entry.id == next.id);
    if (index == -1) {
      _mockServicesStore = [..._mockServicesStore, next];
    } else {
      _mockServicesStore[index] = next;
    }
    return next;
  }

  static BusinessStaffItem _saveMockStaff(BusinessStaffItem item) {
    final next = item.id == null ? item.copyWith(id: _nextStaffId()) : item;
    final index = _mockStaffStore.indexWhere((entry) => entry.id == next.id);
    if (index == -1) {
      _mockStaffStore = [..._mockStaffStore, next];
    } else {
      _mockStaffStore[index] = next;
    }
    return next;
  }

  static int _nextServiceId() {
    return _mockServicesStore.fold<int>(0, (max, item) {
          final id = item.id ?? 0;
          return id > max ? id : max;
        }) +
        1;
  }

  static int _nextStaffId() {
    return _mockStaffStore.fold<int>(0, (max, item) {
          final id = item.id ?? 0;
          return id > max ? id : max;
        }) +
        1;
  }
}
