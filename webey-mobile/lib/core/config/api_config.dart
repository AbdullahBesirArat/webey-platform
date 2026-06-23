class ApiConfig {
  const ApiConfig._();

  static const baseUrl = String.fromEnvironment(
    'WEBEY_API_BASE_URL',
    defaultValue: 'https://webey.com.tr',
  );

  static const mobileBasePath = '/api/mobile';

  static const useMockAuth = bool.fromEnvironment(
    'WEBEY_USE_MOCK_AUTH',
    defaultValue: false,
  );

  static const useMockDiscovery = bool.fromEnvironment(
    'WEBEY_USE_MOCK_DISCOVERY',
    defaultValue: false,
  );

  static const useMockAppointments = bool.fromEnvironment(
    'WEBEY_USE_MOCK_APPOINTMENTS',
    defaultValue: false,
  );

  static const useMockNotifications = bool.fromEnvironment(
    'WEBEY_USE_MOCK_NOTIFICATIONS',
    defaultValue: false,
  );

  static const useMockProfile = bool.fromEnvironment(
    'WEBEY_USE_MOCK_PROFILE',
    defaultValue: false,
  );

  static const useMockBooking = bool.fromEnvironment(
    'WEBEY_USE_MOCK_BOOKING',
    defaultValue: false,
  );

  static const useMockBusiness = bool.fromEnvironment(
    'WEBEY_USE_MOCK_BUSINESS',
    defaultValue: false,
  );

  static const connectTimeout = Duration(seconds: 12);
  static const receiveTimeout = Duration(seconds: 20);

  static String get normalizedBaseUrl {
    final trimmed = baseUrl.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static String get mobileBaseUrl => '$normalizedBaseUrl$mobileBasePath';

  static String resolveUrl(String? path) {
    final value = path?.trim() ?? '';
    if (value.isEmpty) return '';
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return value;
    final cleanPath = value.startsWith('/') ? value : '/$value';
    return '$normalizedBaseUrl$cleanPath';
  }
}
