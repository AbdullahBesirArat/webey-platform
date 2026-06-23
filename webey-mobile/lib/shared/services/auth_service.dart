import '../../core/config/api_config.dart';
import '../../core/storage/secure_token_storage.dart';
import '../../features/auth/data/models/auth_response.dart';
import '../../features/auth/data/models/auth_user.dart';
import '../models/beauty_models.dart';
import 'api_client.dart';
import 'app_logger.dart';
import 'result.dart';

abstract class AuthService {
  Future<Result<AuthSession>> login(String email, String password);

  Future<Result<AuthSession>> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    String? city,
    String? district,
    String? neighborhood,
    String? addressLine,
    double? latitude,
    double? longitude,
  });

  Future<Result<void>> sendCustomerEmailOtp(String email, String purpose);

  Future<Result<void>> verifyCustomerEmailOtp(
    String email,
    String code,
    String purpose,
  );

  Future<Result<void>> requestCustomerPasswordReset(String email);

  Future<Result<void>> confirmCustomerPasswordReset(
    String email,
    String code,
    String newPassword,
  );

  Future<Result<AuthUser>> me();

  Future<Result<void>> logout();

  Future<Result<AuthSession>> businessLogin(String email, String password);

  Future<Result<AuthSession>> businessRegister({
    required String name,
    required String email,
    required String phone,
    required String password,
  });

  Future<Result<void>> sendBusinessEmailOtp(String email, String purpose);

  Future<Result<void>> verifyBusinessEmailOtp(
    String email,
    String code,
    String purpose,
  );

  Future<Result<void>> requestBusinessPasswordReset(String email);

  Future<Result<void>> confirmBusinessPasswordReset(
    String email,
    String code,
    String newPassword,
  );

  Future<Result<AuthUser>> businessMe();

  Future<Result<void>> businessLogout();

  Future<Result<AuthSession>> signInWithPhoneMock(
    String phone, {
    UserRole role = UserRole.customer,
  });

  Future<Result<AuthSession>> signInWithEmailMock(
    String email, {
    UserRole role = UserRole.customer,
  });

  Future<Result<void>> signOut();

  Future<Result<AuthUser>> getCurrentUser();

  Future<bool> isAuthenticated();

  Future<Result<AuthSession>> refreshSessionMock();
}

class WebeyAuthService implements AuthService {
  WebeyAuthService._({
    ApiClient? apiClient,
    SecureTokenStorage? tokenStorage,
    AuthService? mock,
  }) : _apiClient = apiClient ?? const ApiClient(),
       _tokenStorage = tokenStorage ?? const SecureTokenStorage(),
       _mock = mock ?? MockAuthService.instance;

  static final instance = WebeyAuthService._();

  final ApiClient _apiClient;
  final SecureTokenStorage _tokenStorage;
  final AuthService _mock;

  bool get _useMock => ApiConfig.useMockAuth;

  @override
  Future<Result<AuthSession>> login(String email, String password) {
    if (_useMock) {
      return _mock.signInWithEmailMock(email, role: UserRole.customer);
    }
    return _authenticate(
      path: '/auth/login.php',
      body: {'email': email, 'password': password, ..._deviceMeta()},
      expectedUserType: 'customer',
    );
  }

  @override
  Future<Result<void>> sendCustomerEmailOtp(
    String email,
    String purpose,
  ) async {
    if (_useMock) return Result.empty();
    return _postEmpty('/auth/email-send-otp.php', {
      'email': email.trim(),
      'purpose': purpose,
    });
  }

  @override
  Future<Result<void>> verifyCustomerEmailOtp(
    String email,
    String code,
    String purpose,
  ) async {
    if (_useMock) return Result.empty();
    return _postEmpty('/auth/email-verify-otp.php', {
      'email': email.trim(),
      'code': code.trim(),
      'purpose': purpose,
    });
  }

  @override
  Future<Result<void>> requestCustomerPasswordReset(String email) async {
    if (_useMock) return Result.empty();
    return _postEmpty('/auth/password-reset-request.php', {
      'email': email.trim(),
    });
  }

  @override
  Future<Result<void>> confirmCustomerPasswordReset(
    String email,
    String code,
    String newPassword,
  ) async {
    if (_useMock) return Result.empty();
    return _postEmpty('/auth/password-reset-confirm.php', {
      'email': email.trim(),
      'code': code.trim(),
      'new_password': newPassword,
    });
  }

