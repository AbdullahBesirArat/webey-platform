// lib/shared/widgets/webey_toast.dart
//
// Uygulama içi bildirim helper'ı. Android default Toast ve alttan çıkan
// SnackBar yerine, ekranın ÜSTÜNDEN kayan modern bir banner gösterir.
// Banner safe-area içinde, bottom navigation / ana CTA'ları kapatmadan görünür.
//
// Kullanım:
//   WebeyToast.success(context, 'Kaydedildi');
//   WebeyToast.error(context, 'İşlem başarısız');
//   WebeyToast.info(context, 'Bilgi mesajı');

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/webey_colors.dart';

enum _WebeyToastKind { success, error, info }

class WebeyToast {
  const WebeyToast._();

  static OverlayEntry? _current;
  static Timer? _timer;

  static void success(BuildContext context, String message) =>
      _show(context, message, _WebeyToastKind.success);

  static void error(BuildContext context, String message) =>
      _show(context, message, _WebeyToastKind.error);

  static void info(BuildContext context, String message) =>
      _show(context, message, _WebeyToastKind.info);

  static void _dismiss() {
    _timer?.cancel();
    _timer = null;
    _current?.remove();
    _current = null;
  }

  static void _show(
    BuildContext context,
    String message,
    _WebeyToastKind kind,
  ) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // Önceki banner'ı temizle (üst üste binmeyi önle).
    _dismiss();

    final entry = OverlayEntry(
      builder: (ctx) =>
          _WebeyToastBanner(message: message, kind: kind, onDismiss: _dismiss),
    );
    _current = entry;
    overlay.insert(entry);

    _timer = Timer(const Duration(milliseconds: 3200), _dismiss);
  }
}

class _WebeyToastBanner extends StatefulWidget {
  const _WebeyToastBanner({
    required this.message,
    required this.kind,
    required this.onDismiss,
  });

  final String message;
  final _WebeyToastKind kind;
  final VoidCallback onDismiss;

  @override
  State<_WebeyToastBanner> createState() => _WebeyToastBannerState();
}

class _WebeyToastBannerState extends State<_WebeyToastBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..forward();

  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, -1.2),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (Color accent, Color bg, IconData icon) = switch (widget.kind) {
      _WebeyToastKind.success => (
        WebeyColors.successGreen,
        const Color(0xFFEAF6EF),
        Icons.check_circle_rounded,
      ),
      _WebeyToastKind.error => (
        WebeyColors.errorRed,
        const Color(0xFFFBEAEA),
        Icons.error_outline_rounded,
      ),
      _WebeyToastKind.info => (
        WebeyColors.primaryGold,
        WebeyColors.warmCream,
        Icons.info_outline_rounded,
      ),
    };

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _offset,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withAlpha(80)),
                  boxShadow: [
                    BoxShadow(
                      color: WebeyColors.darkEspresso.withAlpha(28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(icon, color: accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onDismiss,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.close_rounded,
                          size: 17,
                          color: WebeyColors.darkEspresso.withAlpha(130),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
