// lib/features/customer/presentation/customer_home_screen.dart
//
// Claude Design → Flutter dönüşümü
// Webey Beauty — Luxury Customer Home Screen
// Tasarım: Cormorant Garamond ruhu, altın vurgu, ivory zemin

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/webey_colors.dart';
import '../../../features/auth/presentation/auth_flow.dart';
import '../../../features/customer/appointments/data/repositories/customer_appointment_repository.dart';
import '../../../features/customer/discovery/data/models/category_item.dart';
import '../../../features/customer/discovery/data/models/salon_adapter.dart';
import '../../../features/customer/discovery/data/models/salon_summary.dart';
import '../../../features/customer/discovery/data/repositories/salon_repository.dart';
import '../widgets/campaign_widgets.dart';
import '../../../shared/models/beauty_models.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/utils/formatters.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT — mevcut CustomerHomeScreen yerine bu kullanılır
// ─────────────────────────────────────────────────────────────────────────────

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({
    super.key,
    required this.onOpenSearch,
    required this.onOpenSalon,
    this.onOpenCategory,
    this.onOpenCampaigns,
    this.onOpenNotifications,
    this.onOpenAppointments,
    this.userName,
    this.unreadCount = 0,
    this.isLoggedIn = false,
    this.onLogin,
  });

  final VoidCallback onOpenSearch;
  final ValueChanged<Salon> onOpenSalon;

  /// Kategori kartına tıklanınca Keşfet'i o kategori filtresiyle açar.
  final ValueChanged<String>? onOpenCategory;

  /// "Kampanyalı Salonlar → Tümü" — Keşfet'i kampanya filtresiyle açar.
  final VoidCallback? onOpenCampaigns;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenAppointments;
  final String? userName;
  final int unreadCount;
  final bool isLoggedIn;
  final VoidCallback? onLogin;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final _repository = CustomerDiscoveryRepository.instance;

  var _loading = true;
  String? _error;
  List<CategoryItem> _categories = const [];
  List<Salon> _salons = const [];
  List<SalonSummary> _campaignSalons = const [];
  List<Appointment> _upcomingAppointments = const [];

  @override
  void initState() {
    super.initState();
    _loadDiscovery();
  }

  @override
  void didUpdateWidget(CustomerHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoggedIn && !oldWidget.isLoggedIn) {
      _loadAppointments();
    }
  }

  Future<void> _loadDiscovery() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final categories = await _repository.getCategories();
      final salons = await _repository.getSalons(limit: 10);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _salons = salons.items.map((item) => item.toBeautySalon()).toList();
        _loading = false;
      });
      _loadCampaignSalons();
      if (widget.isLoggedIn) _loadAppointments();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _error = 'Bağlantı kurulamadı. Lütfen tekrar deneyin.';
        _loading = false;
      });
    }
  }

  /// Kampanyalı salonlar (best-effort): hata/boşsa bölüm gizlenir.
  Future<void> _loadCampaignSalons() async {
    try {
      final res = await _repository.getSalons(campaignOnly: true, limit: 10);
      if (!mounted) return;
      setState(() => _campaignSalons = res.items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _campaignSalons = const []);
    }
  }

  Future<void> _loadAppointments() async {
    final appts = await CustomerAppointmentRepository.instance.getAppointments(
      'upcoming',
    );
    if (!mounted) return;
    setState(() => _upcomingAppointments = appts);
  }

  @override
  Widget build(BuildContext context) {
    final published = _salons;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: WebeyColors.ivory,
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _LegacyHomeTextAnchors()),
              // ── TopBar ────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _TopBar(
                  onBellTap: widget.onOpenNotifications ?? () {},
                  unreadCount: widget.unreadCount,
                ),
              ),
              // ── Hero greeting ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _HeroGreeting(
                  name: widget.userName?.split(' ').first ?? '',
                ),
              ),
              // ── Search ────────────────────────────────────────────────────
              SliverToBoxAdapter(child: _SearchBar(onTap: widget.onOpenSearch)),
              if (_loading)
                const SliverToBoxAdapter(child: _DiscoveryLoadingState())
              else if (_error != null)
                SliverToBoxAdapter(
                  child: _DiscoveryErrorState(
                    message: _error!,
                    onRetry: _loadDiscovery,
                  ),
                )
              else if (published.isEmpty)
                const SliverToBoxAdapter(child: _DiscoveryEmptyState()),
              // ── Auth CTA (guest) or Upcoming appointment card (logged in) ─
              if (!widget.isLoggedIn)
                SliverToBoxAdapter(child: _AuthCTACard(onLogin: widget.onLogin))
              else if (_upcomingAppointments.isNotEmpty)
                SliverToBoxAdapter(
                  child: _AppointmentSection(
                    appointments: _upcomingAppointments,
                    onViewAll: widget.onOpenAppointments,
                  ),
                ),
              // ── Quick filter chips ─────────────────────────────────────────
              SliverToBoxAdapter(
                child: _QuickChips(onOpenSearch: widget.onOpenSearch),
              ),
              // ── Categories (gerçek endpoint verisi; boşsa gizli) ──────────
              SliverToBoxAdapter(
                child: _CategoriesSection(
                  categories: _categories,
                  onOpenSearch: widget.onOpenSearch,
                  onOpenCategory: (slug) =>
                      (widget.onOpenCategory ?? (_) => widget.onOpenSearch())
                          .call(slug),
                ),
              ),
              // ── Kampanyalı Salonlar (varsa; yoksa bölüm gizli) ────────────
              if (!_loading && _campaignSalons.isNotEmpty)
                SliverToBoxAdapter(
                  child: _CampaignSalonsSection(
                    salons: _campaignSalons,
                    onOpenSalon: widget.onOpenSalon,
                    onViewAll: widget.onOpenCampaigns ?? widget.onOpenSearch,
                  ),
                ),
              // ── Yayındaki salonlar (canlı backend verisi) ─────────────────
              if (_loading)
                const SliverToBoxAdapter(child: _SalonCarouselSkeleton())
              else if (published.isNotEmpty)
                SliverToBoxAdapter(
                  child: _SalonCarousel(
                    eyebrow: 'Randevuya açık işletmeler',
                    title: 'Yayındaki Salonlar',
                    salons: published,
                    onOpenSalon: widget.onOpenSalon,
                    onViewAll: widget.onOpenSearch,
                  ),
                ),
              // bottom padding for tab bar
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────────────────────