  @override
  Future<Result<AuthSession>> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    String? city,
    String? district,
    String? neighborhood,
    String? addressLine,
    double? latitude,
    double? longitude,
  }) {
    if (_useMock) {
      return _mock.signInWithEmailMock(email, role: UserRole.customer);
    }
    return _authenticate(
      path: '/auth/register.php',
      body: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
        if (district != null && district.trim().isNotEmpty)
          'district': district.trim(),
        if (neighborhood != null && neighborhood.trim().isNotEmpty)
          'neighborhood': neighborhood.trim(),
        if (addressLine != null && addressLine.trim().isNotEmpty)
          'address_line': addressLine.trim(),
        'latitude': ?latitude,
        'longitude': ?longitude,
        ..._deviceMeta(),
      },
      expectedUserType: 'customer',
    );
  }

  @override
  Future<Result<AuthUser>> me() async {
    if (_useMock) {
      return _mock.getCurrentUser();
    }
    final token = await _tokenStorage.readToken();
    if (token == null || token.isEmpty) {
      return Result.fail('Aktif oturum yok.', statusCode: 401);
    }
    final storedType = await _tokenStorage.readUserType();
    if (storedType != null && storedType != 'customer') {
      return Result.fail('Müşteri hesabı gerekli.', statusCode: 403);
    }
    try {
      final data = await _apiClient.getData('/auth/me.php');
      final user = _userFromData(data, fallbackType: 'customer');
      await _tokenStorage.saveUserType('customer');
      return Result.ok(user.toBeautyAuthUser());
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _tokenStorage.clearAll();
      }
      return Result.fail(error.message, statusCode: error.statusCode);
    }
  }

  @override
  Future<Result<void>> logout() async {
    if (_useMock) {
      return _mock.signOut();
    }
    try {
      await _apiClient.postData('/auth/logout.php');
    } on ApiException catch (error) {
      AppLogger.warning('Remote logout failed: ${error.message}');
    } finally {
      await _tokenStorage.clearAll();
    }
    return Result.empty();
  }

  @override
  Future<Result<AuthSession>> businessLogin(String email, String password) {
    if (_useMock) {
      return _mock.signInWithEmailMock(email, role: UserRole.businessOwner);
    }
    return _authenticate(
      path: '/business/auth/login.php',
      body: {'email': email, 'password': password, ..._deviceMeta()},
      expectedUserType: 'business',
    );
  }

  @override
  Future<Result<AuthSession>> businessRegister({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) {
    if (_useMock) {
      return _mock.signInWithEmailMock(email, role: UserRole.businessOwner);
    }
    return _authenticate(
      path: '/business/auth/register.php',
      body: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        ..._deviceMeta(),
      },
      expectedUserType: 'business',
    );
  }

  @override
  Future<Result<void>> sendBusinessEmailOtp(
    String email,
    String purpose,
  ) async {
    if (_useMock) return Result.empty();
    return _postEmpty('/business/auth/email-send-otp.php', {
      'email': email.trim(),
      'purpose': purpose,
    });
  }

  @override
  Future<Result<void>> verifyBusinessEmailOtp(
    String email,
    String code,
    String purpose,
  ) async {
    if (_useMock) return Result.empty();
    return _postEmpty('/business/auth/email-verify-otp.php', {
      'email': email.trim(),
      'code': code.trim(),
      'purpose': purpose,
    });
  }

  @override
  Future<Result<void>> requestBusinessPasswordReset(String email) async {
    if (_useMock) return Result.empty();
    return _postEmpty('/business/auth/password-reset-request.php', {
      'email': email.trim(),
    });
  }

  @override
  Future<Result<void>> confirmBusinessPasswordReset(
    String email,
    String code,
    String newPassword,
  ) async {
    if (_useMock) return Result.empty();
    return _postEmpty('/business/auth/password-reset-confirm.php', {
      'email': email.trim(),
      'code': code.trim(),
      'new_password': newPassword,
    });
  }

  @override
  Future<Result<AuthUser>> businessMe() async {
    if (_useMock) {
      return _mock.getCurrentUser();
    }
    final token = await _tokenStorage.readToken();
    if (token == null || token.isEmpty) {
      return Result.fail('Aktif oturum yok.', statusCode: 401);
    }
    final storedType = await _tokenStorage.readUserType();
    if (storedType != null && storedType != 'business') {
      return Result.fail('İşletme hesabı bulunamadı.', statusCode: 403);
    }
    try {
      final data = await _apiClient.getData('/business/auth/me.php');
      final user = _userFromData(data, fallbackType: 'business');
      if (user.userType != 'business') {
        await _tokenStorage.clearAll();
        return Result.fail('İşletme hesabı bulunamadı.', statusCode: 403);
      }
      await _tokenStorage.saveUserType('business');
      return Result.ok(user.toBeautyAuthUser());
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _tokenStorage.clearAll();
      }
      return Result.fail(error.message, statusCode: error.statusCode);
    }
  }

  @override
  Future<Result<void>> businessLogout() async {
    if (_useMock) {
      return _mock.signOut();
    }
    try {
      await _apiClient.postData('/business/auth/logout.php');
    } on ApiException catch (error) {
      AppLogger.warning('Remote business logout failed: ${error.message}');
    } finally {
      await _tokenStorage.clearAll();
    }
    return Result.empty();
  }

  Future<Result<AuthSession>> _authenticate({
    required String path,
    required Map<String, Object?> body,
    required String expectedUserType,
  }) async {
    try {
      final data = await _apiClient.postData(path, body: body);
      final response = AuthResponse.fromJson(data);
      final user = response.user;

      if (response.token.isEmpty) {
        return Result.fail('Oturum tokenı alınamadı.');
      }
      if (expectedUserType == 'business' && user.userType != 'business') {
        await _tokenStorage.clearAll();
        return Result.fail('İşletme hesabı bulunamadı.', statusCode: 403);
      }
      if (expectedUserType == 'customer' && user.userType != 'customer') {
        await _tokenStorage.clearAll();
        return Result.fail('Müşteri hesabı gerekli.', statusCode: 403);
      }

      await _tokenStorage.saveToken(response.token);
      await _tokenStorage.saveUserType(expectedUserType);

      return Result.ok(
        AuthSession(
          accessTokenMock: response.token,
          refreshTokenMock: '',
          expiresAt: DateTime.now().add(
            Duration(seconds: response.expiresIn > 0 ? response.expiresIn : 0),
          ),
          user: user.toBeautyAuthUser(),
        ),
      );
    } on ApiException catch (error) {
      return Result.fail(error.message, statusCode: error.statusCode);
    }
  }

  Future<Result<void>> _postEmpty(
    String path,
    Map<String, Object?> body,
  ) async {
    try {
      await _apiClient.postData(path, body: body);
      return Result.empty();
    } on ApiException catch (error) {
      return Result.fail(error.message, statusCode: error.statusCode);
    }
  }

  MobileAuthUser _userFromData(
    Map<String, Object?> data, {
    required String fallbackType,
  }) {
    final userJson = data['user'];
    if (userJson is Map) {
      final merged = Map<String, Object?>.from(userJson);
      final businessJson = data['business'];
      if (businessJson is Map) {
        final business = Map<String, Object?>.from(businessJson);
        merged['business_id'] ??= business['id'];
        merged['business_name'] ??= business['name'];
        merged['business_onboarding_completed'] ??=
            business['onboarding_completed'] ??
            business['business_onboarding_completed'];
        merged['onboarding_step'] ??=
            business['onboarding_step'] ?? business['step'];
      }
      return MobileAuthUser.fromJson(merged);
    }
    return MobileAuthUser(id: '', userType: fallbackType);
  }

  Map<String, String> _deviceMeta() {
    return const {
      'platform': String.fromEnvironment(
        'WEBEY_PLATFORM',
        defaultValue: 'unknown',
      ),
      'app_version': String.fromEnvironment(
        'WEBEY_APP_VERSION',
        defaultValue: '1.0.0',
      ),
    };
  }

  @override
  Future<Result<AuthSession>> signInWithPhoneMock(
    String phone, {
    UserRole role = UserRole.customer,
  }) {
    return _mock.signInWithPhoneMock(phone, role: role);
  }

  @override
  Future<Result<AuthSession>> signInWithEmailMock(
    String email, {
    UserRole role = UserRole.customer,
  }) {
    return _mock.signInWithEmailMock(email, role: role);
  }

  @override
  Future<Result<void>> signOut() => logout();

  @override
  Future<Result<AuthUser>> getCurrentUser() => me();

  @override
  Future<bool> isAuthenticated() async {
    if (_useMock) {
      return _mock.isAuthenticated();
    }
    final token = await _tokenStorage.readToken();
    return token != null && token.isNotEmpty;
  }

  @override
  Future<Result<AuthSession>> refreshSessionMock() {
    return _mock.refreshSessionMock();
  }
}

