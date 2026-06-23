// lib/features/business/business_start_flow.dart
// Yeni business UI'ya gecis katmani.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/webey_colors.dart';
import '../../shared/models/beauty_models.dart';
import '../../shared/services/auth_service.dart';
import '../../shared/services/business_fcm_service.dart';
import '../../shared/services/result.dart';
import '../../shared/widgets/webey_back_handler.dart';
import '../splash/splash_and_legal_screens.dart';
import 'data/repositories/business_repository.dart';
import 'presentation/business_onboarding_flow.dart';
import 'presentation/business_start_flow.dart';

export 'presentation/business_start_flow.dart';
export 'presentation/business_gallery_screen.dart';
export 'presentation/business_management_screens.dart';

enum _BizStage { splash, onboarding, login, register, app }

class BusinessStartFlow extends StatefulWidget {
  const BusinessStartFlow({super.key, this.authService, this.repository});

  final AuthService? authService;
  final BusinessRepository? repository;

  @override
  State<BusinessStartFlow> createState() => _BusinessStartFlowState();
}

class _BusinessStartFlowState extends State<BusinessStartFlow> {
  _BizStage _stage = _BizStage.splash;

  @override
  void initState() {
    super.initState();
    _bootstrapAuth();
    // Delay kaldırıldı: splash ekranı buton bekliyor
  }

  Future<void> _bootstrapAuth() async {
    final result = await _authService.businessMe();
    if (!mounted || !result.success) return;
    await BusinessFcmService.instance.registerCurrentToken(
      reason: 'businessMe',
    );
    if (!mounted) return;
    setState(() => _stage = _stageForBusinessUser(result.data));
  }

  Future<void> _markBusinessSessionReady(
    String reason, {
    AuthUser? user,
  }) async {
    await BusinessFcmService.instance.registerCurrentToken(reason: reason);
    if (!mounted) return;
    setState(() => _stage = _stageForBusinessUser(user));
  }

  Future<void> _markBusinessRegistered() async {
    await BusinessFcmService.instance.registerCurrentToken(
      reason: 'businessRegister',
    );
    if (!mounted) return;
    setState(() => _stage = _BizStage.onboarding);
  }

  Future<void> _logout() async {
    await _authService.businessLogout();
    if (!mounted) return;
    setState(() => _stage = _BizStage.splash);
  }

  AuthService get _authService =>
      widget.authService ?? WebeyAuthService.instance;

  BusinessRepository get _repository =>
      widget.repository ?? BusinessRepository.instance;

  _BizStage _stageForBusinessUser(AuthUser? user) {
    if (user?.businessOnboardingCompleted == false) {
      return _BizStage.onboarding;
    }
    return _BizStage.app;
  }

  @override
  Widget build(BuildContext context) {
    // Sistem geri tuşu: root route hiçbir zaman direkt pop olmaz;
    // interceptor'lar (login/register → splash, shell tab, onboarding adımı)
    // tüketmezse çıkış onayı gösterilir.
    return WebeyExitGuard(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: switch (_stage) {
          _BizStage.splash => BusinessSplashScreen(
            key: const ValueKey('splash'),
            onRegister: () => setState(() => _stage = _BizStage.register),
            onLogin: () => setState(() => _stage = _BizStage.login),
          ),
          _BizStage.onboarding => BusinessOnboardingFlow(
            key: const ValueKey('onboarding'),
            repository: _repository,
            hasAuthenticatedSession: true,
            onComplete: () => _markBusinessSessionReady('onboardingComplete'),
            onLogin: () => setState(() => _stage = _BizStage.login),
            onRegister: () => setState(() => _stage = _BizStage.register),
          ),
          _BizStage.login => _BusinessLoginScreen(
            key: const ValueKey('login'),
            authService: _authService,
            onLogin: (user) =>
                _markBusinessSessionReady('businessLogin', user: user),
            onRegister: () => setState(() => _stage = _BizStage.register),
            onBack: () => setState(() => _stage = _BizStage.splash),
          ),
          _BizStage.register => _BusinessRegisterScreen(
            key: const ValueKey('register'),
            authService: _authService,
            onRegistered: _markBusinessRegistered,
            onLogin: () => setState(() => _stage = _BizStage.login),
            onBack: () => setState(() => _stage = _BizStage.splash),
          ),
          _BizStage.app => BusinessShell(
            key: const ValueKey('shell'),
            onLogout: _logout,
          ),
        },
      ),
    );
  }
}

