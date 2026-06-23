import '../../../../../core/config/api_config.dart';
import '../../../../../shared/services/api_client.dart';
import '../models/customer_notification.dart';

class CustomerNotificationRepository {
  const CustomerNotificationRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? const ApiClient();

  static const instance = CustomerNotificationRepository();

  final ApiClient _apiClient;

  Future<CustomerNotificationsResult> getNotifications() async {
    if (ApiConfig.useMockNotifications) {
      return CustomerNotificationsResult(
        items: _kMockNotifications,
        unreadCount: _kMockNotifications.where((n) => !n.read).length,
      );
    }

    try {
      final data = await _apiClient.getData('/customer/notifications.php');
      return CustomerNotificationsResult.fromJson(data);
    } catch (_) {
      return CustomerNotificationsResult.empty;
    }
  }

  Future<void> markAsRead(String id) async {
    if (ApiConfig.useMockNotifications) return;
    try {
      await _apiClient.postData(
        '/customer/notifications/read.php',
        body: {'id': id},
      );
    } catch (_) {}
  }

  Future<void> markAllAsRead() async {
    if (ApiConfig.useMockNotifications) return;
    try {
      await _apiClient.postData(
        '/customer/notifications/read.php',
        body: {'all': true},
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>> getPreferences() async {
    try {
      final data = await _apiClient.getData(
        '/customer/notification-preferences.php',
      );
      final prefs = data['prefs'];
      if (prefs is Map) {
        return prefs.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return const {};
  }

  Future<void> savePreferences(Map<String, dynamic> prefs) async {
    try {
      await _apiClient.postData(
        '/customer/notification-preferences.php',
        body: {'prefs': prefs},
      );
    } catch (_) {}
  }
}

const _kMockNotifications = [
  CustomerNotification(
    id: 'n1',
    type: 'appt_reminder',
    title: 'Randevunuz yarın',
    body: "Luna Nail Studio'da Ece Yıldız ile randevunuz yarın 16:30'da.",
    read: false,
    createdAt: '',
    businessName: 'Luna Nail Studio',
  ),
  CustomerNotification(
    id: 'n2',
    type: 'deposit',
    title: 'Kapora ödemeniz alındı',
    body: '300 TL kapora ödemeniz başarıyla alındı. Kalan ödeme salonda.',
    read: true,
    createdAt: '',
    businessName: 'Luna Nail Studio',
  ),
  CustomerNotification(
    id: 'n3',
    type: 'info',
    title: 'Favori salonunda boşluk oluştu',
    body: "Mina Beauty Studio'da bugün 18:00 için boşluk oluştu.",
    read: false,
    createdAt: '',
    businessName: 'Mina Beauty Studio',
  ),
  CustomerNotification(
    id: 'n4',
    type: 'info',
    title: 'Sezon kampanyası',
    body: "Luna Nail Studio'da Mayıs boyunca %20 indirimli kalıcı oje.",
    read: true,
    createdAt: '',
    businessName: 'Luna Nail Studio',
  ),
  CustomerNotification(
    id: 'n5',
    type: 'info',
    title: 'Değerlendirme zamanı',
    body: 'Geçen haftaki Luna Nail Studio deneyiminizi değerlendirdiniz mi?',
    read: true,
    createdAt: '',
  ),
  CustomerNotification(
    id: 'n6',
    type: 'appt_confirmed',
    title: 'Randevunuz onaylandı',
    body: "Maison Rose'da Selin Kara ile randevunuz onaylandı. 24 May · 11:00.",
    read: true,
    createdAt: '',
    businessName: 'Maison Rose',
  ),
];