class MockAuthService implements AuthService {
  MockAuthService._();

  static final instance = MockAuthService._();

  AuthSession? _session;

  @override
  Future<Result<AuthSession>> login(String email, String password) {
    return signInWithEmailMock(email, role: UserRole.customer);
  }

  @override
  Future<Result<AuthSession>> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    String? city,
    String? district,
    String? neighborhood,
    String? addressLine,
    double? latitude,
    double? longitude,
  }) {
    return signInWithEmailMock(email, role: UserRole.customer);
  }

  @override
  Future<Result<void>> sendCustomerEmailOtp(
    String email,
    String purpose,
  ) async {
    return Result.empty();
  }

  @override
  Future<Result<void>> verifyCustomerEmailOtp(
    String email,
    String code,
    String purpose,
  ) async {
    if (!_looksLikeOtp(code)) {
      return Result.fail('Dogrulama kodu 6 haneli olmali.');
    }
    return Result.empty();
  }

  @override
  Future<Result<void>> requestCustomerPasswordReset(String email) async {
    return Result.empty();
  }

  @override
  Future<Result<void>> confirmCustomerPasswordReset(
    String email,
    String code,
    String newPassword,
  ) async {
    if (!_looksLikeOtp(code)) {
      return Result.fail('Dogrulama kodu 6 haneli olmali.');
    }
    return Result.empty();
  }

  @override
  Future<Result<AuthUser>> me() => getCurrentUser();

  @override
  Future<Result<void>> logout() => signOut();

  @override
  Future<Result<AuthSession>> businessLogin(String email, String password) {
    return signInWithEmailMock(email, role: UserRole.businessOwner);
  }

  @override
  Future<Result<AuthSession>> businessRegister({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) {
    return signInWithEmailMock(email, role: UserRole.businessOwner);
  }

  @override
  Future<Result<void>> sendBusinessEmailOtp(
    String email,
    String purpose,
  ) async {
    return Result.empty();
  }

  @override
  Future<Result<void>> verifyBusinessEmailOtp(
    String email,
    String code,
    String purpose,
  ) async {
    if (!_looksLikeOtp(code)) {
      return Result.fail('Dogrulama kodu 6 haneli olmali.');
    }
    return Result.empty();
  }

  @override
  Future<Result<void>> requestBusinessPasswordReset(String email) async {
    return Result.empty();
  }

  @override
  Future<Result<void>> confirmBusinessPasswordReset(
    String email,
    String code,
    String newPassword,
  ) async {
    if (!_looksLikeOtp(code)) {
      return Result.fail('Dogrulama kodu 6 haneli olmali.');
    }
    return Result.empty();
  }

  @override
  Future<Result<AuthUser>> businessMe() => getCurrentUser();

  @override
  Future<Result<void>> businessLogout() => signOut();

  @override
  Future<Result<AuthSession>> signInWithPhoneMock(
    String phone, {
    UserRole role = UserRole.customer,
  }) async {
    if (!_looksLikePhone(phone)) {
      return Result.fail('Telefon numarası geçerli görünmüyor.');
    }
    AppLogger.info('Mock phone login started');
    _session = _sessionFor(role, phone: phone, phoneVerified: true);
    return Result.ok(_session!);
  }

  @override
  Future<Result<AuthSession>> signInWithEmailMock(
    String email, {
    UserRole role = UserRole.customer,
  }) async {
    if (!_looksLikeEmail(email)) {
      return Result.fail('E-posta adresi geçerli görünmüyor.');
    }
    AppLogger.info('Mock email login started');
    _session = _sessionFor(role, email: email, emailVerified: true);
    return Result.ok(_session!);
  }

  @override
  Future<Result<void>> signOut() async {
    _session = null;
    AppLogger.info('Mock session signed out');
    return Result.empty();
  }

  @override
  Future<Result<AuthUser>> getCurrentUser() async {
    final user = _session?.user;
    if (user == null) return Result.fail('Aktif oturum yok.');
    return Result.ok(user);
  }

  @override
  Future<bool> isAuthenticated() async => _session != null;

  @override
  Future<Result<AuthSession>> refreshSessionMock() async {
    final existing = _session;
    if (existing == null) return Result.fail('Yenilenecek oturum yok.');
    _session = AuthSession(
      accessTokenMock: 'mock_access_${DateTime.now().millisecondsSinceEpoch}',
      refreshTokenMock: existing.refreshTokenMock,
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
      user: existing.user,
    );
    return Result.ok(_session!);
  }

  AuthSession _sessionFor(
    UserRole role, {
    String phone = '',
    String email = '',
    bool phoneVerified = false,
    bool emailVerified = false,
  }) {
    final user = AuthUser(
      id: role == UserRole.businessOwner ? 'bo_mock_1' : 'u_mock_1',
      fullName: role == UserRole.businessOwner
          ? 'Luna Studio Sahibi'
          : 'Ayşe Demir',
      phone: phone,
      email: email,
      role: role,
      isPhoneVerified: phoneVerified,
      isEmailVerified: emailVerified,
      createdAt: DateTime(2026, 5, 19),
    );
    return AuthSession(
      accessTokenMock: 'mock_access_${role.name}',
      refreshTokenMock: 'mock_refresh_${role.name}',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
      user: user,
    );
  }

  bool _looksLikeEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  bool _looksLikePhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10;
  }

  bool _looksLikeOtp(String value) {
    return RegExp(r'^\d{6}$').hasMatch(value.trim());
  }
}
