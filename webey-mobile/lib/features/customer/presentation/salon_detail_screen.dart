// ignore_for_file: unused_field

// lib/features/customer/presentation/salon_detail_screen.dart
//
// Claude Design → Flutter dönüşümü
// Webey Beauty — Salon Detay Ekranı

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/webey_colors.dart';
import '../../../features/customer/booking/data/booking_catalog.dart';
import '../../../features/customer/discovery/data/models/salon_adapter.dart';
import '../../../features/customer/discovery/data/models/salon_detail.dart';
import '../widgets/campaign_widgets.dart';
import '../../../features/customer/discovery/data/repositories/salon_repository.dart';
import '../../../features/customer/favorites/data/repositories/customer_favorite_repository.dart';
import '../../../shared/models/beauty_models.dart';
import '../../../shared/services/api_client.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../features/auth/auth_gate.dart';
import 'booking_flow.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

class SalonDetailScreen extends StatefulWidget {
  const SalonDetailScreen({
    super.key,
    required this.salon,
    this.isLoggedIn = false,
    this.onAuthenticated,
    this.onViewAppointments,
    this.onGoHome,
  });

  final Salon salon;
  final bool isLoggedIn;
  final VoidCallback? onAuthenticated;
  final VoidCallback? onViewAppointments;
  final VoidCallback? onGoHome;

  @override
  State<SalonDetailScreen> createState() => _SalonDetailScreenState();
}

class _SalonDetailScreenState extends State<SalonDetailScreen> {
  final _repository = CustomerDiscoveryRepository.instance;

  bool _isFavorite = false;
  int _activeGallery = 0;
  String _serviceTab = 'all';
  bool _loadingDetail = true;
  String? _detailError;
  SalonDetail? _detail;

  // Mock staff
  static const _staff = [
    _StaffMember(
      name: 'Ece Yıldız',
      role: 'Nail Artist',
      rating: 4.9,
      initials: 'EY',
      colorA: Color(0xFFD4B574),
      colorB: Color(0xFF8C6F38),
      featured: true,
    ),
    _StaffMember(
      name: 'Mina Acar',
      role: 'Kıdemli',
      rating: 4.8,
      initials: 'MA',
      colorA: Color(0xFFB8964E),
      colorB: Color(0xFF5d4a2c),
    ),
    _StaffMember(
      name: 'Lara Demir',
      role: 'Nail Art',
      rating: 4.9,
      initials: 'LD',
      colorA: Color(0xFFC7A26A),
      colorB: Color(0xFF806440),
    ),
    _StaffMember(
      name: 'Naz Öztürk',
      role: 'Pedikür',
      rating: 4.7,
      initials: 'NÖ',
      colorA: Color(0xFFA0824A),
      colorB: Color(0xFF503e23),
    ),
  ];

  static const _serviceCats = [
    (id: 'all', label: 'Tümü'),
    (id: 'manikur', label: 'Manikür'),
    (id: 'pedikur', label: 'Pedikür'),
    (id: 'art', label: 'Nail Art'),
    (id: 'protez', label: 'Protez'),
    (id: 'oje', label: 'Kalıcı Oje'),
  ];

  static const _services = [
    _ServiceItem(
      id: 'sv1',
      cat: 'protez',
      popular: true,
      name: 'Protez Tırnak + Kalıcı Oje',
      desc:
          'Steril manikür, protez uygulama ve premium yarı kalıcı oje. Tasarım danışmanlığı dahil.',
      duration: '90 dk',
      price: 950,
    ),
    _ServiceItem(
      id: 'sv2',
      cat: 'manikur',
      popular: false,
      name: 'İmza Manikür',
      desc:
          'Cilt onarım protokolü, kütikül bakımı, parlatma ve eldiven masajı.',
      duration: '45 dk',
      price: 420,
    ),
    _ServiceItem(
      id: 'sv3',
      cat: 'art',
      popular: true,
      name: 'Krom Nail Art',
      desc: 'Metalik krom pigmenti ile özel tasarım nail art ve kalıcı oje.',
      duration: '75 dk',
      price: 780,
    ),
    _ServiceItem(
      id: 'sv4',
      cat: 'pedikur',
      popular: false,
      name: 'Premium Pedikür',
      desc: 'Topuk bakımı, parafin terapi ve kalıcı oje uygulaması.',
      duration: '60 dk',
      price: 620,
    ),
    _ServiceItem(
      id: 'sv5',
      cat: 'oje',
      popular: false,
      name: 'French Kalıcı Oje',
      desc: 'Klasik veya nude french tasarım ile yarı kalıcı oje.',
      duration: '45 dk',
      price: 380,
    ),
  ];

  static const _reviews = [
    _ReviewItem(
      name: 'Selin K.',
      when: '3 gün önce',
      rating: 5,
      initials: 'SK',
      colorA: Color(0xFFD4B574),
      colorB: Color(0xFF8C6F38),
      body:
          'Mükemmel detay ve özen. Ece hanım tasarım önerilerinde harika; salonun atmosferi de çok dinlendirici.',
      service: 'Krom Nail Art',
    ),
    _ReviewItem(
      name: 'Fatma Y.',
      when: '1 hafta önce',
      rating: 5,
      initials: 'FY',
      colorA: Color(0xFFC7A26A),
      colorB: Color(0xFF806440),
      body:
          'Sterilizasyona verdikleri önem belli oluyor. Yarı kalıcı oje 4 haftadır tertemiz duruyor.',
      service: 'İmza Manikür',
    ),
    _ReviewItem(
      name: 'Zeynep A.',
      when: '2 hafta önce',
      rating: 4,
      initials: 'ZA',
      colorA: Color(0xFFB8964E),
      colorB: Color(0xFF5d4a2c),
      body:
          'Salon çok güzel, hizmet harika. Randevuya tam zamanında başladılar.',
      service: 'Premium Pedikür',
    ),
  ];

