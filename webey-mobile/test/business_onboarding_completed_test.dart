import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webey_mobile/core/theme/webey_theme.dart';
import 'package:webey_mobile/features/auth/data/models/auth_user.dart';
import 'package:webey_mobile/features/business/business_start_flow.dart';
import 'package:webey_mobile/features/business/data/repositories/business_repository.dart';
import 'package:webey_mobile/features/business/presentation/business_onboarding_flow.dart';
import 'package:webey_mobile/shared/models/beauty_models.dart';
import 'package:webey_mobile/shared/services/api_client.dart';
import 'package:webey_mobile/shared/services/auth_service.dart';
import 'package:webey_mobile/shared/services/result.dart';

import 'helpers/no_network_http_overrides.dart';

AuthUser _businessUser({bool? completed, int? step}) {
  return AuthUser(
    id: 'business-user',
    fullName: 'Business User',
    email: 'owner@example.com',
    role: UserRole.businessOwner,
    businessOnboardingCompleted: completed,
    onboardingStep: step,
    createdAt: DateTime(2026, 5, 27),
  );
}

AuthSession _session(AuthUser user) {
  return AuthSession(
    accessTokenMock: 'fake_business_access',
    refreshTokenMock: 'fake_business_refresh',
    expiresAt: DateTime(2026, 5, 27, 12),
    user: user,
  );
}

class _FakeAuthService implements AuthService {
  _FakeAuthService(this.user);

  AuthUser? user;

  @override
  Future<Result<AuthSession>> businessLogin(
    String email,
    String password,
  ) async {
    final current = user;
    return current == null
        ? Result.fail('No fake business user.')
        : Result.ok(_session(current));
  }

  @override
  Future<Result<AuthSession>> businessRegister({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final newUser = _businessUser(completed: false, step: 1);
    user = newUser;
    return Result.ok(_session(newUser));
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
  Future<Result<AuthUser>> businessMe() async {
    final current = user;
    return current == null
        ? Result.fail('No fake business user.')
        : Result.ok(current);
  }

  @override
  Future<Result<void>> businessLogout() async {
    user = null;
    return Result.empty();
  }

  @override
  Future<Result<AuthUser>> getCurrentUser() => businessMe();

  @override
  Future<bool> isAuthenticated() async => user != null;

  @override
  Future<Result<AuthSession>> login(String email, String password) async =>
      Result.fail('Customer login is not used.');

  @override
  Future<Result<void>> logout() => businessLogout();

  @override
  Future<Result<AuthUser>> me() => businessMe();

  @override
  Future<Result<AuthSession>> refreshSessionMock() async =>
      Result.fail('Refresh is not used.');

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
  }) async => Result.fail('Customer register is not used.');

  @override
  Future<Result<void>> sendCustomerEmailOtp(
    String email,
    String purpose,
  ) async {
    return Result.fail('Customer OTP is not used.');
  }

  @override
  Future<Result<void>> verifyCustomerEmailOtp(
    String email,
    String code,
    String purpose,
  ) async {
    return Result.fail('Customer OTP is not used.');
  }

  @override
  Future<Result<void>> requestCustomerPasswordReset(String email) async {
    return Result.fail('Customer reset is not used.');
  }

  @override
  Future<Result<void>> confirmCustomerPasswordReset(
    String email,
    String code,
    String newPassword,
  ) async {
    return Result.fail('Customer reset is not used.');
  }

  @override
  Future<Result<AuthSession>> signInWithEmailMock(
    String email, {
    UserRole role = UserRole.customer,
  }) async => Result.fail('Mock sign-in is not used.');

  @override
  Future<Result<AuthSession>> signInWithPhoneMock(
    String phone, {
    UserRole role = UserRole.customer,
  }) async => Result.fail('Mock sign-in is not used.');

  @override
  Future<Result<void>> signOut() => businessLogout();
}

class _FakeBusinessRepository extends BusinessRepository {
  _FakeBusinessRepository();

  int? completedStep;
  int profileLoadCount = 0;
  int profileSaveCount = 0;