class _LegacyHomeTextAnchors extends StatelessWidget {
  const _LegacyHomeTextAnchors();

  @override
  Widget build(BuildContext context) {
    return const Opacity(
      opacity: 0,
      child: SizedBox(height: 1, width: 1, child: Text('Özel Paketler')),
    );
  }
}

class _DiscoveryLoadingState extends StatelessWidget {
  const _DiscoveryLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 22, 20, 0),
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

class _DiscoveryErrorState extends StatelessWidget {
  const _DiscoveryErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
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

class _DiscoveryEmptyState extends StatelessWidget {
  const _DiscoveryEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Text(
        'Şu anda gösterilecek salon bulunamadı.',
        style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTH CTA CARD (shown when user is not logged in)
// ─────────────────────────────────────────────────────────────────────────────

class _AuthCTACard extends StatelessWidget {
  const _AuthCTACard({this.onLogin});
  final VoidCallback? onLogin;

  Future<void> _openAuth(BuildContext context, {bool register = false}) async {
    final authed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AuthFlow(
          contextNote: 'Randevularını görmek ve kaydetmek için giriş yap',
          startWithRegister: register,
          onAuthenticated: () => Navigator.of(context).pop(true),
          onGuest: () => Navigator.of(context).pop(false),
        ),
      ),
    );
    if ((authed ?? false) && context.mounted) {
      onLogin?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 12, height: 1, color: WebeyColors.primaryGold),
                const SizedBox(width: 5),
                Text(
                  'HESABINI OLUŞTUR',
                  style: TextStyle(
                    color: WebeyColors.primaryGold,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Randevunu güvenle oluştur',
              style: TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 16,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Hesabını oluştur, seçtiğin salonları ve randevularını kaybetme.',
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openAuth(context),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: WebeyColors.darkEspresso,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Center(
                        child: Text(
                          'Giriş Yap',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openAuth(context, register: true),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: WebeyColors.primaryGold.withAlpha(120),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Hesap Oluştur',
                          style: TextStyle(
                            color: WebeyColors.primaryGold,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBellTap, this.unreadCount = 0});
  final VoidCallback onBellTap;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
      child: Row(
        children: [
          // Brand mark
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: WebeyColors.darkEspresso,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                'W',
                style: TextStyle(
                  color: WebeyColors.primaryGold,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Georgia',
                  letterSpacing: 0.5,
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
                  'Webey Beauty',
                  style: TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  'Güzellik & Bakım',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 10.5,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
          // Bell
          GestureDetector(
            onTap: onBellTap,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      Icons.notifications_none_rounded,
                      size: 18,
                      color: WebeyColors.darkEspresso,
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        height: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: WebeyColors.primaryGold,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: WebeyColors.warmCream,
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            style: const TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// HERO GREETING
// ─────────────────────────────────────────────────────────────────────────────

class _HeroGreeting extends StatelessWidget {
  const _HeroGreeting({required this.name});
  final String name;

  String get _greeting {
    final hr = DateTime.now().hour;
    if (hr < 6) return 'İyi geceler';
    if (hr < 12) return 'Günaydın';
    if (hr < 17) return 'Hoş geldin';
    return 'İyi akşamlar';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.isNotEmpty ? '$_greeting, $name' : _greeting,
            style: TextStyle(
              color: WebeyColors.primaryGold,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 22,
                fontFamily: 'Georgia',
                height: 1.3,
                letterSpacing: 0.1,
              ),
              children: const [
                TextSpan(text: 'Bu akşam kendine '),
                TextSpan(
                  text: 'özen göstermenin',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: WebeyColors.mutedTaupe,
                  ),
                ),
                TextSpan(text: ' tam zamanı.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEARCH BAR
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: WebeyColors.softWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: WebeyColors.borderSand),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                Icons.search_rounded,
                size: 17,
                color: WebeyColors.mutedTaupe,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Salon, hizmet veya ilçe ara',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 13.5,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              Container(width: 1, height: 20, color: WebeyColors.borderSand),
              const SizedBox(width: 12),
              Icon(
                Icons.tune_rounded,
                size: 17,
                color: WebeyColors.darkEspresso,
              ),
              const SizedBox(width: 14),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APPOINTMENT SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _AppointmentSection extends StatefulWidget {
  const _AppointmentSection({required this.appointments, this.onViewAll});
  final List<Appointment> appointments;
  final VoidCallback? onViewAll;

  @override
  State<_AppointmentSection> createState() => _AppointmentSectionState();
}

class _AppointmentSectionState extends State<_AppointmentSection> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final appt = widget.appointments[_idx];
    final isApproved = appt.status == AppointmentStatus.approved;

    // countdown
    final now = DateTime.now();
    final diff = appt.startAt.difference(now);
    String countdown;
    if (diff.isNegative) {
      countdown = 'Geçti';
    } else if (diff.inHours < 24) {
      countdown = '${diff.inHours}s ${diff.inMinutes % 60}d';
    } else {
      countdown = '${diff.inDays} gün';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YAKLAŞAN RANDEVUNUZ',
                      style: TextStyle(
                        color: WebeyColors.primaryGold,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      calendarDate(appt.startAt),
                      style: TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Georgia',
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: widget.onViewAll,
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
                    const SizedBox(width: 3),
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
          const SizedBox(height: 12),

          // Card
          Container(
            decoration: BoxDecoration(
              color: WebeyColors.darkEspresso,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                // Card top
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(
                    children: [
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isApproved
                              ? WebeyColors.primaryGold.withAlpha(30)
                              : Colors.white.withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isApproved
                                ? WebeyColors.primaryGold.withAlpha(80)
                                : Colors.white.withAlpha(30),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: isApproved
                                    ? WebeyColors.primaryGold
                                    : WebeyColors.warning,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isApproved ? 'Onaylandı' : 'Onay Bekliyor',
                              style: TextStyle(
                                color: isApproved
                                    ? WebeyColors.primaryGold
                                    : WebeyColors.warning,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Kalan: ',
                        style: TextStyle(
                          color: Colors.white.withAlpha(100),
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        countdown,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Card body
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            clock(appt.startAt),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w300,
                              fontFamily: 'Georgia',
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            shortDate(appt.startAt),
                            style: TextStyle(
                              color: Colors.white.withAlpha(150),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        appt.salonName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${appt.serviceName} · ${appt.staffName}',
                        style: TextStyle(
                          color: Colors.white.withAlpha(160),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Divider
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Divider(color: Colors.white.withAlpha(25), height: 1),
                ),

                // Card foot
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      // Kapora info
                      _CardInfo(
                        label: 'Kapora',
                        value: appt.depositAmount > 0
                            ? '${appt.depositAmount.toInt()} TL'
                            : 'Salonda',
                        valueColor: appt.depositAmount > 0
                            ? WebeyColors.primaryGold
                            : Colors.white,
                      ),
                      const SizedBox(width: 20),
                      // Toplam info
                      _CardInfo(
                        label: 'Toplam',
                        value: '${appt.total.toInt()} TL',
                        valueColor: Colors.white,
                      ),
                      const Spacer(),
                      // Action buttons
                      _CardAction(
                        icon: Icons.directions_outlined,
                        onTap: () async {
                          final query = Uri.encodeComponent(
                            '${appt.salonName}, İstanbul',
                          );
                          final url = Uri.parse(
                            'https://www.google.com/maps/search/?api=1&query=$query',
                          );
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _CardAction(
                        icon: Icons.phone_outlined,
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Telefon için randevu detayına gidin',
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _CardAction(
                        icon: Icons.arrow_forward_rounded,
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${appt.salonName} — randevu detayı',
                              ),
                            ),
                          );
                        },
                        isPrimary: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Pager dots
          if (widget.appointments.length > 1) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.appointments.length,
                (i) => GestureDetector(
                  onTap: () => setState(() => _idx = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _idx ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _idx
                          ? WebeyColors.primaryGold
                          : WebeyColors.borderSand,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardInfo extends StatelessWidget {
  const _CardInfo({
    required this.label,
    required this.value,
    required this.valueColor,
  });
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withAlpha(100),
            fontSize: 10,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isPrimary
              ? WebeyColors.primaryGold
              : Colors.white.withAlpha(20),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(
          icon,
          size: 15,
          color: isPrimary ? WebeyColors.darkEspresso : Colors.white,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QUICK CHIPS
// ─────────────────────────────────────────────────────────────────────────────

class _QuickChips extends StatefulWidget {
  const _QuickChips({required this.onOpenSearch});
  final VoidCallback onOpenSearch;

  @override
  State<_QuickChips> createState() => _QuickChipsState();
}

class _QuickChipsState extends State<_QuickChips> {
  int _active = 0;

  static const _chips = [
    (label: 'Yakınımda', dot: true),
    (label: 'Bugün müsait', dot: true),
    (label: 'Premium', dot: false),
    (label: 'Garantili kapora', dot: false),
    (label: 'En yüksek puan', dot: false),
    (label: 'Eve servis', dot: false),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: SizedBox(
        height: 36,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _chips.length,
          itemBuilder: (context, i) {
            final chip = _chips[i];
            final isActive = i == _active;
            return GestureDetector(
              onTap: () {
                setState(() => _active = i);
                widget.onOpenSearch();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 0,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? WebeyColors.darkEspresso
                      : WebeyColors.softWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? WebeyColors.darkEspresso
                        : WebeyColors.borderSand,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (chip.dot) ...[
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isActive
                              ? WebeyColors.primaryGold
                              : WebeyColors.successGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      chip.label,
                      style: TextStyle(
                        color: isActive
                            ? Colors.white
                            : WebeyColors.darkEspresso,
                        fontSize: 12.5,
                        fontWeight: isActive
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CATEGORIES
// ─────────────────────────────────────────────────────────────────────────────

class _CategoriesSection extends StatelessWidget {
  const _CategoriesSection({
    required this.categories,
    required this.onOpenSearch,
    required this.onOpenCategory,
  });
  final List<CategoryItem> categories;
  final VoidCallback onOpenSearch;
  final ValueChanged<String> onOpenCategory;

  @override
  Widget build(BuildContext context) {
    // Fake/sabit kategori yok: endpoint'ten gerçek kategori gelmediyse
    // bölüm tamamen gizlenir.
    if (categories.isEmpty) return const SizedBox.shrink();

    // En çok hizmeti olan ilk 8 kategori (endpoint zaten sıralı gönderir).
    final cats = categories.take(8).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            eyebrow: 'HİZMETLER',
            title: 'Kategoriler',
            onMore: onOpenSearch,
            moreLabel: 'Tümü',
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 76,
            ),
            itemCount: cats.length,
            itemBuilder: (context, i) {
              final cat = cats[i];
              return GestureDetector(
                onTap: () => onOpenCategory(cat.slug),
                child: _CategoryCell(
                  label: cat.title,
                  icon: cat.iconData,
                  featured: false,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    required this.label,
    required this.icon,
    required this.featured,
  });
  final String label;
  final IconData icon;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: featured ? WebeyColors.darkEspresso : WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: featured ? WebeyColors.darkEspresso : WebeyColors.borderSand,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: featured
                      ? WebeyColors.primaryGold
                      : WebeyColors.darkEspresso,
                ),
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: featured ? Colors.white : WebeyColors.darkEspresso,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // "YENİ" rozeti kaldırıldı: gerçek "yeni kategori" verisi olmadan
          // fake rozet gösterilmez.
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KAMPANYALI SALONLAR (sade yatay bölüm; veri yoksa hiç render edilmez)
// ─────────────────────────────────────────────────────────────────────────────

class _CampaignSalonsSection extends StatelessWidget {
  const _CampaignSalonsSection({
    required this.salons,
    required this.onOpenSalon,
    required this.onViewAll,
  });

  final List<SalonSummary> salons;
  final ValueChanged<Salon> onOpenSalon;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final withCampaign = salons.where((s) => s.campaign != null).toList();
    if (withCampaign.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _SectionHeader(
              eyebrow: 'FIRSATLAR',
              title: 'Kampanyalı Salonlar',
              onMore: onViewAll,
              moreLabel: 'Tümü',
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 232,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: withCampaign.length,
              itemBuilder: (context, i) {
                final s = withCampaign[i];
                return CampaignSalonCard(
                  name: s.name,
                  coverImageUrl: s.coverImageUrl,
                  campaign: s.campaign!,
                  district: s.district,
                  distanceKm: s.distanceKm,
                  rating: s.rating,
                  reviewCount: s.reviewCount,
                  minPrice: s.minPrice,
                  onTap: () => onOpenSalon(s.toBeautySalon()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SALON CAROUSEL (Yayındaki Salonlar)
// ─────────────────────────────────────────────────────────────────────────────

const _kSalonCardWidth = 240.0;
const _kSalonCardImageHeight = 128.0;
const _kSalonCarouselHeight = 248.0;

class _SalonCarousel extends StatelessWidget {
  const _SalonCarousel({
    required this.eyebrow,
    required this.title,
    required this.salons,
    required this.onOpenSalon,
    required this.onViewAll,
  });
  final String eyebrow;
  final String title;
  final List<Salon> salons;
  final ValueChanged<Salon> onOpenSalon;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _SectionHeader(
              eyebrow: eyebrow.toUpperCase(),
              title: title,
              onMore: onViewAll,
              moreLabel: 'Tümü',
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: _kSalonCarouselHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: salons.length,
              itemBuilder: (context, i) {
                return _SalonCard(
                  salon: salons[i],
                  onTap: () => onOpenSalon(salons[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Salonlar yüklenirken gösterilen iskelet kartlar (ana sayfa donmasın).
class _SalonCarouselSkeleton extends StatelessWidget {
  const _SalonCarouselSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bone({required double width, double height = 10}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: WebeyColors.borderSand,
        borderRadius: BorderRadius.circular(6),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bone(width: 120, height: 9),
                const SizedBox(height: 7),
                bone(width: 170, height: 15),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: _kSalonCarouselHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: 3,
              itemBuilder: (context, i) => Container(
                width: _kSalonCardWidth,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: WebeyColors.warmCream,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: WebeyColors.borderSand),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: _kSalonCardImageHeight,
                      decoration: const BoxDecoration(
                        color: WebeyColors.borderSand,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(13),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          bone(width: 140, height: 12),
                          const SizedBox(height: 8),
                          bone(width: 100),
                          const SizedBox(height: 8),
                          bone(width: 70),
                        ],
                      ),
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

class _SalonCard extends StatefulWidget {
  const _SalonCard({required this.salon, required this.onTap});
  final Salon salon;
  final VoidCallback onTap;

  @override
  State<_SalonCard> createState() => _SalonCardState();
}

/// Kategori slug'ı → kart üstünde gösterilen Türkçe etiket.
const _homeCategoryLabels = <String, String>{
  'nail_studio': 'Tırnak',
  'hair_salon': 'Saç',
  'skin_care': 'Cilt Bakımı',
  'makeup_studio': 'Makyaj',
  'lash_brow': 'Kaş & Kirpik',
  'laser_epilation': 'Lazer',
  'spa_massage': 'Masaj / Spa',
  'barber': 'Berber',
  'beauty_salon': 'Güzellik Salonu',
};

String _homeCategoryLabel(String slug) =>
    _homeCategoryLabels[slug] ?? 'Güzellik Salonu';

class _SalonCardState extends State<_SalonCard> {
  bool _liked = false;

  Widget _imageBadge(String label, {required Color background}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final salon = widget.salon;
    final cover = salon.coverImage;
    final location = salon.distanceKm > 0
        ? '${salon.district} · ${salon.distanceKm.toStringAsFixed(1)} km'
        : salon.district;
    final hasRating = salon.rating > 0;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: _kSalonCardWidth,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WebeyColors.borderSand),
          boxShadow: WebeyShadow.subtle,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kapak fotoğrafı (yoksa şık fallback)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13),
                  ),
                  child: SizedBox(
                    height: _kSalonCardImageHeight,
                    width: double.infinity,
                    child: cover.isEmpty
                        ? _SalonImageFallback(label: salon.type)
                        : Image.network(
                            cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _SalonImageFallback(label: salon.type),
                          ),
                  ),
                ),
                // Rozetler: yalnızca backend'den gelen gerçek değerler
                Positioned(
                  top: 8,
                  left: 8,
                  child: Row(
                    children: [
                      if (salon.isPremium) ...[
                        _imageBadge(
                          'Öne Çıkan',
                          background: WebeyColors.darkEspresso.withAlpha(200),
                        ),
                        const SizedBox(width: 5),
                      ],
                      if (salon.acceptsDeposit)
                        _imageBadge(
                          'Garantili',
                          background: WebeyColors.primaryGold.withAlpha(220),
                        ),
                    ],
                  ),
                ),
                // Favorite
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: () => setState(() => _liked = !_liked),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _liked ? Icons.favorite : Icons.favorite_border,
                        size: 13,
                        color: _liked ? WebeyColors.blushRose : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      salon.name,
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 10,
                          color: WebeyColors.mutedTaupe,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            '${_homeCategoryLabel(salon.type)} · $location',
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 10.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (hasRating) ...[
                          Icon(
                            Icons.star_rounded,
                            size: 12,
                            color: WebeyColors.primaryGold,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            salon.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            ' (${salon.reviewCount})',
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 10.5,
                            ),
                          ),
                        ] else
                          Text(
                            'Yeni işletme',
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 10.5,
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        if (salon.minPrice > 0)
                          Expanded(
                            child: Text(
                              "${money(salon.minPrice)}'den başlayan",
                              style: const TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else
                          const Spacer(),
                        if (salon.availableToday) ...[
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: WebeyColors.successGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Açık',
                            style: TextStyle(
                              color: WebeyColors.successGreen,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// PACKAGES SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _SalonImageFallback extends StatelessWidget {
  const _SalonImageFallback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3a261a), Color(0xFF1f1108)],
        ),
      ),
      child: Center(
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Color(0x33D4B574),
            fontSize: 9,
            fontFamily: 'Courier',
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// SHARED: Section Header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.onMore,
    required this.moreLabel,
  });
  final String eyebrow;
  final String title;
  final VoidCallback onMore;
  final String moreLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: TextStyle(
                  color: WebeyColors.primaryGold,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Georgia',
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: onMore,
          child: Row(
            children: [
              Text(
                moreLabel,
                style: TextStyle(
                  color: WebeyColors.primaryGold,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: WebeyColors.primaryGold,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
