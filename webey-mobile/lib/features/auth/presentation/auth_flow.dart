import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/webey_colors.dart';
import '../../../shared/services/auth_service.dart';
import '../../../shared/services/result.dart';
import '../../../shared/services/webey_location_service.dart';

enum _AuthScreen { welcome, login, registerEmail, otp, password, personal }

class AuthFlow extends StatefulWidget {
  const AuthFlow({
    super.key,
    required this.onAuthenticated,
    required this.onGuest,
    this.startWithRegister = false,
    this.contextNote,
    this.authService,
  });

  final VoidCallback onAuthenticated;
  final VoidCallback onGuest;
  final bool startWithRegister;
  final String? contextNote;
  final AuthService? authService;

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  late _AuthScreen _screen;
  String _email = '';
  String _password = '';
  bool _isSubmitting = false;
  bool _isSendingOtp = false;

  @override
  void initState() {
    super.initState();
    _screen = widget.startWithRegister
        ? _AuthScreen.registerEmail
        : _AuthScreen.welcome;
  }

  void _go(_AuthScreen screen) => setState(() => _screen = screen);

  AuthService get _authService =>
      widget.authService ?? WebeyAuthService.instance;

  Future<void> _login(String email, String password) async {
    await _runAuthAction(() {
      return _authService.login(email, password);
    });
  }

  Future<void> _sendRegistrationOtp(String email) async {
    final trimmed = email.trim();
    if (!_looksLikeEmail(trimmed)) {
      _showError('Geçerli bir e-posta adresi girin.');
      return;
    }
    if (_isSendingOtp) return;
    setState(() => _isSendingOtp = true);
    final result = await _authService.sendCustomerEmailOtp(trimmed, 'register');
    if (!mounted) return;
    setState(() => _isSendingOtp = false);
    if (result.success) {
      _email = trimmed;
      _go(_AuthScreen.otp);
      return;
    }
    _showError(_otpErrorMessage(result));
  }

  Future<Result<void>> _verifyRegistrationOtp(String code) {
    return _authService.verifyCustomerEmailOtp(_email, code, 'register');
  }

  Future<Result<void>> _requestPasswordReset(String email) {
    return _authService.requestCustomerPasswordReset(email);
  }

  Future<Result<void>> _confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  ) {
    return _authService.confirmCustomerPasswordReset(email, code, newPassword);
  }

  Future<void> _register({
    required String firstName,
    required String lastName,
    required String phone,
    String? city,
    String? district,
    String? neighborhood,
    String? addressLine,
    double? latitude,
    double? longitude,
  }) async {
    await _runAuthAction(() {
      return _authService.register(
        name: [
          firstName,
          lastName,
        ].where((part) => part.trim().isNotEmpty).join(' ').trim(),
        email: _email,
        phone: phone,
        password: _password,
        city: city,
        district: district,
        neighborhood: neighborhood,
        addressLine: addressLine,
        latitude: latitude,
        longitude: longitude,
      );
    });
  }

  Future<void> _runAuthAction(Future<Result<dynamic>> Function() action) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (result.success == true) {
      widget.onAuthenticated();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.errorMessage ?? 'Giriş yapılamadı.')),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _otpErrorMessage(Result<dynamic> result) {
    final message = result.errorMessage ?? '';
    final lower = message.toLowerCase();
    if (result.statusCode == 429) {
      return 'Çok sık kod istediniz. Lütfen biraz bekleyin.';
    }
    if (lower.contains('expired') || lower.contains('süresi')) {
      return 'Kodun süresi dolmuş. Yeni kod isteyin.';
    }
    if (lower.contains('hatal') || lower.contains('invalid')) {
      return 'Kod hatalı. Lütfen tekrar deneyin.';
    }
    if (lower.contains('gönder') || lower.contains('mail')) {
      return 'E-posta gönderilemedi. Lütfen tekrar deneyin.';
    }
    return message.isEmpty
        ? 'İşlem tamamlanamadı. Lütfen tekrar deneyin.'
        : message;
  }

  bool _looksLikeEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  void _back() {
    final previous = switch (_screen) {
      _AuthScreen.login => _AuthScreen.welcome,
      _AuthScreen.registerEmail => _AuthScreen.welcome,
      _AuthScreen.otp => _AuthScreen.registerEmail,
      _AuthScreen.password => _AuthScreen.otp,
      _AuthScreen.personal => _AuthScreen.password,
      _AuthScreen.welcome => null,
    };
    if (previous == null) {
      widget.onGuest();
      return;
    }
    setState(() => _screen = previous);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _screen == _AuthScreen.welcome
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: WebeyColors.ivory,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
          child: _buildScreen(),
        ),
      ),
    );
  }

  Widget _buildScreen() {
    return switch (_screen) {
      _AuthScreen.welcome => WelcomeScreen(
        key: const ValueKey('welcome'),
        contextNote: widget.contextNote,
        onLogin: () => _go(_AuthScreen.login),
        onRegister: () => _go(_AuthScreen.registerEmail),
        onGuest: widget.onGuest,
      ),
      _AuthScreen.login => LoginScreen(
        key: const ValueKey('login'),
        onBack: _back,
        onLogin: _login,
        onRegister: () => _go(_AuthScreen.registerEmail),
        onPasswordResetRequest: _requestPasswordReset,
        onPasswordResetConfirm: _confirmPasswordReset,
        isLoading: _isSubmitting,
      ),
      _AuthScreen.registerEmail => RegisterEmailScreen(
        key: const ValueKey('register-email'),
        onBack: _back,
        onLogin: () => _go(_AuthScreen.login),
        onNext: _sendRegistrationOtp,
        isLoading: _isSendingOtp,
      ),
      _AuthScreen.otp => OtpScreen(
        key: const ValueKey('otp'),
        email: _email,
        onBack: _back,
        onChangeEmail: () => _go(_AuthScreen.registerEmail),
        onVerified: () => _go(_AuthScreen.password),
        onVerify: _verifyRegistrationOtp,
        onResend: () => _authService.sendCustomerEmailOtp(_email, 'register'),
      ),
      _AuthScreen.password => PasswordScreen(
        key: const ValueKey('password'),
        onBack: _back,
        onNext: (password) {
          _password = password;
          _go(_AuthScreen.personal);
        },
      ),
      _AuthScreen.personal => PersonalInfoScreen(
        key: const ValueKey('personal'),
        onBack: _back,
        onComplete: _register,
        isLoading: _isSubmitting,
      ),
    };
  }
}

