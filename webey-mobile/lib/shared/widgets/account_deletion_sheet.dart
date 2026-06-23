// lib/shared/widgets/account_deletion_sheet.dart
//
// Hesap silme talebi alt sayfası — hem müşteri hem işletme uygulamasında
// kullanılır. Gerçek silme YAPMAZ; kullanıcıyı KVKK / Gizlilik Politikası
// kapsamında değerlendirilmek üzere resmi hesap silme sayfasına ve destek
// e-postasına yönlendirir. (Play / App Store hesap silme gereksinimi.)

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/webey_legal.dart';
import '../../core/theme/webey_colors.dart';
import 'webey_toast.dart';

class WebeyAccountDeletionSheet extends StatelessWidget {
  const WebeyAccountDeletionSheet({super.key});

  /// Alt sayfayı açar.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const WebeyAccountDeletionSheet(),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        WebeyToast.error(context, 'Bağlantı açılamadı.');
      }
    } catch (_) {
      if (context.mounted) {
        WebeyToast.error(context, 'Bağlantı açılamadı.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: WebeyColors.ivory,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: WebeyColors.errorRed.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: WebeyColors.errorRed,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Hesabımı Sil',
                      style: TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 18,
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Hesap silme talebiniz Webey ekibine iletilecek. Randevu geçmişi, '
                'yasal yükümlülükler ve güvenlik kayıtları KVKK ve Gizlilik '
                'Politikası kapsamında değerlendirilebilir.',
                style: TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 13.5,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Talebinizi aşağıdaki resmi sayfadan oluşturabilir veya destek '
                'ekibimize yazabilirsiniz.',
                style: TextStyle(
                  color: WebeyColors.mutedTaupe,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              _DeletionButton(
                label: 'Hesap Silme Sayfasını Aç',
                icon: Icons.open_in_new_rounded,
                filled: true,
                onTap: () => _open(context, WebeyLegal.accountDeletion),
              ),
              const SizedBox(height: 10),
              _DeletionButton(
                label: 'Destek\'e E-posta Gönder',
                icon: Icons.mail_outline_rounded,
                filled: false,
                onTap: () => _open(
                  context,
                  'mailto:${WebeyLegal.supportEmail}'
                  '?subject=${Uri.encodeComponent('Hesap Silme Talebi')}',
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  WebeyLegal.accountDeletion,
                  style: const TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Vazgeç',
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeletionButton extends StatelessWidget {
  const _DeletionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : WebeyColors.darkEspresso;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: filled ? WebeyColors.darkEspresso : WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(13),
          border: filled ? null : Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: fg),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
