// lib/shared/widgets/webey_back_handler.dart
//
// Android sistem geri tuşu için ortak kök katman.
//
// Kullanım:
//   - Root route'un en üstüne `WebeyExitGuard(child: ...)` sarılır.
//   - Alt ekranlar (tab shell, harita görünümü, adım akışları) kendi
//     "geri" davranışlarını `WebeyBackScope.register/unregister` ile
//     interceptor olarak kaydeder. Interceptor true dönerse geri tuşu
//     tüketilmiş sayılır; hiçbiri tüketmezse çıkış onayı gösterilir.
//   - Push edilen route'lar (sayfa, dialog, bottom sheet) bu katmana
//     hiç gelmeden normal pop olur; guard yalnızca root route'un
//     kapanmasını (= uygulamadan çıkışı) yakalar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/webey_colors.dart';

/// true dönerse geri tuşu olayı tüketildi demektir (örn. tab değişti,
/// harita kapandı, bir önceki adıma dönüldü).
typedef WebeyBackInterceptor = bool Function();

class WebeyExitGuard extends StatefulWidget {
  const WebeyExitGuard({super.key, required this.child});

  final Widget child;

  @override
  State<WebeyExitGuard> createState() => _WebeyExitGuardState();
}

class _WebeyExitGuardState extends State<WebeyExitGuard> {
  final List<WebeyBackInterceptor> _interceptors = [];
  bool _dialogOpen = false;

  void _register(WebeyBackInterceptor interceptor) {
    if (!_interceptors.contains(interceptor)) _interceptors.add(interceptor);
  }

  void _unregister(WebeyBackInterceptor interceptor) {
    _interceptors.remove(interceptor);
  }

  Future<void> _handleBack() async {
    // İçten dışa: en son kaydedilen (en derindeki ekran) önce sorulur.
    for (final interceptor in _interceptors.reversed.toList()) {
      if (interceptor()) return;
    }
    if (_dialogOpen) return;
    _dialogOpen = true;
    final exit = await showWebeyExitDialog(context);
    _dialogOpen = false;
    if (exit == true) SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: _WebeyBackScopeMarker(state: this, child: widget.child),
    );
  }
}

class _WebeyBackScopeMarker extends InheritedWidget {
  const _WebeyBackScopeMarker({required this.state, required super.child});

  final _WebeyExitGuardState state;

  @override
  bool updateShouldNotify(_WebeyBackScopeMarker oldWidget) =>
      state != oldWidget.state;
}

class WebeyBackScope {
  const WebeyBackScope._();

  static _WebeyExitGuardState? _of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_WebeyBackScopeMarker>()?.state;

  /// Geri tuşu interceptor'ı kaydeder. `didChangeDependencies` içinde
  /// çağırmak güvenlidir; aynı referans iki kez eklenmez. Dönen handle
  /// `dispose()` içinde kapatılmalıdır (context'e ihtiyaç duymaz).
  static WebeyBackRegistration? register(
    BuildContext context,
    WebeyBackInterceptor interceptor,
  ) {
    final state = _of(context);
    if (state == null) return null;
    state._register(interceptor);
    return WebeyBackRegistration._(state, interceptor);
  }
}

/// [WebeyBackScope.register] sonucu; ekran dispose olurken kapatılır.
class WebeyBackRegistration {
  WebeyBackRegistration._(this._state, this._interceptor);

  final _WebeyExitGuardState _state;
  final WebeyBackInterceptor _interceptor;

  void dispose() => _state._unregister(_interceptor);
}

/// Uygulamadan çıkış onayı. true → çık, false/null → kal.
Future<bool?> showWebeyExitDialog(BuildContext context) {
  return showWebeyConfirmDialog(
    context,
    icon: Icons.logout_rounded,
    title: 'Uygulamadan çıkmak istiyor musunuz?',
    message: 'Webey’den çıkmak üzeresiniz.',
    cancelLabel: 'Vazgeç',
    confirmLabel: 'Çık',
  );
}

/// Webey tasarımına uygun genel onay dialog'u.
/// true → onay (destruktif aksiyon), false/null → vazgeç.
Future<bool?> showWebeyConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = 'Vazgeç',
  String confirmLabel = 'Çık',
  IconData? icon,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: WebeyColors.alpha(WebeyColors.darkEspresso, 0.45),
    builder: (ctx) => Dialog(
      backgroundColor: WebeyColors.ivory,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WebeyRadius.large),
        side: const BorderSide(color: WebeyColors.borderSand),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (icon != null) ...[
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: WebeyColors.warmCream,
                  shape: BoxShape.circle,
                  border: Border.all(color: WebeyColors.borderSand),
                ),
                child: Icon(icon, size: 22, color: WebeyColors.primaryGold),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 17,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: WebeyColors.primaryGold,
                  foregroundColor: WebeyColors.darkEspresso,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                child: Text(cancelLabel),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              child: OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: WebeyColors.errorRed,
                  side: BorderSide(
                    color: WebeyColors.alpha(WebeyColors.errorRed, 0.55),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(confirmLabel),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
