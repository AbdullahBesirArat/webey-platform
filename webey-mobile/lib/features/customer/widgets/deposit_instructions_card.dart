// lib/features/customer/widgets/deposit_instructions_card.dart
//
// MVP kapora talimatı kartı (müşteri tarafı).
// Para Webey'de toplanmaz; müşteri kaporayı doğrudan salonun IBAN'ına gönderir.
//
// Akış: müşteri IBAN'a havale yapar → "IBAN'a parayı gönderdim" der →
// deposit_status = customer_marked_sent → işletme "Para geldi" ile onaylar →
// deposit_status = paid + randevu onaylanır.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/webey_colors.dart';
import '../../../shared/models/beauty_models.dart';
import '../../../shared/widgets/webey_toast.dart';

class DepositStatusBadge extends StatelessWidget {
  const DepositStatusBadge({super.key, required this.status});
  final String status;

  ({String label, Color color, Color bg}) _style() {
    switch (status) {
      case 'paid':
        return (
          label: 'Kapora onaylandı',
          color: WebeyColors.successGreen,
          bg: WebeyColors.successGreen.withAlpha(28),
        );
      case 'not_received':
      case 'rejected':
        return (
          label: 'Ödeme doğrulanamadı',
          color: WebeyColors.errorRed,
          bg: WebeyColors.errorRed.withAlpha(28),
        );
      case 'waived':
        return (
          label: 'Kapora muaf',
          color: WebeyColors.mutedTaupe,
          bg: WebeyColors.warmCream,
        );
      case 'refunded':
        return (
          label: 'Kapora iade edildi',
          color: WebeyColors.mutedTaupe,
          bg: WebeyColors.warmCream,
        );
      case 'customer_marked_sent':
        return (
          label: 'İşletme kontrol ediyor',
          color: WebeyColors.primaryGold,
          bg: WebeyColors.primaryGold.withAlpha(28),
        );
      default:
        return (
          label: 'Kapora bekleniyor',
          color: WebeyColors.warning,
          bg: WebeyColors.warning.withAlpha(28),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        s.label,
        style: TextStyle(
          color: s.color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class DepositInstructionsCard extends StatelessWidget {
  const DepositInstructionsCard({
    super.key,
    required this.deposit,
    this.onMarkSent,
    this.marking = false,
    this.onCancel,
    this.cancelling = false,
    this.actionsDisabled = false,
  });

  final DepositInfo deposit;

  /// "IBAN'a parayı gönderdim" butonu için callback. null ise buton yerine
  /// (gönderilebilir durumdaysa) bilgi notu gösterilir — confirm önizlemesi.
  final VoidCallback? onMarkSent;

  /// "IBAN'a parayı gönderdim" loading durumu.
  final bool marking;

  /// "Randevuyu iptal et" butonu için callback. null ise buton gösterilmez.
  final VoidCallback? onCancel;

  /// İptal loading durumu.
  final bool cancelling;

  /// Randevu iptal edildi / iptal talebi gönderildi: tüm aksiyonlar kapalı.
  final bool actionsDisabled;

  void _copy(BuildContext context, String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    WebeyToast.success(context, '$label kopyalandı');
  }

  @override
  Widget build(BuildContext context) {
    if (!deposit.required) return const SizedBox.shrink();
    final amount = deposit.amount;
    final refCode = deposit.referenceCode ?? '';
    final showInstructionsIntro =
        !deposit.awaitingIban &&
        !deposit.isPaid &&
        !deposit.isNotReceived &&
        !deposit.isMarkedSent &&
        !actionsDisabled;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 17,
                color: WebeyColors.primaryGold,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Kapora Ödeme Bilgileri',
                  style: TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 14.5,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              DepositStatusBadge(status: deposit.status),
            ],
          ),
          if (showInstructionsIntro) ...[
            const SizedBox(height: 8),
            Text(
              'Kapora tutarını aşağıdaki IBAN\'a gönderin. Gönderimden sonra '
              '"IBAN\'a parayı gönderdim" butonuna basın.',
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (amount != null && amount > 0)
            Text(
              'Kapora tutarı: ${amount.toInt()} TL',
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),

          // Salon IBAN eklememişse bilgilendirme.
          if (deposit.awaitingIban) ...[
            const SizedBox(height: 8),
            Text(
              'Salon kapora ödeme bilgilerini henüz eklememiş. '
              'Salon sizinle iletişime geçebilir.',
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            _row(
              context,
              'IBAN',
              deposit.ibanFormatted.isNotEmpty
                  ? deposit.ibanFormatted
                  : deposit.iban,
              copyValue: deposit.iban,
              copyLabel: 'IBAN',
            ),
            if (deposit.accountHolder != null)
              _row(context, 'Hesap sahibi', deposit.accountHolder!),
            if (deposit.bankName != null)
              _row(context, 'Banka', deposit.bankName!),
            if (refCode.isNotEmpty)
              _row(
                context,
                'Açıklama',
                refCode,
                copyValue: refCode,
                copyLabel: 'Açıklama kodu',
              ),
            if (deposit.instructions != null) ...[
              const SizedBox(height: 8),
              Text(
                deposit.instructions!,
                style: TextStyle(
                  color: WebeyColors.mutedTaupe,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Görünür IBAN / açıklama kodu kopyala butonları.
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: () => _copy(context, deposit.iban, 'IBAN'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: WebeyColors.darkEspresso,
                        side: const BorderSide(color: WebeyColors.borderSand),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 15),
                      label: const Text(
                        'IBAN\'ı Kopyala',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                if (refCode.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _copy(context, refCode, 'Açıklama kodu'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: WebeyColors.darkEspresso,
                          side: const BorderSide(color: WebeyColors.borderSand),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        icon: const Icon(Icons.tag_rounded, size: 15),
                        label: const Text(
                          'Kodu Kopyala',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: WebeyColors.warmCream,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kapora ödemesi doğrudan salonun banka hesabına yapılır. '
                  'Webey ödeme tahsil etmez.',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
                if (refCode.isNotEmpty && !deposit.awaitingIban) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Ödeme açıklamasına bu kodu yazın: $refCode',
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Kapora iade/iptal koşulları salon tarafından belirlenir.',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          _buildStatusInfo(),
          _buildMarkSent(),
          _buildCancel(),
        ],
      ),
    );
  }

  /// Durum bazlı bilgi şeridi (paid / not_received / iptal).
  Widget _buildStatusInfo() {
    if (actionsDisabled) {
      return _infoStrip(
        icon: Icons.block_rounded,
        color: WebeyColors.mutedTaupe,
        text: 'Randevu iptal sürecinde. Kapora aksiyonları kapalı.',
      );
    }
    if (deposit.isPaid) {
      return _infoStrip(
        icon: Icons.check_circle_rounded,
        color: WebeyColors.successGreen,
        text: 'Kapora onaylandı. Randevunuz onaylandı.',
      );
    }
    if (deposit.isNotReceived) {
      return _infoStrip(
        icon: Icons.error_outline_rounded,
        color: WebeyColors.errorRed,
        text:
            'Ödeme doğrulanamadı. İşletme kaporayı henüz almadığını bildirdi. '
            'Lütfen salonla iletişime geçin.',
      );
    }
    return const SizedBox.shrink();
  }

  Widget _infoStrip({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: color.withAlpha(18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "IBAN'a parayı gönderdim" butonu / gönderildi bilgisi.
  Widget _buildMarkSent() {
    // IBAN yoksa, kapora terminal durumdaysa veya randevu iptaldeyse buton yok.
    if (deposit.awaitingIban ||
        deposit.isPaid ||
        deposit.isNotReceived ||
        actionsDisabled) {
      return const SizedBox.shrink();
    }

    // Zaten bildirilmiş → disabled bilgi.
    if (deposit.isMarkedSent) {
      return _infoStrip(
        icon: Icons.check_circle_outline_rounded,
        color: WebeyColors.primaryGold,
        text:
            'Ödeme bildiriminiz işletmeye iletildi. İşletme hesabını kontrol '
            'edip onayladıktan sonra randevunuz onaylanacaktır.',
      );
    }

    if (!deposit.canMarkSent) {
      return const SizedBox.shrink();
    }

    // Confirm önizlemesi (randevu henüz oluşmadı): buton yerine bilgi notu.
    if (onMarkSent == null) {
      return _infoStrip(
        icon: Icons.info_outline_rounded,
        color: WebeyColors.primaryGold,
        text:
            'Randevu oluşturulduktan sonra "IBAN\'a parayı gönderdim" '
            'butonunu kullanabilirsiniz.',
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: marking ? null : onMarkSent,
          icon: marking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded, size: 17),
          label: Text(marking ? 'Gönderiliyor...' : "IBAN'a parayı gönderdim"),
        ),
      ),
    );
  }

  /// "Randevuyu iptal et" — kırmızı outline ikincil aksiyon.
  Widget _buildCancel() {
    if (onCancel == null ||
        actionsDisabled ||
        deposit.isPaid ||
        deposit.isNotReceived) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: OutlinedButton.icon(
          onPressed: (cancelling || marking) ? null : onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: WebeyColors.errorRed,
            side: BorderSide(color: WebeyColors.errorRed.withAlpha(120)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: cancelling
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: WebeyColors.errorRed,
                  ),
                )
              : const Icon(Icons.cancel_outlined, size: 17),
          label: Text(
            cancelling ? 'İptal ediliyor...' : 'Randevuyu iptal et',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    String? copyValue,
    String? copyLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (copyValue != null)
            GestureDetector(
              onTap: () => _copy(context, copyValue, copyLabel ?? label),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: WebeyColors.primaryGold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
