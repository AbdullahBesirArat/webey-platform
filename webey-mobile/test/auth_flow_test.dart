import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webey_mobile/core/theme/webey_theme.dart';
import 'package:webey_mobile/features/auth/presentation/auth_flow.dart';
import 'package:webey_mobile/shared/models/beauty_models.dart';
import 'package:webey_mobile/shared/services/auth_service.dart';
import 'package:webey_mobile/shared/services/result.dart';

import 'helpers/no_network_http_overrides.dart';

final _testSession = AuthSession(
  accessTokenMock: 'fake_test_access',
  refreshTokenMock: 'fake_test_refresh',
  expiresAt: DateTime(2026, 5, 25, 12),
  user: AuthUser(
    id: 'test-user',
    fullName: 'Test User',
    email: 'test@example.com',
    role: UserRole.customer,
    isEmailVerified: true,
    createdAt: DateTime(2026, 5, 25),
  ),
);

class _FakeAuthService implements AuthService {
  AuthSession? _session;

  @override
  Future<Result<AuthSession>> login(String email, String password) async {
    if (!email.contains('@') || password.isEmpty) {
      return Result.fail('Fake auth rejected login.');
    }
    _session = _testSession;
    return Result.ok(_session!);
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
  }) async {
    _session = _testSession;
    return Result.ok(_session!);
  }

  @override
  Future<Result<void>> sendCustomerEmailOtp(
    String email,
    String purpose,
  ) async {
    return email.contains('@') ? Result.empty() : Result.fail('Invalid email.');
  }

  @override
  Future<Result<void>> verifyCustomerEmailOtp(
    String email,
    String code,
    String purpose,
  ) async {
    return RegExp(r'^\d{6}$').hasMatch(code)
        ? Result.empty()
        : Result.fail('Invalid code.');
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
    return Result.empty();
  }

  @override
  Future<Result<AuthUser>> me() async {
    final user = _session?.user;
    return user == null ? Result.fail('No fake session.') : Result.ok(user);
  }

  @override
  Future<Result<void>> logout() => signOut();

  @override
  Future<Result<AuthSession>> businessLogin(String email, String password) {
    return login(email, password);
  }

  @override
  Future<Result<AuthSession>> businessRegister({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) {
    return login(email, password);
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
    return Result.empty();
  }

  @override
  Future<Result<AuthUser>> businessMe() => me();

  @override
  Future<Result<void>> businessLogout() => signOut();

  @override
  Future<Result<AuthSession>> signInWithPhoneMock(
    String phone, {
    UserRole role = UserRole.customer,
  }) async {
    _session = _testSession;
    return Result.ok(_session!);
  }

  @override
  Future<Result<AuthSession>> signInWithEmailMock(
    String email, {
    UserRole role = UserRole.customer,
  }) {
    return login(email, 'password');
  }

  @override
  Future<Result<void>> signOut() async {
    _session = null;
    return Result.empty();
  }

  @override
  Future<Result<AuthUser>> getCurrentUser() => me();

  @override
  Future<bool> isAuthenticated() async => _session != null;

  @override
  Future<Result<AuthSession>> refreshSessionMock() async {
    final session = _session;
    return session == null
        ? Result.fail('No fake session.')
        : Result.ok(session);
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(theme: WebeyTheme.customer(), home: child);
}

AuthFlow _authFlow({
  required VoidCallback onAuthenticated,
  VoidCallback? onGuest,
}) {
  return AuthFlow(
    authService: _FakeAuthService(),
    onAuthenticated: onAuthenticated,
    onGuest: onGuest ?? () {},
  );
}

Future<void> _pumpAuth(WidgetTester tester) {
  return tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
}

void main() {
  installNoNetworkHttpOverrides();

  group('AuthFlow', () {
    testWidgets('welcome screen shows primary auth actions', (tester) async {
      await tester.pumpWidget(
        _wrap(_authFlow(onAuthenticated: () {}, onGuest: () {})),
      );

      expect(find.text('E-posta ile Giriş Yap'), findsOneWidget);
      expect(find.text('Hesap Oluştur'), findsOneWidget);
      expect(find.text('Misafir olarak keşfet'), findsOneWidget);
    });

    testWidgets('register action opens email verification step', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_authFlow(onAuthenticated: () {})));

      await tester.tap(find.text('Hesap Oluştur'));
      await _pumpAuth(tester);

      expect(find.text('Doğrulama Kodu Gönder'), findsOneWidget);
    });

    testWidgets('login action completes fake authentication', (tester) async {
      var authenticated = false;

      await tester.pumpWidget(
        _wrap(_authFlow(onAuthenticated: () => authenticated = true)),
      );

      await tester.tap(find.text('E-posta ile Giriş Yap'));
      await _pumpAuth(tester);
      await tester.enterText(find.byType(TextField).at(0), 'test@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'password');
      await tester.tap(find.text('Giriş Yap'));
      await _pumpAuth(tester);

      expect(authenticated, isTrue);
    });

    testWidgets('login action shows fake auth error for invalid input', (
      tester,
    ) async {
      var authenticated = false;

      await tester.pumpWidget(
        _wrap(_authFlow(onAuthenticated: () => authenticated = true)),
      );

      await tester.tap(find.text('E-posta ile Giriş Yap'));
      await _pumpAuth(tester);
      await tester.tap(find.text('Giriş Yap'));
      await _pumpAuth(tester);

      expect(authenticated, isFalse);
      expect(find.text('Fake auth rejected login.'), findsOneWidget);
    });
  });
}
