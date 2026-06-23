import '../models/beauty_models.dart';

String money(num value) {
  final rounded = value.round();
  final text = rounded.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return '$text TL';
}

String shortDate(DateTime dateTime) {
  const months = [
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ];
  return '${dateTime.day} ${months[dateTime.month - 1]}';
}

String clock(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String appointmentStatusLabel(AppointmentStatus status) {
  return switch (status) {
    AppointmentStatus.pending => 'Onay bekliyor',
    AppointmentStatus.approved => 'Onaylandı',
    AppointmentStatus.completed => 'Tamamlandı',
    AppointmentStatus.cancelled => 'İptal edildi',
    AppointmentStatus.cancellationRequested => 'İptal talebi var',
    AppointmentStatus.noShow => 'Gelmedi',
    AppointmentStatus.rejected => 'Reddedildi',
  };
}

String depositStatusLabel(DepositStatus status) {
  return switch (status) {
    DepositStatus.none => 'Ödeme salonda',
    DepositStatus.pending => 'Kapora bekliyor',
    DepositStatus.paid => 'Kapora ödendi',
    DepositStatus.refunded => 'Kapora iade',
    DepositStatus.failed => 'Kapora başarısız',
  };
}

String depositBadgeLabel(bool acceptsDeposit) {
  return acceptsDeposit ? 'Garantili Randevu' : 'Kaporasız Randevu';
}

String relativeDate(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
  if (diff.inHours < 24) return '${diff.inHours} sa önce';
  if (diff.inDays == 1) return 'Dün';
  if (diff.inDays < 7) return '${diff.inDays} gün önce';
  return shortDate(dt);
}

String ratingStr(double r) => r.toStringAsFixed(1);

String reviewCountText(int count) {
  if (count >= 1000) {
    final value = (count / 1000).toStringAsFixed(count % 1000 == 0 ? 0 : 1);
    return '$value bin yorum';
  }
  return '$count yorum';
}

String cancellationHoursText(int hours) {
  if (hours <= 0) return 'İade koşulu işletme onayına bağlı';
  if (hours % 24 == 0) return '${hours ~/ 24} gün öncesine kadar';
  return '$hours saat öncesine kadar';
}

String notificationTimeText(DateTime dt) => relativeDate(dt);

String campaignPrice(CampaignPackage package) {
  return '${money(package.discountedPrice)} · ${package.discountLabel}';
}

String validUntilText(DateTime dt) => '${shortDate(dt)} tarihine kadar geçerli';

String waitlistStatusText(String status) {
  return switch (status) {
    'waiting' => 'Beklemede',
    'notified' => 'Uygunluk bildirildi',
    'booked' => 'Randevuya dönüştü',
    'cancelled' => 'İptal edildi',
    _ => 'Beklemede',
  };
}

String smartSuggestionLabel(String type) {
  return switch (type) {
    'earliest' => 'En erken',
    'popular' => 'Popüler',
    'premium' => 'Premium',
    'favorite' => 'Favori',
    'nearby' => 'Yakında',
    'lowDeposit' => 'Düşük kapora',
    'noDeposit' => 'Kaporasız',
    _ => 'Öneri',
  };
}

String shortDistance(double km) => '${km.toStringAsFixed(1)} km';

String compactReviewCount(int count) => reviewCountText(count);

String compactCurrency(num value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)} Mn TL';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} B TL';
  return money(value);
}

String percentage(double value) => '%${(value * 100).round()}';

String maskedPhone(String value) => value;

String analyticsPeriodLabel(String period) {
  return switch (period) {
    'week' => 'Bu hafta',
    'month' => 'Bu ay',
    'quarter' => 'Son 3 ay',
    _ => 'Bu ay',
  };
}

String noShowRateText(double rate) => percentage(rate);

String trendValueText(num value) =>
    value >= 1000 ? compactCurrency(value) : value.round().toString();

String calendarDate(DateTime dt) {
  const months = [
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ];
  const weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
  return '${dt.day} ${months[dt.month - 1]} ${weekdays[dt.weekday - 1]}';
}