class _AuthHeader extends StatelessWidget {
  const _AuthHeader({
    required this.titleBold,
    required this.titleItalic,
    required this.subtitle,
    required this.onBack,
    this.step,
    this.totalSteps,
    this.progress,
  });

  final String titleBold;
  final String titleItalic;
  final String subtitle;
  final VoidCallback onBack;
  final int? step;
  final int? totalSteps;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: WebeyColors.warmCream,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: const Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: WebeyColors.darkEspresso,
                  ),
                ),
              ),
              const Spacer(),
              if (step != null && totalSteps != null)
                Text(
                  'Adım $step / $totalSteps',
                  style: const TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
        if (progress != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress! / 100,
                backgroundColor: WebeyColors.borderSand,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  WebeyColors.primaryGold,
                ),
                minHeight: 3,
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 24,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
              children: [
                TextSpan(text: titleBold),
                if (titleItalic.isNotEmpty)
                  TextSpan(
                    text: ' $titleItalic',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            subtitle,
            style: const TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.label,
    this.hint,
    this.controller,
    this.prefixIcon,
    this.suffixWidget,
    this.isPassword = false,
    this.keyboardType,
    this.isFocused = false,
    this.isValid,
    this.helperText,
    this.onChanged,
  });

  final String label;
  final String? hint;
  final String? helperText;
  final TextEditingController? controller;
  final IconData? prefixIcon;
  final Widget? suffixWidget;
  final bool isPassword;
  final bool isFocused;
  final bool? isValid;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            if (isValid == true) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.check_rounded,
                size: 10,
                color: WebeyColors.successGreen,
              ),
              const SizedBox(width: 3),
              const Text(
                'GEÇERLİ',
                style: TextStyle(
                  color: WebeyColors.successGreen,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: WebeyColors.softWhite,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: isFocused
                  ? WebeyColors.primaryGold
                  : isValid == false
                  ? WebeyColors.errorRed.withAlpha(150)
                  : WebeyColors.borderSand,
              width: isFocused ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              if (prefixIcon != null) ...[
                Icon(prefixIcon, size: 16, color: WebeyColors.mutedTaupe),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: isPassword,
                  keyboardType: keyboardType,
                  onChanged: onChanged,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 13.5,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (suffixWidget != null) ...[
                suffixWidget!,
                const SizedBox(width: 12),
              ],
            ],
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 5),
          Text(
            helperText!,
            style: const TextStyle(color: WebeyColors.mutedTaupe, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _GoldButton extends StatelessWidget {
  const _GoldButton({required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: WebeyColors.primaryGold,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: WebeyColors.darkEspresso),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: WebeyColors.darkEspresso,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: WebeyColors.goldLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.shield_outlined,
              size: 15,
              color: WebeyColors.primaryGold,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onLogin,
    required this.onRegister,
    required this.onGuest,
    this.contextNote,
  });

  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final VoidCallback onGuest;
  final String? contextNote;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.darkEspresso,
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF3A261A), Color(0xFF1A0E05)],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'EDITORIAL · BEAUTY',
                        style: TextStyle(
                          color: Colors.white.withAlpha(28),
                          fontSize: 10,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 60,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontFamily: 'Georgia',
                            fontWeight: FontWeight.w600,
                          ),
                          children: [
                            TextSpan(text: 'Webey '),
                            TextSpan(
                              text: 'Beauty',
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Color(0xFFD4B574),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'PREMIUM GÜZELLİK RANDEVULARI',
                        style: TextStyle(
                          color: Colors.white.withAlpha(130),
                          fontSize: 9,
                          letterSpacing: 2.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 16,
                  left: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withAlpha(30)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 11,
                          color: Colors.white.withAlpha(180),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Premium salonlar · Güvenli randevu',
                          style: TextStyle(
                            color: Colors.white.withAlpha(180),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 6,
            child: Container(
              color: WebeyColors.ivory,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'HOŞ GELDİNİZ',
                                  style: TextStyle(
                                    color: WebeyColors.primaryGold,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                RichText(
                                  text: const TextSpan(
                                    style: TextStyle(
                                      color: WebeyColors.darkEspresso,
                                      fontSize: 22,
                                      fontFamily: 'Georgia',
                                      fontWeight: FontWeight.w600,
                                      height: 1.25,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: 'Güzellik randevularınızı ',
                                      ),
                                      TextSpan(
                                        text: 'zahmetsizce',
                                        style: TextStyle(
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                      TextSpan(text: ' planlayın.'),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  contextNote ??
                                      'Yakınınızdaki premium salonları keşfedin, kaporalı veya kaporasız seçeneklerle güvenle randevu alın.',
                                  style: const TextStyle(
                                    color: WebeyColors.mutedTaupe,
                                    fontSize: 12.5,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _GoldButton(
                                  label: 'E-posta ile Giriş Yap',
                                  icon: Icons.mail_outline_rounded,
                                  onTap: onLogin,
                                ),
                                const SizedBox(height: 10),
                                _OutlineAction(
                                  label: 'Hesap Oluştur',
                                  onTap: onRegister,
                                ),
                                const SizedBox(height: 12),
                                Center(
                                  child: GestureDetector(
                                    onTap: onGuest,
                                    child: const Text(
                                      'Misafir olarak keşfet',
                                      style: TextStyle(
                                        color: WebeyColors.primaryGold,
                                        fontSize: 13,
                                        decoration: TextDecoration.underline,
                                        decorationColor:
                                            WebeyColors.primaryGold,
                                      ),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Center(
                                  child: Text(
                                    'Devam ederek Kullanım Şartları ve Gizlilik Politikası’nı kabul etmiş olursunuz.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: WebeyColors.mutedTaupe,
                                      fontSize: 10.5,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onBack,
    required this.onLogin,
    required this.onRegister,
    required this.onPasswordResetRequest,
    required this.onPasswordResetConfirm,
    this.isLoading = false,
  });

  final VoidCallback onBack;
  final void Function(String email, String password) onLogin;
  final VoidCallback onRegister;
  final Future<Result<void>> Function(String email) onPasswordResetRequest;
  final Future<Result<void>> Function(
    String email,
    String code,
    String newPassword,
  )
  onPasswordResetConfirm;
  final bool isLoading;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _remember = true;

  Future<void> _showForgotPassword() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WebeyColors.ivory,
      builder: (context) => _PasswordResetSheet(
        initialEmail: _emailController.text.trim(),
        onRequest: widget.onPasswordResetRequest,
        onConfirm: widget.onPasswordResetConfirm,
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      children: [
        _AuthHeader(
          titleBold: 'Giriş',
          titleItalic: 'Yap',
          subtitle: 'Webey Beauty hesabınıza devam edin.',
          onBack: widget.onBack,
        ),
        _FormCard(
          children: [
            _InputField(
              label: 'E-POSTA',
              controller: _emailController,
              prefixIcon: Icons.mail_outline_rounded,
              isFocused: true,
              isValid: true,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 14),
            _InputField(
              label: 'ŞİFRE',
              controller: _passwordController,
              prefixIcon: Icons.lock_outline_rounded,
              isPassword: !_showPassword,
              suffixWidget: GestureDetector(
                onTap: () => setState(() => _showPassword = !_showPassword),
                child: Icon(
                  _showPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 16,
                  color: WebeyColors.mutedTaupe,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _remember = !_remember),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: _remember
                              ? WebeyColors.primaryGold
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _remember
                                ? WebeyColors.primaryGold
                                : WebeyColors.borderSand,
                          ),
                        ),
                        child: _remember
                            ? const Icon(
                                Icons.check_rounded,
                                size: 12,
                                color: WebeyColors.darkEspresso,
                              )
                            : null,
                      ),
                      const SizedBox(width: 7),
                      const Text(
                        'Beni hatırla',
                        style: TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _showForgotPassword,
                  child: const Text(
                    'Şifremi unuttum',
                    style: TextStyle(
                      color: WebeyColors.primaryGold,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _GoldButton(
              label: 'Giriş Yap',
              onTap: widget.isLoading
                  ? () {}
                  : () => widget.onLogin(
                      _emailController.text.trim(),
                      _passwordController.text,
                    ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Center(
          child: GestureDetector(
            onTap: widget.onRegister,
            child: const Text(
              'Hesabınız yok mu? Hesap oluşturun',
              style: TextStyle(
                color: WebeyColors.primaryGold,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: WebeyColors.primaryGold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _TrustBadge(
          title: 'Webey Güvencesi',
          subtitle:
              'Randevu, kapora ve favori salon bilgileriniz güvenle saklanır.',
        ),
      ],
    );
  }
}

class _PasswordResetSheet extends StatefulWidget {
  const _PasswordResetSheet({
    required this.initialEmail,
    required this.onRequest,
    required this.onConfirm,
  });

  final String initialEmail;
  final Future<Result<void>> Function(String email) onRequest;
  final Future<Result<void>> Function(
    String email,
    String code,
    String newPassword,
  )
  onConfirm;

  @override
  State<_PasswordResetSheet> createState() => _PasswordResetSheetState();
}

class _PasswordResetSheetState extends State<_PasswordResetSheet> {
  late final TextEditingController _emailController;
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Geçerli bir e-posta adresi girin.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.onRequest(email);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _codeSent = result.success;
      _error = result.success
          ? null
          : (result.errorMessage ??
                'E-posta gönderilemedi. Lütfen tekrar deneyin.');
    });
  }

  Future<void> _confirm() async {
    final password = _passwordController.text;
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Kod hatalı. Lütfen tekrar deneyin.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Şifre en az 8 karakter olmalı.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.onConfirm(
      _emailController.text.trim(),
      code,
      password,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Şifreniz güncellendi. Yeni şifrenizle giriş yapabilirsiniz.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _error = result.statusCode == 429
          ? 'Çok sık kod istediniz. Lütfen biraz bekleyin.'
          : (result.errorMessage ?? 'Kod hatalı. Lütfen tekrar deneyin.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Şifre sıfırla',
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 20,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _InputField(
            label: 'E-POSTA',
            controller: _emailController,
            prefixIcon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          if (_codeSent) ...[
            const SizedBox(height: 12),
            _InputField(
              label: 'DOĞRULAMA KODU',
              hint: '6 haneli kod',
              controller: _codeController,
              keyboardType: TextInputType.number,
              prefixIcon: Icons.password_rounded,
              helperText: 'Kod 10 dakika geçerlidir.',
            ),
            const SizedBox(height: 12),
            _InputField(
              label: 'YENİ ŞİFRE',
              controller: _passwordController,
              isPassword: true,
              prefixIcon: Icons.lock_outline_rounded,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: WebeyColors.errorRed, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          _GoldButton(
            label: _loading
                ? 'Lütfen bekleyin...'
                : _codeSent
                ? 'Şifreyi güncelle'
                : 'Kodu gönder',
            onTap: _loading ? () {} : (_codeSent ? _confirm : _request),
          ),
        ],
      ),
    );
  }
}

class RegisterEmailScreen extends StatefulWidget {
  const RegisterEmailScreen({
    super.key,
    required this.onBack,
    required this.onNext,
    required this.onLogin,
    this.isLoading = false,
  });

  final VoidCallback onBack;
  final ValueChanged<String> onNext;
  final VoidCallback onLogin;
  final bool isLoading;

  @override
  State<RegisterEmailScreen> createState() => _RegisterEmailScreenState();
}

class _RegisterEmailScreenState extends State<RegisterEmailScreen> {
  final _emailController = TextEditingController();
  bool _isValid = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool _validateEmail(String value) {
    return RegExp(r'^[\w.+-]+@[\w.-]+\.\w+$').hasMatch(value);
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      children: [
        _AuthHeader(
          titleBold: 'Webey Beauty’ye',
          titleItalic: 'katılın.',
          subtitle: 'Premium salonları keşfetmek için hesabınızı oluşturun.',
          onBack: widget.onBack,
          step: 1,
          totalSteps: 4,
          progress: 25,
        ),
        _FormCard(
          children: [
            _InputField(
              label: 'E-POSTA ADRESİ',
              hint: 'ornek@email.com',
              controller: _emailController,
              prefixIcon: Icons.mail_outline_rounded,
              isFocused: true,
              isValid: _isValid ? true : null,
              keyboardType: TextInputType.emailAddress,
              helperText: 'Bu adresi giriş yaparken kullanacaksınız.',
              onChanged: (value) {
                setState(() => _isValid = _validateEmail(value));
              },
            ),
          ],
        ),
        const _InfoNote(
          text:
              'E-posta adresinize 6 haneli doğrulama kodu göndereceğiz. Spam klasörünüzü de kontrol etmeyi unutmayın.',
        ),
        _GoldButton(
          label: widget.isLoading
              ? 'Kod gönderiliyor...'
              : 'Doğrulama Kodu Gönder',
          onTap: widget.isLoading
              ? () {}
              : () => widget.onNext(_emailController.text.trim()),
        ),
        const SizedBox(height: 14),
        Center(
          child: GestureDetector(
            onTap: widget.onLogin,
            child: const Text(
              'Zaten hesabınız var mı? Giriş yap',
              style: TextStyle(
                color: WebeyColors.primaryGold,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: WebeyColors.primaryGold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.email,
    required this.onBack,
    required this.onVerified,
    required this.onChangeEmail,
    required this.onVerify,
    required this.onResend,
  });

  final String email;
  final VoidCallback onBack;
  final VoidCallback onVerified;
  final VoidCallback onChangeEmail;
  final Future<Result<void>> Function(String code) onVerify;
  final Future<Result<void>> Function() onResend;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _codeController = TextEditingController();
  Timer? _timer;
  bool _isSubmitting = false;
  bool _isResending = false;
  String? _error;
  int _cooldown = 60;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
        return;
      }
      setState(() => _cooldown -= 1);
    });
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Kod hatalı. Lütfen tekrar deneyin.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final result = await widget.onVerify(code);
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (result.success) {
      widget.onVerified();
      return;
    }
    setState(() => _error = _otpMessage(result));
  }

  Future<void> _resend() async {
    if (_cooldown > 0 || _isResending) return;
    setState(() {
      _isResending = true;
      _error = null;
    });
    final result = await widget.onResend();
    if (!mounted) return;
    setState(() => _isResending = false);
    if (result.success) {
      _startCooldown();
      return;
    }
    setState(() => _error = _otpMessage(result));
  }

  String _otpMessage(Result<void> result) {
    final message = result.errorMessage ?? '';
    final lower = message.toLowerCase();
    if (result.statusCode == 429) {
      return 'Çok sık kod istediniz. Lütfen biraz bekleyin.';
    }
    if (lower.contains('expired') || lower.contains('süresi')) {
      return 'Kodun süresi dolmuş. Yeni kod isteyin.';
    }
    if (lower.contains('hatal') || lower.contains('invalid')) {
      return 'Kod hatalı. Lütfen tekrar deneyin.';
    }
    if (lower.contains('gönder') || lower.contains('mail')) {
      return 'E-posta gönderilemedi. Lütfen tekrar deneyin.';
    }
    return message.isEmpty ? 'Kod hatalı. Lütfen tekrar deneyin.' : message;
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      children: [
        _AuthHeader(
          titleBold: 'E-postanızı',
          titleItalic: 'doğrulayın.',
          subtitle: 'E-posta adresinize gönderilen 6 haneli kodu girin.',
          onBack: widget.onBack,
          step: 2,
          totalSteps: 4,
          progress: 50,
        ),
        _EmailChangeCard(email: widget.email, onTap: widget.onChangeEmail),
        const SizedBox(height: 20),
        _InputField(
          label: 'DOĞRULAMA KODU',
          hint: '6 haneli kod',
          controller: _codeController,
          prefixIcon: Icons.password_rounded,
          keyboardType: TextInputType.number,
          helperText: 'Kod 10 dakika geçerlidir.',
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(color: WebeyColors.errorRed, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              _cooldown > 0
                  ? 'Kodu tekrar gönder: ${_cooldown}s'
                  : 'Kodu tekrar gönderebilirsiniz.',
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 12.5,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: (_cooldown > 0 || _isResending) ? null : _resend,
              child: Text(
                _isResending ? 'Gönderiliyor...' : 'Kodu tekrar gönder',
              ),
            ),
          ],
        ),
        _GoldButton(
          label: _isSubmitting ? 'Doğrulanıyor...' : 'Doğrula',
          onTap: _isSubmitting ? () {} : _verify,
        ),
        const SizedBox(height: 14),
        const _TrustBadge(
          title: 'Tek seferlik kod',
          subtitle:
              'Bu kod 10 dakika geçerlidir ve kimseyle paylaşılmamalıdır.',
        ),
      ],
    );
  }
}

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key, required this.onBack, required this.onNext});

  final VoidCallback onBack;
  final ValueChanged<String> onNext;

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _showPassword = false;
  bool _showConfirm = false;

  int get _strength {
    final value = _passwordController.text;
    var score = 0;
    if (value.length >= 6) score++;
    if (value.contains(RegExp(r'[A-Z]'))) score++;
    if (value.contains(RegExp(r'[0-9]'))) score++;
    return score;
  }

  bool get _lengthOk => _passwordController.text.length >= 6;
  bool get _matchOk =>
      _passwordController.text == _confirmController.text &&
      _passwordController.text.isNotEmpty;
  bool get _hasUpperAndNumber =>
      _passwordController.text.contains(RegExp(r'[A-Z]')) &&
      _passwordController.text.contains(RegExp(r'[0-9]'));

  Color get _strengthColor {
    if (_strength <= 1) return WebeyColors.errorRed;
    if (_strength == 2) return WebeyColors.warning;
    return WebeyColors.successGreen;
  }

  String get _strengthLabel {
    if (_strength <= 1) return 'Zayıf';
    if (_strength == 2) return 'Orta';
    return 'Güçlü';
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      children: [
        _AuthHeader(
          titleBold: 'Şifre',
          titleItalic: 'oluşturun.',
          subtitle: 'Hesabınızı korumak için güvenli bir şifre belirleyin.',
          onBack: widget.onBack,
          step: 3,
          totalSteps: 4,
          progress: 75,
        ),
        _FormCard(
          children: [
            _InputField(
              label: 'ŞİFRE',
              controller: _passwordController,
              prefixIcon: Icons.lock_outline_rounded,
              isPassword: !_showPassword,
              isFocused: true,
              onChanged: (_) => setState(() {}),
              suffixWidget: GestureDetector(
                onTap: () => setState(() => _showPassword = !_showPassword),
                child: Icon(
                  _showPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 16,
                  color: WebeyColors.mutedTaupe,
                ),
              ),
            ),
            if (_passwordController.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: List.generate(3, (index) {
                        return Expanded(
                          child: Container(
                            height: 4,
                            margin: EdgeInsets.only(right: index < 2 ? 4 : 0),
                            decoration: BoxDecoration(
                              color: index < _strength
                                  ? _strengthColor
                                  : WebeyColors.borderSand,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _strengthLabel,
                    style: TextStyle(
                      color: _strengthColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            _InputField(
              label: 'ŞİFRE TEKRAR',
              controller: _confirmController,
              prefixIcon: Icons.lock_outline_rounded,
              isPassword: !_showConfirm,
              onChanged: (_) => setState(() {}),
              suffixWidget: GestureDetector(
                onTap: () => setState(() => _showConfirm = !_showConfirm),
                child: Icon(
                  _showConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 16,
                  color: WebeyColors.mutedTaupe,
                ),
              ),
            ),
          ],
        ),
        _PasswordCheck(ok: _lengthOk, label: 'En az 6 karakter'),
        const SizedBox(height: 6),
        _PasswordCheck(ok: _matchOk, label: 'Şifreler eşleşmeli'),
        const SizedBox(height: 6),
        _PasswordCheck(
          ok: _hasUpperAndNumber,
          label: 'En az 1 büyük harf ve sayı önerilir',
        ),
        const SizedBox(height: 14),
        _GoldButton(
          label: 'Devam Et',
          onTap: () => widget.onNext(_passwordController.text),
        ),
        const SizedBox(height: 14),
        const _TrustBadge(
          title: 'Şifreniz güvende',
          subtitle:
              'Şifreniz şifrelenmiş olarak saklanır, kimse görüntüleyemez.',
        ),
      ],
    );
  }
}

class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({
    super.key,
    required this.onBack,
    required this.onComplete,
    this.isLoading = false,
  });

  final VoidCallback onBack;
  final void Function({
    required String firstName,
    required String lastName,
    required String phone,
    String? city,
    String? district,
    String? neighborhood,
    String? addressLine,
    double? latitude,
    double? longitude,
  })
  onComplete;
  final bool isLoading;

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _districtController = TextEditingController();
  final _neighbourhoodController = TextEditingController();
  final _addressController = TextEditingController();
  String _city = '';
  double? _latitude;
  double? _longitude;
  bool _locationBusy = false;
  String? _locationMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _districtController.dispose();
    _neighbourhoodController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    if (_locationBusy) return;
    setState(() {
      _locationBusy = true;
      _locationMessage = 'Konumunuz alınıyor...';
    });
    try {
      final location = await WebeyLocationService.instance.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _city = location.city ?? _city;
        _districtController.text =
            location.district ?? _districtController.text;
        _neighbourhoodController.text =
            location.neighborhood ?? _neighbourhoodController.text;
        _addressController.text =
            location.addressLine ?? _addressController.text;
        _latitude = location.latitude;
        _longitude = location.longitude;
        _locationMessage = 'Konumunuz bulundu';
      });
    } on WebeyLocationException catch (error) {
      if (!mounted) return;
      setState(() => _locationMessage = error.message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      const message = 'Konum alınamadı. Bilgileri manuel girebilirsiniz.';
      setState(() => _locationMessage = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      children: [
        _AuthHeader(
          titleBold: 'Kişisel',
          titleItalic: 'bilgiler.',
          subtitle:
              'Size en yakın salonları önerebilmemiz için birkaç bilgi yeterli.',
          onBack: widget.onBack,
          step: 4,
          totalSteps: 4,
          progress: 100,
        ),
        _FormCard(
          children: [
            const Text(
              'Konumunuzu ekleyin',
              style: TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Size yakın salonları gösterebilmemiz için şehir ve ilçe bilginizi ekleyin.',
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _locationBusy ? null : _useCurrentLocation,
              icon: _locationBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded, size: 18),
              label: Text(
                _locationBusy ? 'Konumunuz alınıyor...' : 'Konumumu Kullan',
              ),
            ),
            if (_locationMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _locationMessage!,
                style: const TextStyle(
                  color: WebeyColors.mutedTaupe,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _InputField(
                    label: 'AD',
                    controller: _firstNameController,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InputField(
                    label: 'SOYAD',
                    controller: _lastNameController,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _PhoneField(controller: _phoneController),
            const SizedBox(height: 14),
            _SelectField(
              label: 'İL',
              value: _city,
              placeholder: 'Şehir seçin',
              icon: Icons.location_on_outlined,
              onTap: () async {
                final picked = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const _CityPickerSheet(),
                );
                if (picked != null) setState(() => _city = picked);
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _InputField(
                    label: 'İLÇE',
                    controller: _districtController,
                    hint: 'Kadıköy',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InputField(
                    label: 'MAHALLE',
                    controller: _neighbourhoodController,
                    hint: 'Moda',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _InputField(
              label: 'AÇIK ADRES',
              controller: _addressController,
              hint: 'Opsiyonel',
            ),
          ],
        ),
        const _InfoNote(
          text:
              'Konum bilgileriniz yalnızca size yakın salonları göstermek için kullanılır. Adresiniz salonlarla paylaşılmaz.',
        ),
        _GoldButton(
          label: 'Hesabımı Oluştur',
          icon: Icons.check_rounded,
          onTap: widget.isLoading
              ? () {}
              : () => widget.onComplete(
                  firstName: _firstNameController.text.trim(),
                  lastName: _lastNameController.text.trim(),
                  phone: _phoneController.text.trim(),
                  city: _city.trim().isEmpty ? null : _city.trim(),
                  district: _districtController.text.trim(),
                  neighborhood: _neighbourhoodController.text.trim(),
                  addressLine: _addressController.text.trim(),
                  latitude: _latitude,
                  longitude: _longitude,
                ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: WebeyColors.successGreen.withAlpha(15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: WebeyColors.successGreen.withAlpha(50)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: WebeyColors.successGreen,
                child: Icon(Icons.check_rounded, size: 14, color: Colors.white),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Son adım. Hesabınız oluşturulduktan sonra favori salonlarınızı kaydetmeye başlayabilirsiniz.',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverList.list(
              children: [
                ...children.map(
                  (child) => Padding(
                    padding: child is _AuthHeader
                        ? EdgeInsets.zero
                        : const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: child,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(children: children),
    );
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebeyColors.goldLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: WebeyColors.primaryGold,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailChangeCard extends StatelessWidget {
  const _EmailChangeCard({required this.email, required this.onTap});

  final String email;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.mail_outline_rounded,
            size: 15,
            color: WebeyColors.mutedTaupe,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              email,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 13.5,
              ),
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: const Text(
              'Değiştir',
              style: TextStyle(
                color: WebeyColors.primaryGold,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordCheck extends StatelessWidget {
  const _PasswordCheck({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ok ? WebeyColors.successGreen : Colors.transparent,
            border: Border.all(
              color: ok ? WebeyColors.successGreen : WebeyColors.borderSand,
            ),
          ),
          child: ok
              ? const Icon(Icons.check_rounded, size: 11, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: ok ? WebeyColors.successGreen : WebeyColors.mutedTaupe,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TELEFON NUMARASI',
          style: TextStyle(
            color: WebeyColors.mutedTaupe,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: WebeyColors.softWhite,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: WebeyColors.borderSand),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '+90',
                  style: TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Container(width: 1, height: 24, color: WebeyColors.borderSand),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      isDense: true,
                      hintText: '5XX XXX XX XX',
                      hintStyle: TextStyle(
                        color: WebeyColors.mutedTaupe.withAlpha(140),
                        fontSize: 14,
                      ),
                      counterText: '',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element
const _kTurkishCities = [
  'Adana',
  'Adıyaman',
  'Afyonkarahisar',
  'Ağrı',
  'Amasya',
  'Ankara',
  'Antalya',
  'Artvin',
  'Aydın',
  'Balıkesir',
  'Bilecik',
  'Bingöl',
  'Bitlis',
  'Bolu',
  'Burdur',
  'Bursa',
  'Çanakkale',
  'Çankırı',
  'Çorum',
  'Denizli',
  'Diyarbakır',
  'Edirne',
  'Elazığ',
  'Erzincan',
  'Erzurum',
  'Eskişehir',
  'Gaziantep',
  'Giresun',
  'Gümüşhane',
  'Hakkari',
  'Hatay',
  'Isparta',
  'Mersin',
  'İstanbul',
  'İzmir',
  'Kars',
  'Kastamonu',
  'Kayseri',
  'Kırklareli',
  'Kırşehir',
  'Kocaeli',
  'Konya',
  'Kütahya',
  'Malatya',
  'Manisa',
  'Kahramanmaraş',
  'Mardin',
  'Muğla',
  'Muş',
  'Nevşehir',
  'Niğde',
  'Ordu',
  'Rize',
  'Sakarya',
  'Samsun',
  'Siirt',
  'Sinop',
  'Sivas',
  'Tekirdağ',
  'Tokat',
  'Trabzon',
  'Tunceli',
  'Şanlıurfa',
  'Uşak',
  'Van',
  'Yozgat',
  'Zonguldak',
  'Aksaray',
  'Bayburt',
  'Karaman',
  'Kırıkkale',
  'Batman',
  'Şırnak',
  'Bartın',
  'Ardahan',
  'Iğdır',
  'Yalova',
  'Karabük',
  'Kilis',
  'Osmaniye',
  'Düzce',
];

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet();

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final _searchController = TextEditingController();
  List<String> _filtered = _kTurkishCities;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    setState(() {
      _filtered = query.isEmpty
          ? _kTurkishCities
          : _kTurkishCities
                .where((c) => c.toLowerCase().contains(query.toLowerCase()))
                .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: WebeyColors.ivory,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: WebeyColors.borderSand,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'İl Seçin',
                style: TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 16,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    hintText: 'Ara...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: WebeyColors.warmCream,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: WebeyColors.borderSand,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: WebeyColors.borderSand,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _filtered.length,
                  itemBuilder: (context, i) {
                    final city = _filtered[i];
                    return ListTile(
                      title: Text(
                        city,
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(city),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
    this.placeholder,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final IconData? icon;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final isEmpty = value.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: WebeyColors.mutedTaupe,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: WebeyColors.softWhite,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: WebeyColors.borderSand),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: WebeyColors.mutedTaupe),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    isEmpty ? (placeholder ?? '') : value,
                    style: TextStyle(
                      color: isEmpty
                          ? WebeyColors.mutedTaupe.withAlpha(140)
                          : WebeyColors.darkEspresso,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: WebeyColors.mutedTaupe,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
