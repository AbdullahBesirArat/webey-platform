// lib/features/splash/splash_and_legal_screens.dart
//
// Claude Design → Flutter dönüşümü
// Webey Beauty — Splash & Legal
// 1. _CustomerSplashScreen  (customer_start_flow.dart'a taşınacak)
// 2. LegalDocumentsScreen   (customer/presentation/legal_documents_screen.dart'ı değiştirir)
// 3. _BizSplash             (business/business_start_flow.dart'a taşınacak)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/webey_legal.dart';
import '../../core/theme/webey_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 1 — Müşteri Karşılama (Splash)
// customer_start_flow.dart içindeki _CustomerSplashScreen'i bununla değiştir
// ─────────────────────────────────────────────────────────────────────────────

class CustomerSplashScreen extends StatelessWidget {
  const CustomerSplashScreen({
    super.key,
    required this.onContinue,
    this.onBusinessLogin,
  });
  final VoidCallback onContinue;
  final VoidCallback? onBusinessLogin;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: WebeyColors.darkEspresso,
        body: Column(
          children: [
            // ── Hero ───────────────────────────────────────────────────────
            Expanded(
              flex: 5,
              child: _SplashHero(
                wordmark: 'Webey Beauty',
                wordmarkItalic: 'Beauty',
                tagline: 'Premium güzellik randevuları',
              ),
            ),
            // ── Floating card ─────────────────────────────────────────────
            _SplashCard(
              eyebrow: 'HOŞ GELDİNİZ',
              titlePlain: 'Güzelliğini keşfet, randevunu ',
              titleItalic: 'güvenle',
              titleTail: ' oluştur.',
              body: 'Kaporalı veya kaporasız salonları gör, hizmetini seç ve saatini ayır.',
              trustItems: const [
                _TrustItem(icon: Icons.lock_outline_rounded, label: 'Güvenli ödeme'),
                _TrustItem(icon: Icons.star_outline_rounded, label: 'Premium salonlar'),
                _TrustItem(icon: Icons.calendar_today_outlined, label: 'Anında randevu'),
              ],
              primaryLabel: 'Keşfe Başla',
              onPrimary: onContinue,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 3 — İşletme Karşılama (Business Splash)
// business/business_start_flow.dart içindeki _BizSplash'ı bununla değiştir
// ─────────────────────────────────────────────────────────────────────────────

class BusinessSplashScreen extends StatelessWidget {
  const BusinessSplashScreen({
    super.key,
    required this.onRegister,
    required this.onLogin,
    this.onDemo,
  });
  final VoidCallback onRegister;
  final VoidCallback onLogin;
  final VoidCallback? onDemo;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: WebeyColors.darkEspresso,
        body: Column(
          children: [
            Expanded(
              flex: 5,
              child: _SplashHero(
                wordmark: 'Webey · İşletme',
                wordmarkItalic: '· İşletme',
                tagline: 'Salon yönetim platformu',
              ),
            ),
            _SplashCard(
              eyebrow: 'SALONUNUZU BÜYÜTÜN',
              titlePlain: 'Randevuları dijitale taşı, işini ',
              titleItalic: 'büyüt.',
              titleTail: '',
              body: 'Kaporalı randevu sistemi, akıllı takvim ve müşteri yönetimiyle fark yarat.',
              trustItems: const [
                _TrustItem(icon: Icons.calendar_today_outlined, label: 'Akıllı takvim'),
                _TrustItem(icon: Icons.account_balance_wallet_outlined, label: 'Kapora güvencesi'),
                _TrustItem(icon: Icons.bar_chart_rounded, label: 'Gelir takibi'),
              ],
              primaryLabel: 'Salonu Kaydet',
              onPrimary: onRegister,
              linkLabel: 'Hesabınız var mı?  Giriş yap →',
              onLink: onLogin,
              subLink: onDemo != null ? 'Demo ile keşfet' : null,
              onSubLink: onDemo,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED: Splash Hero (dark espresso top)
// ─────────────────────────────────────────────────────────────────────────────

class _SplashHero extends StatelessWidget {
  const _SplashHero({
    required this.wordmark,
    required this.wordmarkItalic,
    required this.tagline,
  });
  final String wordmark, wordmarkItalic, tagline;

  String get _wordmarkPlain =>
      wordmark.replaceAll(wordmarkItalic, '').trim();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [WebeyColors.darkEspresso, Color(0xFF2d1a0e)],
        ),
      ),
      child: Stack(
        children: [
          // Diagonal texture
          Positioned.fill(
            child: CustomPaint(painter: _DiagonalTexturePainter()),
          ),
          // Gold radial glow top-left
          Positioned(
            left: -60, top: -60,
            child: Container(
              width: 280, height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    WebeyColors.primaryGold.withAlpha(50),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Content
          SafeArea(
            bottom: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // W mark
                  Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFD4B574),
                          Color(0xFFB8964E),
                          Color(0xFF8C6F38),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: WebeyColors.primaryGold.withAlpha(100),
                          blurRadius: 40,
                          spreadRadius: -5,
                          offset: const Offset(0, 22),
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white.withAlpha(45), width: 1),
                    ),
                    child: Center(
                      child: Text('W',
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 54,
                            fontFamily: 'Georgia',
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                            height: 1,
                          )),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Wordmark
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                        height: 1,
                      ),
                      children: [
                        TextSpan(text: _wordmarkPlain),
                        TextSpan(
                          text: wordmarkItalic,
                          style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Color(0xFFD4B574),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Tagline
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: 18, height: 1,
                          color: WebeyColors.primaryGold.withAlpha(130)),
                      const SizedBox(width: 10),
                      Text(
                        tagline.toUpperCase(),
                        style: TextStyle(
                          color: const Color(0xFFD4B574),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2.2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(width: 18, height: 1,
                          color: WebeyColors.primaryGold.withAlpha(130)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagonalTexturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD4B574).withAlpha(10)
      ..strokeWidth = 1.5;
    const spacing = 22.0;
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED: Splash Card (ivory bottom)
// ─────────────────────────────────────────────────────────────────────────────

class _TrustItem {
  const _TrustItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class _SplashCard extends StatelessWidget {
  const _SplashCard({
    required this.eyebrow,
    required this.titlePlain,
    required this.titleItalic,
    required this.titleTail,
    required this.body,
    required this.trustItems,
    required this.primaryLabel,
    required this.onPrimary,
    this.linkLabel,
    this.onLink,
    this.subLink,
    this.onSubLink,
  });
  final String eyebrow, titlePlain, titleItalic, titleTail, body;
  final List<_TrustItem> trustItems;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? linkLabel;
  final VoidCallback? onLink;
  final String? subLink;
  final VoidCallback? onSubLink;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: WebeyColors.ivory,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Color(0x4D1C1209),
            blurRadius: 40,
            offset: Offset(0, -18),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          28, 32, 28, 28 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Eyebrow
          Row(children: [
            Container(width: 14, height: 1,
                color: WebeyColors.primaryGold),
            const SizedBox(width: 8),
            Text(eyebrow,
                style: TextStyle(
                    color: const Color(0xFF8C6F38),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8)),
          ]),
          const SizedBox(height: 10),
          // Title
          RichText(
            text: TextSpan(
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 28,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w500,
                height: 1.12,
                letterSpacing: -0.012 * 28,
              ),
              children: [
                TextSpan(text: titlePlain),
                TextSpan(
                  text: titleItalic,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF8C6F38),
                  ),
                ),
                if (titleTail.isNotEmpty) TextSpan(text: titleTail),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Body
          Text(body,
              style: TextStyle(
                  color: WebeyColors.darkEspresso.withAlpha(158),
                  fontSize: 13,
                  height: 1.55)),
          const SizedBox(height: 18),
          // Trust row
          Row(
            children: trustItems.map((t) => Expanded(
              child: Container(
                margin: EdgeInsets.only(
                    right: t != trustItems.last ? 8 : 0),
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 12),
                decoration: BoxDecoration(
                  color: WebeyColors.warmCream,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: WebeyColors.darkEspresso.withAlpha(25)),
                ),
                child: Column(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: WebeyColors.darkEspresso.withAlpha(25)),
                    ),
                    child: Icon(t.icon, size: 14,
                        color: const Color(0xFF8C6F38)),
                  ),
                  const SizedBox(height: 6),
                  Text(t.label.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          height: 1.3)),
                ]),
              ),
            )).toList(),
          ),
          const SizedBox(height: 22),
          // Primary button
          GestureDetector(
            onTap: onPrimary,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: WebeyColors.primaryGold,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: WebeyColors.primaryGold.withAlpha(140),
                    blurRadius: 26,
                    spreadRadius: -10,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    primaryLabel.toUpperCase(),
                    style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 15, color: WebeyColors.darkEspresso),
                ],
              ),
            ),
          ),
          if (linkLabel != null) ...[
            const SizedBox(height: 10),
            // Link
            GestureDetector(
              onTap: onLink,
              child: Center(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                        color: WebeyColors.darkEspresso.withAlpha(158),
                        fontSize: 11.5),
                    children: linkLabel!.contains('→')
                        ? [
                            TextSpan(
                                text: linkLabel!.split('→').first),
                            TextSpan(
                              text: '→',
                              style: const TextStyle(
                                  color: Color(0xFF8C6F38),
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Color(0xFF8C6F38)),
                            ),
                          ]
                        : [TextSpan(text: linkLabel!)],
                  ),
                ),
              ),
            ),
          ],
          if (subLink != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: onSubLink,
              child: Center(
                child: Text(subLink!,
                    style: TextStyle(
                        color: WebeyColors.primaryGold,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        decorationColor: WebeyColors.primaryGold)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 2 — Yasal Belgeler
// legal_documents_screen.dart dosyasını BU CLASS ile değiştir
// ─────────────────────────────────────────────────────────────────────────────

class LegalDocumentsScreen extends StatefulWidget {
  const LegalDocumentsScreen({super.key});

  @override
  State<LegalDocumentsScreen> createState() =>
      _LegalDocumentsScreenState();
}

class _LegalDocumentsScreenState extends State<LegalDocumentsScreen> {
  String? _openId = 'd1';

  static final _docs = [
    _DocItem(
      id: 'd1',
      title: 'Kullanım Şartları',
      summary: 'Randevu, kapora ve platform kullanımına dair kurallar.',
      quote:
          'Webey, salon ve müşteri arasındaki randevu sürecini güvence altına alan dijital bir aracıdır. Kaporalı randevularda kapora yalnızca taraflar arasında uzlaşı sağlanana kadar Webey altyapısında tutulur.',
      updated: '12 May 2026',
      version: 'v3.2',
    ),
    _DocItem(
      id: 'd2',
      title: 'Gizlilik Politikası',
      summary:
          'Kişisel verilerin nasıl işlendiği ve korunduğu hakkında.',
      updated: '04 May 2026',
      version: 'v2.8',
    ),
    _DocItem(
      id: 'd3',
      title: 'Kapora ve İptal Politikası',
      summary: 'Kapora tahsilatı, iade koşulları ve iptal kuralları.',
      updated: '17 Nis 2026',
      version: 'v2.4',
    ),
    _DocItem(
      id: 'd4',
      title: 'KVKK Aydınlatma Metni',
      summary:
          '6698 sayılı kanun kapsamında haklarınız ve veri işleme.',
      updated: '01 Mar 2026',
      version: 'v1.6',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: WebeyColors.ivory,
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Header
              SliverToBoxAdapter(child: _LegalHeader()),
              // Webey mini card
              SliverToBoxAdapter(child: _WebeyMiniCard()),
              // Doc list
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final doc = _docs[i];
                      return _DocCard(
                        doc: doc,
                        isOpen: _openId == doc.id,
                        onTap: () => setState(() =>
                            _openId = _openId == doc.id ? null : doc.id),
                      );
                    },
                    childCount: _docs.length,
                  ),
                ),
              ),
              // Contact card
              SliverToBoxAdapter(child: _ContactCard()),
              // Resmî web belgeleri — mağaza uyumluluğu için public URL'ler
              const SliverToBoxAdapter(child: _LegalWebLinks()),
              // Footer
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'WEBEY BEAUTY  ·  İSTANBUL  ·  2026',
                      style: TextStyle(
                          color: WebeyColors.darkEspresso.withAlpha(100),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Resmî Web Belgeleri ──────────────────────────────────────────────────────

class _LegalWebLinks extends StatelessWidget {
  const _LegalWebLinks();

  static const _links = <(String, String)>[
    ('Gizlilik Politikası — webey.com.tr', WebeyLegal.privacyPolicy),
    ('KVKK Aydınlatma Metni — webey.com.tr', WebeyLegal.kvkk),
    ('Kullanım Şartları — webey.com.tr', WebeyLegal.terms),
    ('Hesap Silme Talebi — webey.com.tr', WebeyLegal.accountDeletion),
  ];

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RESMÎ BELGELER',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Güncel sürümler webey.com.tr üzerinde yayımlanır.',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          ..._links.map(
            (link) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => _open(link.$2),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: WebeyColors.warmCream,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: WebeyColors.primaryGold,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          link.$1,
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: WebeyColors.mutedTaupe,
                      ),
                    ],
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

// ── Legal Header ─────────────────────────────────────────────────────────────

class _LegalHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
      child: Column(children: [
        Row(children: [
          GestureDetector(
            onTap: () => Navigator.maybePop(context),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: WebeyColors.warmCream,
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: const Icon(Icons.chevron_left_rounded, size: 20,
                  color: WebeyColors.darkEspresso),
            ),
          ),
          Expanded(
            child: Center(
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(
                      color: WebeyColors.darkEspresso, fontSize: 22,
                      fontFamily: 'Georgia', fontWeight: FontWeight.w500),
                  children: [
                    TextSpan(text: 'Yasal '),
                    TextSpan(
                        text: 'Bilgi',
                        style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Color(0xFF8C6F38))),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 38),
        ]),
        const SizedBox(height: 6),
        Text(
          'Şeffaf, güvenli ve anlaşılır kullanım için tüm belgeleriniz tek yerde.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: WebeyColors.darkEspresso.withAlpha(158),
              fontSize: 11.5, height: 1.4),
        ),
      ]),
    );
  }
}

