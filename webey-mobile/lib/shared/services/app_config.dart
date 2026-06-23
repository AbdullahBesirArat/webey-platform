enum AppEnvironment { development, staging, production }

class AppConfig {
  const AppConfig({
    required this.appName,
    required this.environment,
    required this.apiBaseUrl,
    required this.paymentMode,
    required this.enableMockData,
    required this.enableDebugBanner,
    required this.customerBuildName,
    required this.businessBuildName,
    this.enableMockErrors = false,
    this.showDemoPaymentCopy = true,
  });

  final String appName;
  final AppEnvironment environment;
  final String apiBaseUrl;
  final String paymentMode;
  final bool enableMockData;
  final bool enableDebugBanner;
  final String customerBuildName;
  final String businessBuildName;
  final bool enableMockErrors;
  final bool showDemoPaymentCopy;

  bool get isProduction => environment == AppEnvironment.production;

  static AppConfig current = AppConfig.development();

  static void configure(AppConfig config) {
    current = config;
  }

  factory AppConfig.development() {
    return const AppConfig(
      appName: 'Webey Beauty',
      environment: AppEnvironment.development,
      apiBaseUrl: 'https://api-dev.webey.beauty',
      paymentMode: 'demo',
      enableMockData: true,
      enableDebugBanner: true,
      customerBuildName: 'Webey Beauty Customer Dev',
      businessBuildName: 'Webey Beauty Business Dev',
    );
  }

  factory AppConfig.staging() {
    return const AppConfig(
      appName: 'Webey Beauty',
      environment: AppEnvironment.staging,
      apiBaseUrl: 'https://api-staging.webey.beauty',
      paymentMode: 'sandbox',
      enableMockData: true,
      enableDebugBanner: true,
      customerBuildName: 'Webey Beauty Customer Staging',
      businessBuildName: 'Webey Beauty Business Staging',
    );
  }

  factory AppConfig.production() {
    return const AppConfig(
      appName: 'Webey Beauty',
      environment: AppEnvironment.production,
      apiBaseUrl: 'https://api.webey.beauty',
      paymentMode: 'live',
      enableMockData: false,
      enableDebugBanner: false,
      customerBuildName: 'Webey Beauty',
      businessBuildName: 'Webey Beauty Business',
      showDemoPaymentCopy: false,
    );
  }
}