class _BusinessLoginScreen extends StatefulWidget {
  const _BusinessLoginScreen({
    super.key,
    required this.authService,
    required this.onLogin,
    required this.onRegister,
    required this.onBack,
  });

  final AuthService authService;
  final ValueChanged<AuthUser?> onLogin;
  final VoidCallback onRegister;
  final VoidCallback onBack;

  @override
  State<_BusinessLoginScreen> createState() => _BusinessLoginScreenState();
}

class _BusinessLoginScreenState extends State<_BusinessLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _showPass = false;
  bool _loading = false;
  WebeyBackRegistration? _backRegistration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sistem geri tuşu: uygulamadan çıkmak yerine splash'e dön.
    _backRegistration ??= WebeyBackScope.register(context, () {
      widget.onBack();
      return true;
    });
  }

  @override
  void dispose() {
    _backRegistration?.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() => _loading = true);
    final result = await widget.authService.businessLogin(
      _emailCtrl.text.trim(),
      _passCtrl.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.success) {
      widget.onLogin(result.data?.user);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.errorMessage ?? 'E-posta veya şifre hatalı.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: widget.onBack,
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
              const SizedBox(height: 20),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 24,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    TextSpan(text: 'İşletme '),
                    TextSpan(
                      text: 'Girişi',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Webey İşletme hesabınıza devam edin.',
                style: TextStyle(
                  color: WebeyColors.mutedTaupe,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: WebeyColors.softWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: WebeyColors.borderSand),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'E-POSTA',
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
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: WebeyColors.ivory,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 14,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'ŞİFRE',
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
                        color: WebeyColors.ivory,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: _passCtrl,
                              obscureText: !_showPass,
                              style: const TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 14,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _showPass = !_showPass),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Icon(
                                _showPass
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 16,
                                color: WebeyColors.mutedTaupe,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _loading ? null : _submit,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: WebeyColors.primaryGold,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: WebeyColors.darkEspresso,
                            ),
                          )
                        : const Text(
                            'Giriş Yap',
                            style: TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : widget.onRegister,
                  child: const Text('Hesabın yok mu? Hesap oluştur'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessRegisterScreen extends StatefulWidget {
  const _BusinessRegisterScreen({
    super.key,
    required this.authService,
    required this.onRegistered,
    required this.onLogin,
    required this.onBack,
  });

  final AuthService authService;
  final VoidCallback onRegistered;
  final VoidCallback onLogin;
  final VoidCallback onBack;

  @override
  State<_BusinessRegisterScreen> createState() =>
      _BusinessRegisterScreenState();
}

class _BusinessRegisterScreenState extends State<_BusinessRegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _showPass = false;
  bool _loading = false;
  bool _otpSent = false;
  bool _emailVerified = false;
  Timer? _resendTimer;
  int _resendCooldown = 0;
  WebeyBackRegistration? _backRegistration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sistem geri tuşu: uygulamadan çıkmak yerine splash'e dön.
    _backRegistration ??= WebeyBackScope.register(context, () {
      widget.onBack();
      return true;
    });
  }

  @override
  void dispose() {
    _backRegistration?.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _otpCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!_validateForm()) return;
    if (!_emailVerified) {
      await (_otpSent ? _verifyOtpAndRegister() : _sendOtp());
      return;
    }
    await _register();
  }

  bool _validateForm() {
    final phone = _phoneCtrl.text.trim();
    if (phone.length != 10 || !phone.startsWith('5')) {
      _snack('Telefon 5 ile başlayan 10 haneli GSM numarası olmalı.');
      return false;
    }
    if (_passCtrl.text.length < 8) {
      _snack('Şifre en az 8 karakter olmalı.');
      return false;
    }
    final bizName = _nameCtrl.text.trim();
    if (bizName.isEmpty || !_emailCtrl.text.contains('@')) {
      _snack('İşletme adı ve geçerli e-posta girin.');
      return false;
    }
    if (bizName.length > 40) {
      _snack('İşletme adı en fazla 40 karakter olabilir.');
      return false;
    }
    return true;
  }

  Future<void> _sendOtp() async {
    setState(() => _loading = true);
    final result = await widget.authService.sendBusinessEmailOtp(
      _emailCtrl.text.trim(),
      'register',
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _otpSent = result.success;
    });
    if (result.success) {
      _startResendCooldown();
      _snack('E-posta adresinize gönderilen 6 haneli kodu girin.');
      return;
    }
    _snack(_otpMessage(result));
  }

  Future<void> _verifyOtpAndRegister() async {
    final code = _otpCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _snack('Kod hatalı. Lütfen tekrar deneyin.');
      return;
    }
    setState(() => _loading = true);
    final verifyResult = await widget.authService.verifyBusinessEmailOtp(
      _emailCtrl.text.trim(),
      code,
      'register',
    );
    if (!mounted) return;
    if (!verifyResult.success) {
      setState(() => _loading = false);
      _snack(_otpMessage(verifyResult));
      return;
    }
    setState(() => _emailVerified = true);
    await _register(keepLoading: true);
  }

  Future<void> _register({bool keepLoading = false}) async {
    if (!keepLoading) setState(() => _loading = true);
    final result = await widget.authService.businessRegister(
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      password: _passCtrl.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.success) {
      widget.onRegistered();
      return;
    }
    _snack(result.errorMessage ?? 'İşletme hesabı oluşturulamadı.');
  }

  Future<void> _resendOtp() async {
    if (_loading || _resendCooldown > 0) return;
    await _sendOtp();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
        return;
      }
      setState(() => _resendCooldown -= 1);
    });
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
    return message.isEmpty
        ? 'E-posta gönderilemedi. Lütfen tekrar deneyin.'
        : message;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.chevron_left_rounded),
                color: WebeyColors.darkEspresso,
              ),
              const SizedBox(height: 14),
              const Text(
                'İşletme hesabı oluştur',
                style: TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 24,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Profil bilgilerini kaydetmeden önce işletme oturumunu başlatalım.',
                style: TextStyle(
                  color: WebeyColors.mutedTaupe,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              _BizInput(
                controller: _nameCtrl,
                label: 'İşletme adı',
                maxLength: 40,
              ),
              const SizedBox(height: 12),
              _BizInput(
                controller: _emailCtrl,
                label: 'E-posta',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _BizPhoneInput(controller: _phoneCtrl),
              const SizedBox(height: 12),
              _BizInput(
                controller: _passCtrl,
                label: 'Şifre',
                obscureText: !_showPass,
                suffix: IconButton(
                  onPressed: () => setState(() => _showPass = !_showPass),
                  icon: Icon(
                    _showPass
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                  ),
                ),
              ),
              if (_otpSent && !_emailVerified) ...[
                const SizedBox(height: 12),
                _BizInput(
                  controller: _otpCtrl,
                  label: '6 haneli doğrulama kodu',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Kod 10 dakika geçerlidir.',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: (_loading || _resendCooldown > 0)
                          ? null
                          : _resendOtp,
                      child: Text(
                        _resendCooldown > 0
                            ? '${_resendCooldown}s'
                            : 'Kodu tekrar gönder',
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _emailVerified
                              ? 'Hesap oluştur ve devam et'
                              : _otpSent
                              ? 'Kodu doğrula ve devam et'
                              : 'Doğrulama kodu gönder',
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : widget.onLogin,
                  child: const Text('Zaten hesabın var mı? Giriş yap'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BizInput extends StatelessWidget {
  const _BizInput({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.maxLength,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLength: maxLength,
      inputFormatters: maxLength != null
          ? [LengthLimitingTextInputFormatter(maxLength)]
          : null,
      decoration: InputDecoration(hintText: label, suffixIcon: suffix),
    );
  }
}

class _BizPhoneInput extends StatelessWidget {
  const _BizPhoneInput({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    // +90 her zaman görünür (prefixIcon, focus'tan bağımsız) → eski prefixText
    // odak anında gelip placeholder ile çakışma hatasını çözer.
    return TextField(
      controller: controller,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      decoration: const InputDecoration(
        hintText: '5XX XXX XX XX',
        counterText: '',
        prefixIcon: Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 10, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(
              '+90',
              style: TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }
}