// ── Webey Mini Card ───────────────────────────────────────────────────────────

class _WebeyMiniCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WebeyColors.borderSand),
          boxShadow: [
            BoxShadow(
              color: WebeyColors.darkEspresso.withAlpha(15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2a1a0f), WebeyColors.darkEspresso],
              ),
            ),
            child: Center(
              child: Text('W',
                  style: TextStyle(
                      color: const Color(0xFFD4B574), fontSize: 18,
                      fontFamily: 'Georgia', fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                        color: WebeyColors.darkEspresso, fontSize: 14.5,
                        fontFamily: 'Georgia', fontWeight: FontWeight.w500),
                    children: [
                      TextSpan(text: 'Webey '),
                      TextSpan(text: 'Beauty',
                          style: TextStyle(fontStyle: FontStyle.italic,
                              color: Color(0xFF8C6F38))),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                        color: WebeyColors.darkEspresso.withAlpha(158),
                        fontSize: 10.5),
                    children: [
                      const TextSpan(text: 'Tüm kullanıcılar için geçerlidir · '),
                      TextSpan(text: 'TR',
                          style: TextStyle(
                              color: WebeyColors.darkEspresso.withAlpha(200),
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Doc models ────────────────────────────────────────────────────────────────

class _DocItem {
  const _DocItem({
    required this.id,
    required this.title,
    required this.summary,
    this.quote,
    required this.updated,
    required this.version,
  });
  final String id, title, summary, updated, version;
  final String? quote;
}

// ── Doc Card ──────────────────────────────────────────────────────────────────

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.doc,
    required this.isOpen,
    required this.onTap,
  });
  final _DocItem doc;
  final bool isOpen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOpen
                ? WebeyColors.primaryGold.withAlpha(80)
                : WebeyColors.borderSand,
          ),
          boxShadow: [
            BoxShadow(
              color: WebeyColors.darkEspresso.withAlpha(15),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gold left rail
            Container(
              width: 2,
              height: null,
              constraints: const BoxConstraints(minHeight: 60),
              decoration: BoxDecoration(
                color: isOpen
                    ? WebeyColors.primaryGold
                    : WebeyColors.primaryGold.withAlpha(80),
                borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(15)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            doc.title,
                            style: const TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 15.5,
                                fontFamily: 'Georgia',
                                fontWeight: FontWeight.w500,
                                height: 1.15),
                          ),
                        ),
                        const SizedBox(width: 10),
                        AnimatedRotation(
                          duration: const Duration(milliseconds: 200),
                          turns: isOpen ? 0.25 : 0,
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: isOpen
                                ? const Color(0xFF8C6F38)
                                : WebeyColors.darkEspresso.withAlpha(100),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(doc.summary,
                        style: TextStyle(
                            color: WebeyColors.darkEspresso.withAlpha(158),
                            fontSize: 11,
                            height: 1.4)),
                    // Expanded content
                    if (isOpen && doc.quote != null) ...[
                      const SizedBox(height: 11),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: WebeyColors.warmCream,
                          borderRadius: BorderRadius.circular(10),
                          border: Border(
                            left: BorderSide(
                                color: const Color(0xFF8C6F38), width: 2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '"${doc.quote}"',
                              style: TextStyle(
                                  color: WebeyColors.darkEspresso,
                                  fontSize: 12.5,
                                  fontFamily: 'Georgia',
                                  fontStyle: FontStyle.italic,
                                  height: 1.5),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Divider(
                                  height: 1, color: WebeyColors.borderSand),
                            ),
                            const SizedBox(height: 8),
                            Row(children: [
                              Text(
                                'Güncellendi · ${doc.updated}',
                                style: TextStyle(
                                    color: WebeyColors.darkEspresso.withAlpha(100),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5),
                              ),
                              Container(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 10),
                                width: 3, height: 3,
                                decoration: BoxDecoration(
                                  color: WebeyColors.darkEspresso.withAlpha(50),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Text(doc.version,
                                  style: TextStyle(
                                      color: WebeyColors.darkEspresso.withAlpha(100),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5)),
                            ]),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 9),
                    Row(children: [
                      Text('DETAYLARI GÖR',
                          style: TextStyle(
                              color: const Color(0xFF8C6F38),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8)),
                      const SizedBox(width: 5),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 11, color: Color(0xFF8C6F38)),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Contact Card ──────────────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [WebeyColors.warmCream, Color(0xFFEADFCF)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Stack(
          children: [
            // Gold glow top-right
            Positioned(
              right: -30, top: -30,
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      WebeyColors.primaryGold.withAlpha(56),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(width: 14, height: 1,
                      color: WebeyColors.primaryGold),
                  const SizedBox(width: 6),
                  Text('SORULARINIZ İÇİN',
                      style: TextStyle(
                          color: const Color(0xFF8C6F38),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6)),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.mail_outline_rounded, size: 15,
                      color: Color(0xFF8C6F38)),
                  const SizedBox(width: 7),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                          color: WebeyColors.darkEspresso, fontSize: 18,
                          fontFamily: 'Georgia', fontWeight: FontWeight.w500,
                          height: 1),
                      children: [
                        TextSpan(text: 'legal'),
                        TextSpan(
                            text: '@',
                            style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Color(0xFF8C6F38))),
                        TextSpan(text: 'webey.com.tr'),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 11),
                Divider(
                    height: 1,
                    color: WebeyColors.darkEspresso.withAlpha(25),
                    indent: 0,
                    endIndent: 0),
                const SizedBox(height: 11),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_outlined, size: 14,
                        color: Color(0xFF8C6F38)),
                    const SizedBox(width: 9),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                              color: WebeyColors.darkEspresso.withAlpha(158),
                              fontSize: 11, height: 1.4),
                          children: const [
                            TextSpan(text: 'Verileriniz '),
                            TextSpan(
                                text: 'Webey güvencesiyle',
                                style: TextStyle(
                                    color: WebeyColors.darkEspresso,
                                    fontWeight: FontWeight.w600)),
                            TextSpan(
                                text:
                                    ' korunmaktadır. Veri silme ve düzenleme taleplerinizi 30 gün içinde yanıtlıyoruz.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}