import 'package:flutter/material.dart';

import 'presentation/auth_flow.dart';

class AuthGateScreen extends StatelessWidget {
  const AuthGateScreen({
    super.key,
    required this.reason,
    required this.onAuthenticated,
    this.onContinueGuest,
  });

  final String reason;
  final VoidCallback onAuthenticated;
  final VoidCallback? onContinueGuest;

  @override
  Widget build(BuildContext context) {
    return AuthFlow(
      contextNote: reason,
      onAuthenticated: onAuthenticated,
      onGuest: onContinueGuest ?? () => Navigator.of(context).maybePop(),
    );
  }
}

class AuthGateSheet extends StatelessWidget {
  const AuthGateSheet({
    super.key,
    required this.reason,
    required this.onAuthenticated,
  });

  final String reason;
  final VoidCallback onAuthenticated;

  @override
  Widget build(BuildContext context) {
    Future<void> openAuth({bool register = false}) async {
      final authed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AuthFlow(
            contextNote: reason,
            startWithRegister: register,
            onAuthenticated: () => Navigator.of(context).pop(true),
            onGuest: () => Navigator.of(context).pop(false),
          ),
        ),
      );
      if ((authed ?? false) && context.mounted) {
        onAuthenticated();
      }
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8DFD4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF5EDD8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFB8964E).withAlpha(60),
                ),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 22,
                color: Color(0xFFB8964E),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF1C1209),
                fontSize: 17,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Seçtiğin saati koruyalım ve randevu bildirimlerini sana gönderelim.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF1C1209).withAlpha(158),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => openAuth(),
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFB8964E),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.login_rounded,
                      size: 17,
                      color: Color(0xFF1C1209),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Giriş Yap ve Devam Et',
                      style: TextStyle(
                        color: Color(0xFF1C1209),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => openAuth(register: true),
              child: Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: const Color(0xFFB8964E).withAlpha(100),
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Yeni hesap oluştur',
                    style: TextStyle(
                      color: Color(0xFFB8964E),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Şimdilik Vazgeç',
                  style: TextStyle(
                    color: Color(0xFF9C8E82),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