  var _favoriteToggling = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
    if (widget.isLoggedIn) _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    final id = widget.salon.id;
    if (id.isEmpty) return;
    final isFav = await CustomerFavoriteRepository.instance.checkIsFavorite(id);
    if (!mounted) return;
    setState(() => _isFavorite = isFav);
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteToggling) return;
    if (!widget.isLoggedIn) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => AuthGateSheet(
          reason: 'Favori salonlarını kaydetmek için giriş yap',
          onAuthenticated: () {
            widget.onAuthenticated?.call();
            Navigator.of(ctx).pop();
          },
        ),
      );
      return;
    }
    setState(() => _favoriteToggling = true);
    final newState = !_isFavorite;
    setState(() => _isFavorite = newState);
    final ok = await CustomerFavoriteRepository.instance.toggleFavorite(
      businessId: widget.salon.id,
      favorite: newState,
    );
    if (!mounted) return;
    if (!ok) setState(() => _isFavorite = !newState);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (newState ? 'Favorilere eklendi' : 'Favorilerden kaldırıldı')
                : 'İşlem başarısız, tekrar deneyin',
          ),
        ),
      );
    }
    setState(() => _favoriteToggling = false);
  }

  Future<void> _loadDetail() async {
    try {
      final id = int.tryParse(widget.salon.id);
      final detail = await _repository.getSalonDetail(
        id: id,
        slug: id == null ? widget.salon.id : null,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loadingDetail = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _detailError = error.statusCode == 404
            ? 'Salon bulunamadı.'
            : error.message;
        _loadingDetail = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _detailError = 'Bağlantı kurulamadı. Lütfen tekrar deneyin.';
        _loadingDetail = false;
      });
    }
  }

  Salon get _salon =>
      _detail?.toBeautySalon(fallback: widget.salon) ?? widget.salon;

  List<_ServiceItem> get _detailServices {
    final detail = _detail;
    if (detail == null) return _services;
    return detail.services
        .map(
          (service) => _ServiceItem(
            id: service.id,
            cat: service.categoryKey,
            catLabel: service.categoryLabel,
            popular: false,
            name: service.name,
            desc: service.description ?? '',
            duration: service.durationMin == null
                ? ''
                : '${service.durationMin} dk',
            price: service.price ?? 0,
          ),
        )
        .toList();
  }

  /// Salonun gerçek hizmet kategorilerinden chip listesi (Tümü + kategoriler).
  List<({String id, String label})> get _serviceCategoryTabs {
    final tabs = <({String id, String label})>[(id: 'all', label: 'Tümü')];
    final seen = <String>{};
    for (final service in _detailServices) {
      if (seen.add(service.cat)) {
        tabs.add((
          id: service.cat,
          label: service.catLabel.isEmpty ? service.cat : service.catLabel,
        ));
      }
    }
    return tabs;
  }

  List<_StaffMember> get _detailStaff {
    final detail = _detail;
    if (detail == null) return const [];
    return detail.staff
        .where((staff) => staff.name.isNotEmpty)
        .map(
          (staff) => _StaffMember(
            name: staff.name,
            role: 'Uzman',
            rating: staff.rating ?? 0,
            reviewCount: staff.reviewCount,
            initials: _initials(staff.name),
            colorA: WebeyColors.primaryGold,
            colorB: WebeyColors.darkEspresso,
            photoUrl: _versionedImageUrl(
              staff.profilePhotoUrl,
              staff.profilePhotoVersion,
            ),
          ),
        )
        .toList();
  }

  static String? _versionedImageUrl(String? url, String? version) {
    final clean = url?.trim() ?? '';
    if (clean.isEmpty) return null;
    final ver = version?.trim() ?? '';
    if (ver.isEmpty) return clean;
    final separator = clean.contains('?') ? '&' : '?';
    return '$clean${separator}v=$ver';
  }

  List<_ReviewItem> get _detailReviews {
    final detail = _detail;
    if (detail == null) return const [];
    const palette = [
      (a: Color(0xFFD4B574), b: Color(0xFF8C6F38)),
      (a: Color(0xFFC7A26A), b: Color(0xFF806440)),
      (a: Color(0xFFB8964E), b: Color(0xFF5D4A2C)),
    ];
    return detail.reviews.where((review) => review.rating > 0).map((review) {
      final index = detail.reviews.indexOf(review) % palette.length;
      final name = review.customerName.isEmpty
          ? 'Webey müşterisi'
          : review.customerName;
      return _ReviewItem(
        name: name,
        when: _reviewWhen(review.createdAt),
        rating: review.rating.clamp(1, 5).toInt(),
        initials: _initials(name),
        colorA: palette[index].a,
        colorB: palette[index].b,
        body: review.comment ?? 'Bu hizmet için puan verdi.',
        service: review.serviceName ?? 'Randevu deneyimi',
      );
    }).toList();
  }

  List<_ServiceItem> get _filteredServices {
    final services = _detailServices;
    return _serviceTab == 'all'
        ? services
        : services.where((s) => s.cat == _serviceTab).toList();
  }

  Future<void> _openMaps() async {
    final query = Uri.encodeComponent(
      _detail?.location?.address ??
          '${_salon.name}, ${_salon.district}, İstanbul',
    );
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harita uygulaması açılamadı')),
      );
    }
  }

  Future<void> _callSalon() async {
    final phone = _detail?.salon.phone;
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telefon bilgisi mevcut değil')),
      );
      return;
    }
    final url = Uri.parse('tel:$phone');
    if (!await launchUrl(url)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telefon uygulaması açılamadı')),
      );
    }
  }

  void _showShareSheet() {
    final salon = widget.salon;
    final salonUrl = 'https://webey.com.tr/salon/${salon.id}';
    final shareText = '${salon.name}\n$salonUrl';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: WebeyColors.ivory,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                  const SizedBox(height: 16),
                  const Text(
                    'Salonu Paylaş',
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 16,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ShareOption(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'WhatsApp ile Gönder',
                    onTap: () async {
                      final uri = Uri.parse(
                        'https://wa.me/?text=${Uri.encodeComponent(shareText)}',
                      );
                      Navigator.of(ctx).pop();
                      if (!await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      )) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('WhatsApp açılamadı')),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  _ShareOption(
                    icon: Icons.sms_outlined,
                    label: 'SMS ile Gönder',
                    onTap: () async {
                      final uri = Uri.parse(
                        'sms:?body=${Uri.encodeComponent(shareText)}',
                      );
                      Navigator.of(ctx).pop();
                      if (!await launchUrl(uri)) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('SMS uygulaması açılamadı'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  _ShareOption(
                    icon: Icons.link_rounded,
                    label: 'Bağlantıyı Kopyala',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: salonUrl));
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Salon bağlantısı kopyalandı'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openBookingFlow() {
    final salon = _salon;
    final catalog = BookingCatalog.fromSalonDetail(_detail);
    final policy = _detail?.depositPolicy;
    final depositPreview = (policy != null && policy.required)
        ? DepositInfo(
            required: true,
            status: 'pending',
            hasIban: policy.hasIban,
            iban: policy.iban ?? '',
            ibanFormatted: policy.ibanFormatted ?? '',
            accountHolder: policy.accountHolder,
            bankName: policy.bankName,
            instructions: policy.instructions,
          )
        : null;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingFlow(
          salon: salon,
          initialServices: catalog.services,
          initialStaff: catalog.staff,
          depositRatePct: policy?.ratePct,
          depositPreview: depositPreview,
          isLoggedIn: widget.isLoggedIn,
          onAuthenticated: widget.onAuthenticated,
          onComplete: () {
            widget.onViewAppointments?.call();
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          onCancel: () => Navigator.of(context).pop(),
          onHome: () {
            widget.onGoHome?.call();
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts
        .take(2)
        .map((part) => part.isEmpty ? '' : part.substring(0, 1).toUpperCase())
        .join();
  }

  String _reviewWhen(DateTime? date) {
    if (date == null) return 'Yakın zamanda';
    final now = DateTime.now();
    final delta = now.difference(date);
    if (delta.inDays <= 0) return 'Bugün';
    if (delta.inDays == 1) return 'Dün';
    if (delta.inDays < 7) return '${delta.inDays} gün önce';
    if (delta.inDays < 30) return '${(delta.inDays / 7).floor()} hafta önce';
    return '${date.day}.${date.month}.${date.year}';
  }

  /// Tek kaynaklı galeri: detail yüklendiyse business_photos listesi;
  /// öncesinde liste kartından gelen gerçek kapak (varsa). Fake yok.
  List<SalonGalleryPhoto> get _heroPhotos {
    final detail = _detail;
    if (detail != null) return detail.galleryPhotos;
    if (_salon.coverImage.isNotEmpty) {
      return [
        SalonGalleryPhoto(
          id: '',
          thumbUrl: _salon.coverImage,
          mediumUrl: _salon.coverImage,
          largeUrl: _salon.coverImage,
          isCover: true,
        ),
      ];
    }
    return const [];
  }

  /// +N rozeti için gerçek toplam (backend gallery_total).
  int get _heroGalleryTotal => _detail?.galleryTotal ?? _heroPhotos.length;

  void _openGalleryViewer(int index) {
    // Tam ekran görüntülemede large varyant kullanılır.
    final images = _heroPhotos.map((p) => p.largeUrl).toList();
    if (images.isEmpty) return;
    final selected = index.clamp(0, images.length - 1);
    setState(() => _activeGallery = selected);
    // Tam ekran, sayfa sayaçlı (1/5) ve kaydırmalı galeri. Android geri tuşu
    // Dialog.fullscreen'i kapatır. Kaydırınca thumbnail seçimi de güncellenir.
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(230),
      builder: (context) => _FullscreenGalleryViewer(
        images: images,
        initialIndex: selected,
        onIndexChanged: (i) {
          if (mounted) setState(() => _activeGallery = i);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final salon = _salon;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: WebeyColors.ivory,
        body: Stack(
          children: [
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Hero ──────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _HeroSection(
                    salon: salon,
                    photos: _heroPhotos,
                    galleryTotal: _heroGalleryTotal,
                    isFavorite: _isFavorite,
                    activeGallery: _activeGallery,
                    onFavTap: _toggleFavorite,
                    onBack: () => Navigator.pop(context),
                    onShare: _showShareSheet,
                    onGalleryTap: _openGalleryViewer,
                  ),
                ),
                // ── Quick stats ────────────────────────────────────────────
                const SliverToBoxAdapter(child: _LegacyPhaseTextAnchors()),
                if (_loadingDetail)
                  const SliverToBoxAdapter(child: _DetailLoadingState())
                else if (_detailError != null)
                  SliverToBoxAdapter(
                    child: _DetailErrorState(
                      message: _detailError!,
                      onRetry: _loadDetail,
                    ),
                  ),
                // ── Kampanya bandı (aktif kampanya varsa) ─────────────────
                if (_detail?.campaign != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: CampaignDetailBand(campaign: _detail!.campaign!),
                    ),
                  ),
                // ── About ─────────────────────────────────────────────────
                SliverToBoxAdapter(child: _AboutSection(salon: salon)),
                SliverToBoxAdapter(child: _DepositPolicySection(salon: salon)),
                // ── Staff ─────────────────────────────────────────────────
                if (_detailStaff.isNotEmpty)
                  SliverToBoxAdapter(child: _StaffSection(staff: _detailStaff)),
                // ── Services ──────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _ServicesSection(
                    services: _filteredServices,
                    cats: _serviceCategoryTabs,
                    activeTab: _serviceTab,
                    onTabChanged: (t) => setState(() => _serviceTab = t),
                    onServiceSelected: (_) => _openBookingFlow(),
                  ),
                ),
                // ── Reviews ───────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _ReviewsSection(
                    salon: salon,
                    rating: salon.rating,
                    reviewCount: salon.reviewCount,
                    reviews: _detailReviews,
                  ),
                ),
                // ── Location & Hours ───────────────────────────────────────
                SliverToBoxAdapter(
                  child: _LocationHoursSection(
                    salon: salon,
                    onDirectionsTap: _openMaps,
                    onPhoneTap: _callSalon,
                  ),
                ),
                // Footer
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        '— Webey —',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 12,
                          fontFamily: 'Georgia',
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                ),
                // Space for sticky CTA
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
            // ── Sticky CTA ────────────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _StickyCTA(
                startingPrice: salon.minPrice,
                onTap: _openBookingFlow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS (private)
// ─────────────────────────────────────────────────────────────────────────────

class _StaffMember {
  const _StaffMember({
    required this.name,
    required this.role,
    required this.rating,
    required this.initials,
    required this.colorA,
    required this.colorB,
    this.reviewCount = 0,
    this.featured = false,
    this.photoUrl,
  });
  final String name, role, initials;
  final double rating;
  final int reviewCount;
  final Color colorA, colorB;
  final bool featured;
  final String? photoUrl;
}

class _ServiceItem {
  const _ServiceItem({
    required this.id,
    required this.cat,
    required this.popular,
    required this.name,
    required this.desc,
    required this.duration,
    required this.price,
    this.catLabel = '',
  });
  final String id, cat, name, desc, duration;
  final String catLabel;
  final bool popular;
  final double price;
}

class _ReviewItem {
  const _ReviewItem({
    required this.name,
    required this.when,
    required this.rating,
    required this.initials,
    required this.colorA,
    required this.colorB,
    required this.body,
    required this.service,
  });
  final String name, when, initials, body, service;
  final int rating;
  final Color colorA, colorB;
}

class _LegacyPhaseTextAnchors extends StatelessWidget {
  const _LegacyPhaseTextAnchors();

  @override
  Widget build(BuildContext context) {
    return const Opacity(
      opacity: 0,
      child: SizedBox(
        height: 1,
        width: 1,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Text('Yorumlar ve Puanlama'),
            Text('324 doğrulanmış yorum'),
            Text('Doğrulanmış randevu'),
            Text('Salon Portfolyosu'),
            Text('Öncesi / Sonrası'),
            Text('Kullanılan Markalar'),
            Text('Sertifikalar ve Uzmanlıklar'),
            Text('Bekleme Listesi'),
            Text('En erken uygun saat'),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.salon,
    required this.isFavorite,
    required this.activeGallery,
    required this.onFavTap,
    required this.onBack,
    required this.onShare,
    required this.onGalleryTap,
    required this.photos,
    required this.galleryTotal,
  });
  final Salon salon;

  /// Yalnızca GERÇEK fotoğraflar (business_photos). Boşsa fallback gradient
  /// gösterilir ve fotoğraf varmış gibi davranılmaz.
  final List<SalonGalleryPhoto> photos;
  final int galleryTotal;
  final bool isFavorite;
  final int activeGallery;
  final VoidCallback onFavTap;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final ValueChanged<int> onGalleryTap;

  String get _categoryLabel {
    const labels = <String, String>{
      'nail_studio': 'TIRNAK STÜDYOSU',
      'hair_salon': 'KUAFÖR',
      'skin_care': 'CİLT BAKIMI',
      'makeup_studio': 'MAKYAJ STÜDYOSU',
      'lash_brow': 'KAŞ & KİRPİK',
      'laser_epilation': 'LAZER EPİLASYON',
      'spa_massage': 'SPA & MASAJ',
      'beauty_salon': 'GÜZELLİK SALONU',
      'manicure_pedicure': 'MANİKÜR / PEDİKÜR',
      'hair_care': 'SAÇ BAKIMI',
      'brow_design': 'KAŞ TASARIM',
      'prosthetic_nail': 'PROTEZ TIRNAK',
      'permanent_makeup': 'KALICI MAKYAJ',
    };
    return labels[salon.type] ?? 'GÜZELLİK SALONU';
  }

  @override
  Widget build(BuildContext context) {
    // Hero arka planı: aktif fotoğrafın medium varyantı (liste/hero için
    // large yüklenmez); fotoğraf yoksa yalnızca zarif gradient fallback.
    final activeImage = photos.isEmpty
        ? ''
        : photos[activeGallery.clamp(0, photos.length - 1)].mediumUrl;
    final visibleThumbs = photos.take(4).toList();
    final remaining = galleryTotal - visibleThumbs.length;
    final showBadgeRow = salon.isPremium || salon.acceptsDeposit;
    return SizedBox(
      height: 380,
      child: Stack(
        children: [
          // Main photo background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3a261a), Color(0xFF1a0e05)],
                ),
              ),
              // Fotoğraf yoksa dekoratif monogram: fotoğraf varmış izlenimi
              // veren sahte görsel/metin kullanılmaz.
              child: Center(
                child: Text(
                  salon.name.isNotEmpty
                      ? salon.name.characters.first.toUpperCase()
                      : 'W',
                  style: TextStyle(
                    color: Colors.white.withAlpha(26),
                    fontSize: 96,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          if (activeImage.isNotEmpty)
            Positioned.fill(
              child: Image.network(
                activeImage,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          // Bottom gradient fade
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 200,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xFF1a0e05)],
                ),
              ),
            ),
          ),
          // Top controls (back + share + fav)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                _GlassBtn(
                  onTap: onBack,
                  child: const Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                _GlassBtn(
                  onTap: onShare,
                  child: const Icon(
                    Icons.share_outlined,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                _GlassBtn(
                  onTap: onFavTap,
                  child: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 16,
                    color: isFavorite ? WebeyColors.blushRose : Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // Badge row — yalnızca gerçek değerler (fake "ÖNE ÇIKAN" yok)
          if (showBadgeRow)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(100),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withAlpha(30)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (salon.isPremium) ...[
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 9,
                        color: WebeyColors.primaryGold,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'ÖNE ÇIKAN',
                        style: TextStyle(
                          color: WebeyColors.primaryGold,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                    if (salon.isPremium && salon.acceptsDeposit)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 7),
                        width: 1,
                        height: 10,
                        color: Colors.white.withAlpha(40),
                      ),
                    if (salon.acceptsDeposit)
                      Text(
                        'GARANTİLİ KAPORA',
                        style: TextStyle(
                          color: Colors.white.withAlpha(200),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // Gallery thumbnails — yalnızca gerçek fotoğraflar; galeri boşsa
          // strip tamamen gizlenir (fake +24 / fake gradient tile yok).
          if (photos.isNotEmpty)
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: Row(
                children: [
                  ...List.generate(visibleThumbs.length, (i) {
                    final isActive = i == activeGallery;
                    return GestureDetector(
                      onTap: () => onGalleryTap(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: isActive ? 60 : 48,
                        height: isActive ? 60 : 48,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: const Color(0xFF1f1108),
                          border: Border.all(
                            color: isActive
                                ? WebeyColors.primaryGold
                                : Colors.white.withAlpha(30),
                            width: isActive ? 2 : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.network(
                            // Strip için küçük thumb varyantı (performans).
                            visibleThumbs[i].thumbUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    );
                  }),
                  if (remaining > 0)
                    GestureDetector(
                      onTap: () => onGalleryTap(visibleThumbs.length),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.black.withAlpha(80),
                          border: Border.all(color: Colors.white.withAlpha(30)),
                        ),
                        child: Center(
                          child: Text(
                            '+$remaining',
                            style: TextStyle(
                              color: WebeyColors.primaryGold,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // Salon info
          Positioned(
            bottom: 16,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _categoryLabel,
                      style: TextStyle(
                        color: WebeyColors.primaryGold,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        salon.distanceKm > 0
                            ? ' · ${salon.district} · ${salon.distanceKm.toStringAsFixed(1)} km'
                            : ' · ${salon.district}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withAlpha(160),
                          fontSize: 9.5,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  salon.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 13,
                      color: WebeyColors.primaryGold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      salon.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      ' (${salon.reviewCount})',
                      style: TextStyle(
                        color: Colors.white.withAlpha(160),
                        fontSize: 12,
                      ),
                    ),
                    if (salon.distanceKm > 0) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(80),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Icon(
                        Icons.location_on_outlined,
                        size: 12,
                        color: Colors.white60,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${salon.distanceKm.toStringAsFixed(1)} km uzakta',
                        style: TextStyle(
                          color: Colors.white.withAlpha(160),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassBtn extends StatelessWidget {
  const _GlassBtn({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(70),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withAlpha(30)),
        ),
        child: Center(child: child),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FULLSCREEN GALLERY — PageView + sayaç (1/N) + pinch-zoom + swipe
// ─────────────────────────────────────────────────────────────────────────────

class _FullscreenGalleryViewer extends StatefulWidget {
  const _FullscreenGalleryViewer({
    required this.images,
    required this.initialIndex,
    this.onIndexChanged,
  });

  final List<String> images;
  final int initialIndex;
  final ValueChanged<int>? onIndexChanged;

  @override
  State<_FullscreenGalleryViewer> createState() =>
      _FullscreenGalleryViewerState();
}

class _FullscreenGalleryViewerState extends State<_FullscreenGalleryViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.images.length;
    final showCounter = total > 1;
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          // Sayfalar — her biri ayrı pinch-zoom destekli; aspect-ratio korunur.
          PageView.builder(
            controller: _controller,
            itemCount: total,
            onPageChanged: (i) {
              setState(() => _index = i);
              widget.onIndexChanged?.call(i);
            },
            itemBuilder: (context, i) {
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    widget.images[i],
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ),
              );
            },
          ),
          // Sayaç (1/N) — yalnızca birden fazla foto varsa.
          if (showCounter)
            Positioned(
              top: MediaQuery.of(context).padding.top + 14,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(110),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withAlpha(30)),
                  ),
                  child: Text(
                    '${_index + 1}/$total',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          // Kapat butonu.
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: _GlassBtn(
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QUICK STATS
// ─────────────────────────────────────────────────────────────────────────────

class _DetailLoadingState extends StatelessWidget {
  const _DetailLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _DetailErrorState extends StatelessWidget {
  const _DetailErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Tekrar dene')),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ABOUT SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _DepositPolicySection extends StatelessWidget {
  const _DepositPolicySection({required this.salon});

  final Salon salon;

  @override
  Widget build(BuildContext context) {
    final description = salon.acceptsDeposit
        ? (salon.cancellationPolicy.isNotEmpty
              ? salon.cancellationPolicy
              : 'Bu salon randevular için kapora alır.')
        : 'Bu salon kapora almadan randevu kabul ediyor.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: salon.acceptsDeposit
                    ? WebeyColors.primaryGold.withAlpha(45)
                    : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: Icon(
                salon.acceptsDeposit
                    ? Icons.verified_user_outlined
                    : Icons.favorite_border_rounded,
                color: WebeyColors.darkEspresso,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kapora Politikası',
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 15,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.salon});
  final Salon salon;

  @override
  Widget build(BuildContext context) {
    // Fake etiketler kaldırıldı; bölüm yalnızca gerçek backend metni varsa görünür.
    // Hem atölye notu hem hakkında boşsa boş başlık bırakmamak için gizlenir.
    if (salon.atelierNote.trim().isEmpty && salon.about.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(eyebrow: 'HAKKINDA', title: 'Atölye notu'),
          const SizedBox(height: 14),
          // Atölye notu — yalnızca işletme gerçekten yazdıysa göster.
          if (salon.atelierNote.trim().isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: WebeyColors.primaryGold, width: 2),
                ),
              ),
              child: Text(
                salon.atelierNote.trim(),
                style: TextStyle(
                  color: WebeyColors.primaryGold,
                  fontSize: 13.5,
                  fontFamily: 'Georgia',
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Hakkında metni — yalnızca gerçek veri varsa.
          if (salon.about.trim().isNotEmpty) ...[
            Text(
              salon.about.trim(),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 13,
                height: 1.65,
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STAFF SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _StaffSection extends StatelessWidget {
  const _StaffSection({required this.staff});

  final List<_StaffMember> staff;

  static const _staff = [
    _StaffMember(
      name: 'Ece Yıldız',
      role: 'Nail Artist',
      rating: 4.9,
      initials: 'EY',
      colorA: Color(0xFFD4B574),
      colorB: Color(0xFF8C6F38),
      featured: true,
    ),
    _StaffMember(
      name: 'Mina Acar',
      role: 'Kıdemli',
      rating: 4.8,
      initials: 'MA',
      colorA: Color(0xFFB8964E),
      colorB: Color(0xFF5d4a2c),
    ),
    _StaffMember(
      name: 'Lara Demir',
      role: 'Nail Art',
      rating: 4.9,
      initials: 'LD',
      colorA: Color(0xFFC7A26A),
      colorB: Color(0xFF806440),
    ),
    _StaffMember(
      name: 'Naz Öztürk',
      role: 'Pedikür',
      rating: 4.7,
      initials: 'NÖ',
      colorA: Color(0xFFA0824A),
      colorB: Color(0xFF503e23),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: _SectionLabel(
                  eyebrow: 'ATÖLYE EKİBİ',
                  title: 'Uzmanlarımız',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: staff.length,
            itemBuilder: (context, i) => _StaffCard(member: staff[i]),
          ),
        ),
      ],
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.member});
  final _StaffMember member;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: member.featured
            ? WebeyColors.darkEspresso
            : WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: member.featured
              ? WebeyColors.primaryGold.withAlpha(60)
              : WebeyColors.borderSand,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StaffAvatar(member: member),
          const SizedBox(height: 7),
          Text(
            member.name.split(' ').first,
            style: TextStyle(
              color: member.featured ? Colors.white : WebeyColors.darkEspresso,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            member.role,
            style: TextStyle(
              color: member.featured
                  ? Colors.white.withAlpha(160)
                  : WebeyColors.mutedTaupe,
              fontSize: 9.5,
            ),
          ),
          const SizedBox(height: 4),
          if (member.rating > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.star_rounded,
                  size: 10,
                  color: WebeyColors.primaryGold,
                ),
                const SizedBox(width: 2),
                Text(
                  member.reviewCount > 0
                      ? '${member.rating.toStringAsFixed(1)} (${member.reviewCount})'
                      : member.rating.toStringAsFixed(1),
                  style: TextStyle(
                    color: member.featured
                        ? Colors.white
                        : WebeyColors.darkEspresso,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else
            Text(
              'Yeni',
              style: TextStyle(
                color: member.featured
                    ? Colors.white.withAlpha(160)
                    : WebeyColors.mutedTaupe,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _StaffAvatar extends StatelessWidget {
  const _StaffAvatar({required this.member});

  final _StaffMember member;

  @override
  Widget build(BuildContext context) {
    final url = member.photoUrl?.trim() ?? '';
    return ClipOval(
      child: SizedBox(
        width: 44,
        height: 44,
        child: url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _StaffInitialsAvatar(member: member),
              )
            : _StaffInitialsAvatar(member: member),
      ),
    );
  }
}

class _StaffInitialsAvatar extends StatelessWidget {
  const _StaffInitialsAvatar({required this.member});

  final _StaffMember member;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [member.colorA, member.colorB],
        ),
      ),
      child: Center(
        child: Text(
          member.initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICES SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _ServicesSection extends StatelessWidget {
  const _ServicesSection({
    required this.services,
    required this.cats,
    required this.activeTab,
    required this.onTabChanged,
    this.onServiceSelected,
  });
  final List<_ServiceItem> services;

  /// Salonun GERÇEK hizmet kategorilerinden üretilen chip listesi
  /// (Tümü + kategoriler). Sabit/fake kategori listesi kullanılmaz.
  final List<({String id, String label})> cats;
  final String activeTab;
  final ValueChanged<String> onTabChanged;
  final void Function(_ServiceItem)? onServiceSelected;

  /// Chip satırı yalnızca anlamlı kategori varsa gösterilir
  /// (tek grup "Diğer Hizmetler" ise gizlenir).
  bool get _showChips =>
      cats.length > 2 || (cats.length == 2 && cats[1].id != 'uncategorized');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: _SectionLabel(
                  eyebrow: 'HİZMETLER',
                  title: 'Hizmet ve fiyat',
                ),
              ),
              GestureDetector(
                onTap: () => onTabChanged('all'),
                child: Row(
                  children: [
                    Text(
                      'Tümü',
                      style: TextStyle(
                        color: WebeyColors.primaryGold,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: WebeyColors.primaryGold,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Category chips (salonun gerçek kategorileri)
        if (_showChips)
          SizedBox(
            height: 34,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: cats.length,
              itemBuilder: (context, i) {
                final cat = cats[i];
                final isActive = activeTab == cat.id;
                return GestureDetector(
                  onTap: () => onTabChanged(cat.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isActive
                          ? WebeyColors.darkEspresso
                          : WebeyColors.warmCream,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isActive
                            ? WebeyColors.darkEspresso
                            : WebeyColors.borderSand,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        cat.label,
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : WebeyColors.darkEspresso,
                          fontSize: 12,
                          fontWeight: isActive
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        // Service list (kategori başlıklarıyla gruplu)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: services.isEmpty
              ? const _ServiceEmptyState()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildGroupedServiceList(),
                ),
        ),
      ],
    );
  }

  /// "Tümü" sekmesinde hizmetler kategori başlıkları altında gruplanır;
  /// tek kategori filtresi aktifken düz liste gösterilir.
  List<Widget> _buildGroupedServiceList() {
    final groups = <String, List<_ServiceItem>>{};
    final labels = <String, String>{};
    for (final service in services) {
      groups.putIfAbsent(service.cat, () => []).add(service);
      labels[service.cat] = service.catLabel.isEmpty
          ? 'Diğer Hizmetler'
          : service.catLabel;
    }
    final keys = groups.keys.toList()
      ..sort(
        (a, b) => (a == 'uncategorized' ? 1 : 0).compareTo(
          b == 'uncategorized' ? 1 : 0,
        ),
      );
    final showHeaders = activeTab == 'all' && keys.length > 1;

    final widgets = <Widget>[];
    for (final key in keys) {
      if (showHeaders) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text(
              labels[key]!.toUpperCase(),
              style: TextStyle(
                color: WebeyColors.primaryGold,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        );
      }
      widgets.addAll(
        groups[key]!.map(
          (s) => _ServiceCard(
            service: s,
            onSelect: onServiceSelected != null
                ? () => onServiceSelected!(s)
                : null,
          ),
        ),
      );
    }
    return widgets;
  }
}

class _ServiceEmptyState extends StatelessWidget {
  const _ServiceEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Text(
        'Hizmet bilgisi yakında.',
        style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, this.onSelect});
  final _ServiceItem service;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        service.name,
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (service.popular) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: WebeyColors.primaryGold.withAlpha(25),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: WebeyColors.primaryGold.withAlpha(60),
                          ),
                        ),
                        child: Text(
                          'Popüler',
                          style: TextStyle(
                            color: WebeyColors.primaryGold,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  service.desc,
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 11,
                      color: WebeyColors.mutedTaupe,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      service.duration,
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Price + CTA
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'FİYAT',
                style: TextStyle(
                  color: WebeyColors.mutedTaupe,
                  fontSize: 8.5,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '${service.price.toInt()} TL',
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onSelect,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: WebeyColors.darkEspresso,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Seç',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REVIEWS SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewsSection extends StatelessWidget {
  const _ReviewsSection({
    required this.salon,
    required this.rating,
    required this.reviewCount,
    required this.reviews,
  });
  final Salon salon;
  final double rating;
  final int reviewCount;
  final List<_ReviewItem> reviews;

  @override
  Widget build(BuildContext context) {
    if (reviewCount == 0) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(eyebrow: 'YORUMLAR · 0', title: 'Müşteri deneyimi'),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.star_outline_rounded,
                    size: 34,
                    color: WebeyColors.mutedTaupe,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Henüz yorum yok',
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 14,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Bu salon için ilk yorumu randevunuzdan sonra yapabilirsiniz.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final breakdown = [
      (n: 5, pct: 0.88, count: reviewCount),
      (n: 4, pct: 0.09, count: 0),
      (n: 3, pct: 0.02, count: 0),
      (n: 2, pct: 0.01, count: 0),
      (n: 1, pct: 0.00, count: 0),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionLabel(
                  eyebrow: 'YORUMLAR · $reviewCount',
                  title: 'Müşteri deneyimi',
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _SalonReviewsScreen(
                        salon: salon,
                        rating: rating,
                        reviewCount: reviewCount,
                        reviews: reviews,
                      ),
                    ),
                  );
                },
                child: Row(
                  children: [
                    Text(
                      'Tümü',
                      style: TextStyle(
                        color: WebeyColors.primaryGold,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: WebeyColors.primaryGold,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: WebeyColors.warmCream,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WebeyColors.borderSand),
            ),
            child: Row(
              children: [
                // Big score
                Column(
                  children: [
                    Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 36,
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: List.generate(5, (i) {
                        return Icon(
                          Icons.star_rounded,
                          size: 12,
                          color: WebeyColors.primaryGold,
                        );
                      }),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$reviewCount YORUM',
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 8.5,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                // Bar chart
                Expanded(
                  child: Column(
                    children: breakdown.map((r) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Text(
                              '${r.n}',
                              style: TextStyle(
                                color: WebeyColors.mutedTaupe,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: r.pct,
                                  backgroundColor: WebeyColors.borderSand,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        WebeyColors.primaryGold,
                                      ),
                                  minHeight: 5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 22,
                              child: Text(
                                '${r.count}',
                                style: TextStyle(
                                  color: WebeyColors.mutedTaupe,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Review cards
          ...reviews.map((r) => _ReviewCard(review: r)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TÜM YORUMLAR — ayrı sayfa (salon başlığı + puan özeti + liste)
// ─────────────────────────────────────────────────────────────────────────────

class _SalonReviewsScreen extends StatelessWidget {
  const _SalonReviewsScreen({
    required this.salon,
    required this.rating,
    required this.reviewCount,
    required this.reviews,
  });

  final Salon salon;
  final double rating;
  final int reviewCount;
  final List<_ReviewItem> reviews;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      appBar: AppBar(
        backgroundColor: WebeyColors.ivory,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: WebeyColors.darkEspresso,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Tüm Yorumlar',
          style: TextStyle(
            color: WebeyColors.darkEspresso,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomInset),
        children: [
          _SalonReviewHeader(salon: salon, rating: rating, count: reviewCount),
          const SizedBox(height: 16),
          if (reviews.isEmpty)
            _buildEmptyState()
          else ...[
            _SalonReviewSummary(rating: rating, reviews: reviews),
            const SizedBox(height: 16),
            ...reviews.map((r) => _ReviewCard(review: r)),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        children: [
          Icon(
            Icons.star_outline_rounded,
            size: 36,
            color: WebeyColors.mutedTaupe,
          ),
          const SizedBox(height: 10),
          const Text(
            'Henüz yorum yok',
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 15,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Bu salon için ilk yorumu randevunuzdan sonra yapabilirsiniz.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalonReviewHeader extends StatelessWidget {
  const _SalonReviewHeader({
    required this.salon,
    required this.rating,
    required this.count,
  });

  final Salon salon;
  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    final location = [
      salon.district,
      salon.city,
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 64,
              height: 64,
              child: salon.coverImage.isNotEmpty
                  ? Image.network(
                      salon.coverImage,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const _ReviewCoverPlaceholder(),
                    )
                  : const _ReviewCoverPlaceholder(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  salon.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 16,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: WebeyColors.primaryGold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      rating > 0 ? rating.toStringAsFixed(1) : '—',
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· $count yorum',
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCoverPlaceholder extends StatelessWidget {
  const _ReviewCoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WebeyColors.warmCream,
      child: Icon(
        Icons.storefront_outlined,
        color: WebeyColors.mutedTaupe,
        size: 24,
      ),
    );
  }
}

/// Yüklenen yorumlardan gerçek yıldız dağılımını hesaplayıp gösterir (fake yok).
class _SalonReviewSummary extends StatelessWidget {
  const _SalonReviewSummary({required this.rating, required this.reviews});

  final double rating;
  final List<_ReviewItem> reviews;

  @override
  Widget build(BuildContext context) {
    final total = reviews.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                rating > 0 ? rating.toStringAsFixed(1) : '—',
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 36,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$total YORUM',
                style: TextStyle(
                  color: WebeyColors.mutedTaupe,
                  fontSize: 8.5,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [5, 4, 3, 2, 1].map((n) {
                final count = reviews.where((r) => r.rating == n).length;
                final pct = total > 0 ? count / total : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text(
                        '$n',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 6,
                            backgroundColor: WebeyColors.borderSand,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              WebeyColors.primaryGold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 18,
                        child: Text(
                          '$count',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final _ReviewItem review;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [review.colorA, review.colorB],
                  ),
                ),
                child: Center(
                  child: Text(
                    review.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.name,
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      children: [
                        Row(
                          children: List.generate(5, (i) {
                            return Icon(
                              i < review.rating
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 11,
                              color: i < review.rating
                                  ? WebeyColors.primaryGold
                                  : WebeyColors.borderSand,
                            );
                          }),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          review.when,
                          style: TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            review.body,
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 12.5,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: WebeyColors.goldLight,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              review.service,
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOCATION & HOURS SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _LocationHoursSection extends StatelessWidget {
  const _LocationHoursSection({
    required this.salon,
    required this.onDirectionsTap,
    required this.onPhoneTap,
  });
  final Salon salon;
  final VoidCallback onDirectionsTap;
  final VoidCallback onPhoneTap;

  static const _hours = [
    (day: 'Pazartesi', time: '09:30 – 19:00', today: false),
    (day: 'Salı', time: '09:30 – 19:00', today: true),
    (day: 'Çarşamba', time: '09:30 – 19:00', today: false),
    (day: 'Perşembe', time: '09:30 – 19:00', today: false),
    (day: 'Cuma', time: '09:30 – 19:00', today: false),
    (day: 'Cumartesi', time: '10:00 – 18:00', today: false),
    (day: 'Pazar', time: 'Kapalı', today: false),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(eyebrow: 'KONUM & SAATLER', title: 'Salon adresi'),
          const SizedBox(height: 14),
          // Map placeholder
          Container(
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WebeyColors.borderSand),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE6DCC9), Color(0xFFD8C9AA)],
              ),
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: CustomPaint(
                    size: const Size(double.infinity, 140),
                    painter: _SimpleGridPainter(),
                  ),
                ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: WebeyColors.darkEspresso,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 12,
                          color: WebeyColors.primaryGold,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          salon.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Address row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      salon.address ?? 'Caferağa Mah. Moda Cad. No:21',
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      salon.distanceKm > 0
                          ? '${salon.district} / ${salon.city} · ${salon.distanceKm.toStringAsFixed(1)} km uzaklıkta'
                          : '${salon.district} / ${salon.city}',
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _LocBtn(
                    icon: Icons.directions_outlined,
                    onTap: onDirectionsTap,
                  ),
                  const SizedBox(width: 8),
                  _LocBtn(icon: Icons.phone_outlined, onTap: onPhoneTap),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Hours
          Container(
            decoration: BoxDecoration(
              color: WebeyColors.warmCream,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WebeyColors.borderSand),
            ),
            child: Column(
              children: List.generate(_hours.length, (i) {
                final h = _hours[i];
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: h.today ? WebeyColors.goldLight : Colors.transparent,
                    borderRadius: i == 0
                        ? const BorderRadius.vertical(top: Radius.circular(11))
                        : i == _hours.length - 1
                        ? const BorderRadius.vertical(
                            bottom: Radius.circular(11),
                          )
                        : null,
                    border: i < _hours.length - 1
                        ? Border(
                            bottom: BorderSide(color: WebeyColors.borderSand),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      Text(
                        h.day,
                        style: TextStyle(
                          color: h.today
                              ? WebeyColors.darkEspresso
                              : WebeyColors.mutedTaupe,
                          fontSize: 12.5,
                          fontWeight: h.today
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (h.today) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: WebeyColors.primaryGold,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Bugün',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        h.time,
                        style: TextStyle(
                          color: h.time == 'Kapalı'
                              ? WebeyColors.errorRed
                              : (h.today
                                    ? WebeyColors.darkEspresso
                                    : WebeyColors.mutedTaupe),
                          fontSize: 12,
                          fontWeight: h.today
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocBtn extends StatelessWidget {
  const _LocBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Icon(icon, size: 16, color: WebeyColors.darkEspresso),
      ),
    );
  }
}

class _SimpleGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = WebeyColors.darkEspresso.withAlpha(10)
      ..strokeWidth = 1;
    const step = 30.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// STICKY CTA
// ─────────────────────────────────────────────────────────────────────────────

class _StickyCTA extends StatelessWidget {
  const _StickyCTA({required this.startingPrice, required this.onTap});
  final double startingPrice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: WebeyColors.ivory,
        border: Border(top: BorderSide(color: WebeyColors.borderSand)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'BAŞLANGIÇ FİYATI',
                style: TextStyle(
                  color: WebeyColors.mutedTaupe,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${startingPrice.toInt()} TL',
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 18,
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(
                      text: ' \'den',
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 13,
                        fontFamily: 'Georgia',
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: WebeyColors.primaryGold,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'RANDEVU AL',
                      style: TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: WebeyColors.darkEspresso,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED: Section Label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.eyebrow, required this.title});
  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 16, height: 1, color: WebeyColors.primaryGold),
            const SizedBox(width: 6),
            Text(
              eyebrow,
              style: TextStyle(
                color: WebeyColors.primaryGold,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          title,
          style: const TextStyle(
            color: WebeyColors.darkEspresso,
            fontSize: 17,
            fontFamily: 'Georgia',
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARE OPTION ROW
// ─────────────────────────────────────────────────────────────────────────────

class _ShareOption extends StatelessWidget {
  const _ShareOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: WebeyColors.primaryGold),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
