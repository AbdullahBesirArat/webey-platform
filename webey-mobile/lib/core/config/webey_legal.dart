// lib/core/config/webey_legal.dart
//
// webey.com.tr üzerinde barındırılan resmi yasal sayfalar ve destek kanalı.
// Mağaza (Play / App Store) formlarında ve uygulama içi yönlendirmelerde
// kullanılan tek kaynak. URL'ler webey-site içindeki public sayfalara denk gelir.

class WebeyLegal {
  const WebeyLegal._();

  static const _base = 'https://webey.com.tr';

  static const privacyPolicy = '$_base/gizlilik-politikasi';
  static const kvkk = '$_base/kvkk';
  static const terms = '$_base/kullanim-sartlari';
  static const accountDeletion = '$_base/hesap-silme';

  static const supportEmail = 'destek@webey.com.tr';
}