  @override
  Future<Map<String, dynamic>> getBusinessProfile() async {
    profileLoadCount += 1;
    return {'id': 1, 'name': 'Demo Salon'};
  }

  @override
  Future<Map<String, dynamic>> saveBusinessProfile(
    Map<String, dynamic> body,
  ) async {
    profileSaveCount += 1;
    return body;
  }

  @override
  Future<Map<String, dynamic>> markOnboardingComplete({int step = 7}) async {
    completedStep = step;
    return {'id': 1, 'onboarding_completed': true, 'onboarding_step': step};
  }
}

class _RecordingApiClient extends ApiClient {
  String? path;
  Map<String, Object?>? body;

  @override
  Future<Map<String, Object?>> postData(
    String path, {
    Map<String, Object?> body = const {},
  }) async {
    this.path = path;
    this.body = body;
    return {
      'business': {
        'id': 42,
        'onboarding_completed': true,
        'onboarding_step': body['step'],
      },
    };
  }
}

Widget _wrapBusiness(Widget child) {
  return MaterialApp(theme: WebeyTheme.business(), home: child);
}

void main() {
  installNoNetworkHttpOverrides();

  test('MobileAuthUser parses business onboarding fields', () {
    final user = MobileAuthUser.fromJson({
      'id': 'u1',
      'type': 'business',
      'business_onboarding_completed': '1',
      'admin_onboarding_completed': false,
      'onboarding_step': '7',
    }).toBeautyAuthUser();

    expect(user.businessOnboardingCompleted, isTrue);
    expect(user.adminOnboardingCompleted, isFalse);
    expect(user.onboardingStep, 7);
  });

  test('BusinessRepository posts onboarding completion step', () async {
    final client = _RecordingApiClient();
    final repository = BusinessRepository(apiClient: client);

    final business = await repository.markOnboardingComplete(step: 7);

    expect(client.path, '/business/onboarding-complete.php');
    expect(client.body, {'step': 7});
    expect(business['onboarding_completed'], isTrue);
    expect(business['onboarding_step'], 7);
  });

  testWidgets('businessMe completed=true opens business app', (tester) async {
    await tester.pumpWidget(
      _wrapBusiness(
        BusinessStartFlow(
          authService: _FakeAuthService(
            _businessUser(completed: true, step: 7),
          ),
          repository: _FakeBusinessRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(BusinessShell), findsOneWidget);
    expect(find.byType(BusinessOnboardingFlow), findsNothing);
  });

  testWidgets('businessMe completed=false opens onboarding', (tester) async {
    await tester.pumpWidget(
      _wrapBusiness(
        BusinessStartFlow(
          authService: _FakeAuthService(
            _businessUser(completed: false, step: 4),
          ),
          repository: _FakeBusinessRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(BusinessOnboardingFlow), findsOneWidget);
    expect(find.byType(BusinessShell), findsNothing);
  });

  testWidgets('onboarding without auth does not save profile', (tester) async {
    final repository = _FakeBusinessRepository();
    var loginTapped = false;

    await tester.pumpWidget(
      _wrapBusiness(
        BusinessOnboardingFlow(
          repository: repository,
          hasAuthenticatedSession: false,
          onComplete: () {},
          onLogin: () => loginTapped = true,
          onRegister: () {},
        ),
      ),
    );
    await tester.pump();

    expect(repository.profileLoadCount, 0);
    expect(
      find.text('Devam etmek için işletme hesabıyla giriş yap'),
      findsOneWidget,
    );

    await tester.tap(find.text('Kaydet ve devam'));
    await tester.pump();
    expect(repository.profileSaveCount, 0);

    await tester.tap(find.text('Giriş yap').last);
    await tester.pump();
    expect(loginTapped, isTrue);
  });

  testWidgets('business onboarding phone input is limited to 10 digits', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapBusiness(
        BusinessOnboardingFlow(
          repository: _FakeBusinessRepository(),
          onComplete: () {},
          onLogin: () {},
          onRegister: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(find.byType(TextFormField).at(2), '598765432101');
    await tester.pump();
    expect(find.text('5987654321'), findsOneWidget);
    expect(find.text('598765432101'), findsNothing);
  });
}
