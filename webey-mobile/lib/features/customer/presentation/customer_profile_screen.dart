// lib/features/customer/presentation/customer_profile_screen.dart
//
// Claude Design → Flutter dönüşümü
// Webey Beauty — Profil Ekranı

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/webey_colors.dart';
import '../../../shared/models/beauty_models.dart';
import '../../../shared/services/webey_location_service.dart';
import '../../../shared/widgets/account_deletion_sheet.dart';
import '../discovery/data/models/salon_adapter.dart';
import '../discovery/data/models/salon_summary.dart';
import '../profile/data/models/customer_review_item.dart';
import '../notifications/data/repositories/customer_notification_repository.dart';
import '../profile/data/models/customer_profile.dart';
import '../profile/data/repositories/customer_profile_repository.dart';
import '../profile/data/repositories/customer_review_repository.dart';
import '../profile/data/repositories/customer_wallet_repository.dart';
import 'customer_profile_edit_screen.dart';
import 'legal_documents_screen.dart';

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({
    super.key,
    this.onLogout,
    this.onNavigateToAppointments,
    this.onNavigateToFavorites,
    this.onOpenSalon,
  });

  final VoidCallback? onLogout;
  final VoidCallback? onNavigateToAppointments;
  final VoidCallback? onNavigateToFavorites;
  final Future<void> Function(Salon salon)? onOpenSalon;

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  CustomerProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await CustomerProfileRepository.instance.getProfile();
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  void _handleMenuTap(BuildContext context, _MenuItem item) {
    switch (item.id) {
      case 'm1':
        widget.onNavigateToAppointments?.call();
      case 'm2':
        widget.onNavigateToFavorites?.call();
      case 'm3':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                CustomerMyReviewsScreen(onOpenSalon: widget.onOpenSalon),
          ),
        );
      case 'm4':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DepositWalletScreen(profile: _profile),
          ),
        );
      case 'm6':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
        );
      case 'm7':
        Navigator.of(context)
            .push<bool>(
              MaterialPageRoute(
                builder: (_) => AddressLocationScreen(profile: _profile),
              ),
            )
            .then((changed) {
              if (changed == true && mounted) _loadProfile();
            });
      case 'm9':
        _showSupportSheet(context);
      case 'm10':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LegalDocumentsScreen()));
      case 'm11':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const _WebeyAboutScreen()));
      case 'm12':
        WebeyAccountDeletionSheet.show(context);
    }
  }

  void _showSupportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _SupportSheet(),
    );
  }

  Future<void> _openEditModal(BuildContext context) async {
    final profile = _profile;
    if (profile == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerProfileEditScreen(profile: profile),
      ),
    );
    if (changed == true && mounted) _loadProfile();
  }

  static const _hesapMenu = [
    _MenuItem(
      id: 'm1',
      name: 'Randevularım',
      sub: 'Yaklaşan ve geçmiş randevular',
      icon: Icons.calendar_today_outlined,
    ),
    _MenuItem(
      id: 'm2',
      name: 'Favorilerim',
      sub: 'Kayıtlı salon ve koleksiyonlar',
      icon: Icons.favorite_border_rounded,
    ),
    _MenuItem(
      id: 'm3',
      name: 'Yorumlarım',
      sub: 'Paylaştığın salon ve personel değerlendirmeleri',
      icon: Icons.rate_review_outlined,
    ),
    _MenuItem(
      id: 'm4',
      name: 'Kapora & Cüzdan',
      sub: 'Kapora ve bakiye bilgileri',
      icon: Icons.account_balance_wallet_outlined,
    ),
  ];

  static const _tercihMenu = [
    _MenuItem(
      id: 'm6',
      name: 'Bildirimler',
      sub: 'Randevu, kampanya, hatırlatma',
      icon: Icons.notifications_none_rounded,
    ),
    _MenuItem(
      id: 'm7',
      name: 'Adres ve Konum',
      sub: 'Konum tercihleri',
      icon: Icons.location_on_outlined,
    ),
  ];

  static const _destekMenu = [
    _MenuItem(
      id: 'm9',
      name: 'Yardım ve Destek',
      sub: 'SSS, sohbet ve iade',
      icon: Icons.help_outline_rounded,
    ),
    _MenuItem(
      id: 'm10',
      name: 'Gizlilik ve KVKK',
      sub: 'Veri tercihleri ve politikalar',
      icon: Icons.shield_outlined,
    ),
    _MenuItem(
      id: 'm11',
      name: 'Webey Hakkında',
      sub: 'Uygulama bilgileri ve sürüm',
      icon: Icons.info_outline_rounded,
    ),
    _MenuItem(
      id: 'm12',
      name: 'Hesabımı Sil',
      sub: 'Hesap silme talebi oluştur',
      icon: Icons.delete_outline_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
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
              SliverToBoxAdapter(
                child: _ProfileHeader(onEdit: () => _openEditModal(context)),
              ),
              // Profile card
              SliverToBoxAdapter(
                child: _ProfileCard(
                  profile: profile,
                  onEdit: () => _openEditModal(context),
                ),
              ),
              // Stats row
              SliverToBoxAdapter(child: _ProfileStats(profile: profile)),
              // Hesap menu
              SliverToBoxAdapter(
                child: _MenuSection(
                  title: 'HESAP',
                  items: _hesapMenu,
                  onItemTap: _handleMenuTap,
                ),
              ),
              // Tercihler menu
              SliverToBoxAdapter(
                child: _MenuSection(
                  title: 'TERCİHLER',
                  items: _tercihMenu,
                  onItemTap: _handleMenuTap,
                ),
              ),
              // Destek menu
              SliverToBoxAdapter(
                child: _MenuSection(
                  title: 'DESTEK & YASAL',
                  items: _destekMenu,
                  onItemTap: _handleMenuTap,
                ),
              ),
              // Sign out
              SliverToBoxAdapter(child: _SignOutRow(onLogout: widget.onLogout)),
              // Footer
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Center(
                    child: Text(
                      'Webey Beauty\nSürüm ${AppInfo.version} · 2026',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 11,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({this.onEdit});
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 24,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w600,
                    ),
                    children: [
                      TextSpan(text: 'Pro'),
                      TextSpan(
                        text: 'fil',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hesabını ve tercihlerini yönet.',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onEdit,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: const Icon(
                Icons.edit_outlined,
                size: 17,
                color: WebeyColors.darkEspresso,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile Card ─────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({this.profile, this.onEdit});
  final CustomerProfile? profile;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final firstName = profile?.displayFirstName ?? '';
    final lastName = profile?.displayLastName ?? '';
    final email = profile?.email ?? '';
    final initial = profile?.displayInitial ?? '?';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFD4B574), Color(0xFF8C6F38)],
                ),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Georgia',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name + email
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 17,
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(text: '$firstName '),
                        TextSpan(
                          text: lastName,
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    email,
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Edit btn
            GestureDetector(
              onTap: onEdit,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: WebeyColors.warmCream,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: WebeyColors.borderSand),
                ),
                child: const Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: WebeyColors.darkEspresso,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Profile Stats ────────────────────────────────────────────────────────────

class _ProfileStats extends StatelessWidget {
  const _ProfileStats({this.profile});
  final CustomerProfile? profile;

  @override
  Widget build(BuildContext context) {
    final apptCount = profile?.stats.appointmentsCount ?? 0;
    final completedCount = profile?.stats.completedCount ?? 0;
    final cancelledCount = profile?.stats.cancelledCount ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          children: [
            _StatCell(value: '$apptCount', label: 'RANDEVU'),
            Container(width: 1, height: 44, color: WebeyColors.borderSand),
            _StatCell(value: '$completedCount', label: 'TAMAMLANAN'),
            Container(width: 1, height: 44, color: WebeyColors.borderSand),
            _StatCell(value: '$cancelledCount', label: 'İPTAL'),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 20,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Menu Section ─────────────────────────────────────────────────────────────

class _MenuItem {
  const _MenuItem({
    required this.id,
    required this.name,
    required this.sub,
    required this.icon,
  });
  final String id, name, sub;
  final IconData icon;
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({
    required this.title,
    required this.items,
    required this.onItemTap,
  });
  final String title;
  final List<_MenuItem> items;
  final void Function(BuildContext, _MenuItem) onItemTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: WebeyColors.softWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: WebeyColors.borderSand),
            ),
            child: Column(
              children: List.generate(items.length, (i) {
                final item = items[i];
                final isLast = i == items.length - 1;
                return Column(
                  children: [
                    _MenuRow(item: item, onTap: () => onItemTap(context, item)),
                    if (!isLast)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Divider(
                          height: 1,
                          color: WebeyColors.borderSand,
                        ),
                      ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item, required this.onTap});
  final _MenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            // Icon
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: Icon(item.icon, size: 17, color: WebeyColors.darkEspresso),
            ),
            const SizedBox(width: 12),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.sub,
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: WebeyColors.mutedTaupe,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sign Out ──────────────────────────────────────────────────────────────────

class CustomerMyReviewsScreen extends StatefulWidget {
  const CustomerMyReviewsScreen({super.key, this.onOpenSalon});

  final Future<void> Function(Salon salon)? onOpenSalon;

  @override
  State<CustomerMyReviewsScreen> createState() =>
      _CustomerMyReviewsScreenState();
}

class _CustomerMyReviewsScreenState extends State<CustomerMyReviewsScreen> {
  var _loading = true;
  var _items = <CustomerReviewItem>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await CustomerReviewRepository.instance.getMyReviews();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _openReview(CustomerReviewItem item) async {
    final openSalon = widget.onOpenSalon;
    if (openSalon == null) return;
    final salon = SalonSummary(
      id: item.businessId,
      slug: item.businessSlug ?? '',
      name: item.businessName,
      city: item.businessCity,
      district: item.businessDistrict,
    ).toBeautySalon();
    await openSalon(salon);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _ProfileInfoScaffold(
        title: 'Yorumlarım',
        icon: Icons.rate_review_outlined,
        children: [
          SizedBox(
            height: 180,
            child: Center(
              child: CircularProgressIndicator(
                color: WebeyColors.primaryGold,
                strokeWidth: 2,
              ),
            ),
          ),
        ],
      );
    }

    return _ProfileInfoScaffold(
      title: 'Yorumlarım',
      icon: Icons.rate_review_outlined,
      children: _items.isEmpty
          ? const [
              _InfoCard(
                title: 'Henüz yorumun yok',
                body:
                    'Tamamlanan randevularından sonra verdiğin puan ve yorumlar burada görünür.',
              ),
            ]
          : _items
                .map(
                  (item) =>
                      _MyReviewCard(item: item, onTap: () => _openReview(item)),
                )
                .toList(),
    );
  }
}

class _MyReviewCard extends StatelessWidget {
  const _MyReviewCard({required this.item, required this.onTap});

  final CustomerReviewItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final target = item.isStaffReview
        ? 'Personel: ${item.staffName ?? 'Uzman'}'
        : 'İşletme yorumu';
    final subtitle = [
      item.serviceName,
      target,
      _reviewDate(item.createdAt),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
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
                Expanded(
                  child: Text(
                    item.businessName.isEmpty ? 'Salon' : item.businessName,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: WebeyColors.mutedTaupe,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: List.generate(
                5,
                (index) => Icon(
                  index < item.rating
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 15,
                  color: WebeyColors.primaryGold,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 11.5),
            ),
            if ((item.comment ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                item.comment!.trim(),
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 12.5,
                  height: 1.45,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _reviewDate(DateTime? value) {
  if (value == null) return '';
  return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
}

class _SignOutRow extends StatelessWidget {
  const _SignOutRow({this.onLogout});
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GestureDetector(
        onTap: onLogout,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: WebeyColors.errorRed.withAlpha(12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: WebeyColors.errorRed.withAlpha(40)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, size: 16, color: WebeyColors.errorRed),
              const SizedBox(width: 8),
              Text(
                'Çıkış Yap',
                style: TextStyle(
                  color: WebeyColors.errorRed,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Support Sheet ─────────────────────────────────────────────────────────────

class _SupportSheet extends StatelessWidget {
  const _SupportSheet();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    // Opak zemin: yazıların arkadaki profil ekranıyla karışmasını önler.
    return Container(
      decoration: const BoxDecoration(
        color: WebeyColors.ivory,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 16),
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
              const Text(
                'Yardım ve Destek',
                style: TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 18,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Sana yardımcı olmak için buradayız.',
                style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 13),
              ),
              const SizedBox(height: 20),
              _SupportOption(
                icon: Icons.help_outline_rounded,
                title: 'Sık Sorulan Sorular',
                subtitle: 'Randevu, ödeme ve hesap hakkında',
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(
                    MaterialPageRoute(builder: (_) => const _FaqScreen()),
                  );
                },
              ),
              const SizedBox(height: 10),
              _SupportOption(
                icon: Icons.mail_outline_rounded,
                title: 'E-posta ile İletişim',
                subtitle: 'destek@webey.com.tr',
                onTap: () {
                  Clipboard.setData(
                    const ClipboardData(text: 'destek@webey.com.tr'),
                  );
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('E-posta adresi panoya kopyalandı.'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportOption extends StatelessWidget {
  const _SupportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: WebeyColors.darkEspresso),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: WebeyColors.mutedTaupe,
            ),
          ],
        ),
      ),
    );
  }
}

// ── SSS (Sık Sorulan Sorular) ─────────────────────────────────────────────────

class _FaqItem {
  const _FaqItem(this.question, this.answer);
  final String question;
  final String answer;
}

class _FaqScreen extends StatelessWidget {
  const _FaqScreen();

  static const _items = [
    _FaqItem(
      'Webey üzerinden nasıl randevu alırım?',
      'Salonu bul, bir hizmet ve uygun saati seç, randevunu oluştur. Kapora '
          'gerekiyorsa işletmenin IBAN bilgisi sana gösterilir.',
    ),
    _FaqItem(
      'Randevumu nasıl iptal ederim?',
      'Randevularım sayfasından ilgili randevuyu açıp iptal talebi '
          'oluşturabilirsin. İptal ve iade koşulları işletmenin politikasına göre '
          'değişebilir.',
    ),
    _FaqItem(
      'Kapora neden isteniyor?',
      'Kapora, randevunun garanti altına alınması ve gelinmeyen randevuların '
          'azaltılması için işletme tarafından istenir.',
    ),
    _FaqItem(
      'Kapora ödemesini nasıl yaparım?',
      'Kapora Webey tarafından tahsil edilmez; doğrudan işletmenin IBAN '
          'numarasına gönderilir. Ödeme açıklamasına sana verilen referans kodunu '
          'yazman gerekir.',
    ),
    _FaqItem(
      'Kapora iadesi nasıl olur?',
      'İade koşulları işletmenin iptal/iade politikasına göre değişir. '
          'Onaylanan ve iade edilen kaporaları Kapora & Cüzdan sayfasından takip '
          'edebilirsin.',
    ),
    _FaqItem(
      'İşletme randevumu ne zaman onaylar?',
      'Kapora gerekiyorsa, işletme ödemeni hesabında gördükten sonra randevunu '
          'onaylar ve randevun kesinleşir.',
    ),
    _FaqItem(
      'Favorilere salon nasıl eklerim?',
      'Salon detay sayfasındaki kalp simgesine dokunarak salonu favorilerine '
          'ekleyebilir, Favorilerim sayfasından kolayca ulaşabilirsin.',
    ),
    _FaqItem(
      'Değerlendirme/yorum nasıl yaparım?',
      'Tamamlanan randevularından sonra ilgili randevu üzerinden salona puan '
          've yorum bırakabilirsin.',
    ),
    _FaqItem(
      'Hesabımı nasıl silebilirim?',
      'Profil > Hesabımı Sil adımından hesap silme talebi oluşturabilir veya '
          'web üzerindeki hesap silme sayfasını kullanabilirsin.',
    ),
    _FaqItem(
      'Destek ekibine nasıl ulaşırım?',
      'Profil > Yardım ve Destek bölümünden destek@webey.com.tr adresine '
          'e-posta göndererek bize ulaşabilirsin.',
    ),
  ];

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
          'Sık Sorulan Sorular',
          style: TextStyle(
            color: WebeyColors.darkEspresso,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView.separated(
        padding: EdgeInsets.fromLTRB(18, 14, 18, 24 + bottomInset),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _FaqCard(item: _items[i]),
      ),
    );
  }
}

class _FaqCard extends StatelessWidget {
  const _FaqCard({required this.item});
  final _FaqItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: WebeyColors.primaryGold,
          collapsedIconColor: WebeyColors.mutedTaupe,
          title: Text(
            item.question,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                item.answer,
                style: const TextStyle(
                  color: WebeyColors.mutedTaupe,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Webey About Screen ────────────────────────────────────────────────────────

class _WebeyAboutScreen extends StatelessWidget {
  const _WebeyAboutScreen();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: WebeyColors.ivory,
        body: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: WebeyColors.warmCream,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: WebeyColors.borderSand),
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            size: 18,
                            color: WebeyColors.darkEspresso,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Text(
                        'Webey Hakkında',
                        style: TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 17,
                          fontFamily: 'Georgia',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: WebeyColors.darkEspresso,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        'W',
                        style: TextStyle(
                          color: WebeyColors.primaryGold,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Georgia',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 22,
                            fontFamily: 'Georgia',
                            height: 1.3,
                          ),
                          children: [
                            TextSpan(text: 'Webey '),
                            TextSpan(
                              text: 'Beauty',
                              style: TextStyle(fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sürüm ${AppInfo.version}',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Webey Beauty, güzellik ve bakım randevunu en güvenli şekilde almanı sağlayan bir platformdur.',
                        style: TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Premium salonları keşfet, uygun saatleri seç ve güvenli kapora sistemi ile randevunu garantiye al. Bildirimler ve anlık takip ile hiçbir randevunu kaçırma.',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 13.5,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _AboutRow(label: 'Versiyon', value: AppInfo.version),
                      _AboutRow(label: 'Platform', value: 'Android'),
                      _AboutRow(label: 'Geliştirici', value: 'Webey Teknoloji'),
                      _AboutRow(label: 'Web', value: 'webey.com.tr'),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 60)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 13),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class DepositWalletScreen extends StatefulWidget {
  const DepositWalletScreen({super.key, this.profile});
  final CustomerProfile? profile;

  @override
  State<DepositWalletScreen> createState() => _DepositWalletScreenState();
}

class _DepositWalletScreenState extends State<DepositWalletScreen> {
  DepositWallet? _wallet;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final wallet = await CustomerWalletRepository.instance.getWallet();
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kapora bilgilerin yüklenemedi. Lütfen tekrar dene.';
        _loading = false;
      });
    }
  }

  static String _money(double v) {
    final whole = v.round();
    final s = whole.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '$buf TL';
  }

  static String _date(DateTime? d) {
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      appBar: AppBar(
        backgroundColor: WebeyColors.ivory,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Kapora & Cüzdan'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: WebeyColors.primaryGold,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: WebeyColors.primaryGold),
        ),
      );
    }
    if (_error != null) {
      return ListView(
        padding: EdgeInsets.fromLTRB(20, 60, 20, 24 + bottomInset),
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 42,
            color: WebeyColors.mutedTaupe,
          ),
          const SizedBox(height: 14),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tekrar dene'),
            ),
          ),
        ],
      );
    }

    final wallet = _wallet ?? DepositWallet.empty;
    return ListView(
      padding: EdgeInsets.fromLTRB(18, 14, 18, 24 + bottomInset),
      children: [
        _WalletHeroCard(value: _money(wallet.paidTotal)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _WalletMiniCard(
                label: 'Onay bekleyen',
                value: _money(wallet.pendingTotal),
                icon: Icons.schedule_rounded,
                color: WebeyColors.warning,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _WalletMiniCard(
                label: 'İade edilen',
                value: _money(wallet.refundedTotal),
                icon: Icons.replay_rounded,
                color: WebeyColors.mutedTaupe,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'SON KAPORA HAREKETLERİ',
          style: TextStyle(
            color: WebeyColors.mutedTaupe,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        if (wallet.items.isEmpty)
          _WalletEmptyState()
        else
          ...wallet.items.map(
            (item) => _WalletTxnCard(
              item: item,
              amountText: _money(item.amount),
              dateText: _date(item.eventAt ?? item.appointmentStart),
            ),
          ),
      ],
    );
  }
}

class _WalletHeroCard extends StatelessWidget {
  const _WalletHeroCard({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: WebeyColors.darkEspresso,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 12, height: 1, color: WebeyColors.primaryGold),
              const SizedBox(width: 5),
              Text(
                'TOPLAM ÖDENEN KAPORA',
                style: TextStyle(
                  color: WebeyColors.primaryGold.withAlpha(210),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'İşletmenin onayladığı kapora ödemelerinin toplamı.',
            style: TextStyle(
              color: Colors.white.withAlpha(160),
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletMiniCard extends StatelessWidget {
  const _WalletMiniCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 17,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _WalletTxnCard extends StatelessWidget {
  const _WalletTxnCard({
    required this.item,
    required this.amountText,
    required this.dateText,
  });
  final DepositWalletItem item;
  final String amountText;
  final String dateText;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (item.serviceName != null && item.serviceName!.isNotEmpty)
        item.serviceName!,
      if (dateText.isNotEmpty) dateText,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.businessName.isNotEmpty ? item.businessName : 'Salon',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 11.5,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                _WalletStatusChip(status: item.status, label: item.label),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amountText,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 14.5,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletStatusChip extends StatelessWidget {
  const _WalletStatusChip({required this.status, required this.label});
  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (status) {
      'paid' => WebeyColors.successGreen,
      'refunded' => WebeyColors.mutedTaupe,
      'not_received' => WebeyColors.errorRed,
      _ => WebeyColors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        label.isNotEmpty ? label : 'Bekliyor',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _WalletEmptyState extends StatelessWidget {
  const _WalletEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 34,
            color: WebeyColors.mutedTaupe,
          ),
          const SizedBox(height: 10),
          const Text(
            'Henüz kapora hareketin yok',
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 14,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Kaporalı randevu oluşturup ödeme bildirimi yaptığında hareketlerin burada görünecek.',
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

class AddressLocationScreen extends StatefulWidget {
  const AddressLocationScreen({super.key, this.profile});
  final CustomerProfile? profile;

  @override
  State<AddressLocationScreen> createState() => _AddressLocationScreenState();
}

class _AddressLocationScreenState extends State<AddressLocationScreen> {
  late final TextEditingController _city;
  late final TextEditingController _district;
  late final TextEditingController _neighborhood;
  late final TextEditingController _addressLine;
  var _saving = false;
  var _locationBusy = false;
  double? _latitude;
  double? _longitude;
  String? _locationMessage;

  @override
  void initState() {
    super.initState();
    _city = TextEditingController(text: widget.profile?.city ?? '');
    _district = TextEditingController(text: widget.profile?.district ?? '');
    _neighborhood = TextEditingController(
      text: widget.profile?.neighborhood ?? '',
    );
    _addressLine = TextEditingController(
      text: widget.profile?.addressLine ?? '',
    );
    _latitude = widget.profile?.latitude;
    _longitude = widget.profile?.longitude;
  }

  @override
  void dispose() {
    _city.dispose();
    _district.dispose();
    _neighborhood.dispose();
    _addressLine.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    if (_locationBusy) return;
    setState(() {
      _locationBusy = true;
      _locationMessage = 'Konumunuz alınıyor...';
    });
    try {
      final location = await WebeyLocationService.instance.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _city.text = location.city ?? _city.text;
        _district.text = location.district ?? _district.text;
        _neighborhood.text = location.neighborhood ?? _neighborhood.text;
        _addressLine.text = location.addressLine ?? _addressLine.text;
        _latitude = location.latitude;
        _longitude = location.longitude;
        _locationMessage = 'Konumunuz bulundu';
      });
    } on WebeyLocationException catch (error) {
      if (!mounted) return;
      setState(() => _locationMessage = error.message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      const message = 'Konum alınamadı. Bilgileri manuel girebilirsiniz.';
      setState(() => _locationMessage = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await CustomerProfileRepository.instance.updateProfile({
        'city': _city.text.trim(),
        'district': _district.text.trim(),
        'neighborhood': _neighborhood.text.trim(),
        'address_line': _addressLine.text.trim(),
        if (_latitude != null) 'latitude': _latitude,
        if (_longitude != null) 'longitude': _longitude,
      });
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adres bilgilerin güncellendi.')),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adres bilgileri kaydedilemedi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = _latitude != null && _longitude != null;
    return _ProfileInfoScaffold(
      title: 'Adres ve Konum',
      icon: Icons.location_on_outlined,
      children: [
        const _InfoCard(
          title: 'Konumunuzu kaydedin',
          body:
              'Konumunuzu kaydederek size yakın salonları daha doğru gösterebiliriz.',
        ),
        _LocationSummaryCard(
          hasLocation: hasLocation,
          city: _city.text,
          district: _district.text,
          neighborhood: _neighborhood.text,
          message: _locationMessage,
          busy: _locationBusy,
          onUseLocation: _locationBusy ? null : _useCurrentLocation,
        ),
        _ProfileTextField(label: 'Şehir', controller: _city),
        _ProfileTextField(label: 'İlçe', controller: _district),
        _ProfileTextField(label: 'Mahalle', controller: _neighborhood),
        _ProfileTextField(
          label: 'Açık adres (opsiyonel)',
          controller: _addressLine,
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _locationBusy ? null : _useCurrentLocation,
                icon: _locationBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded, size: 18),
                label: Text(
                  hasLocation ? 'Konumu yeniden al' : 'Konumumu Kullan',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? 'Kaydediliyor...' : 'Kaydet'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LocationSummaryCard extends StatelessWidget {
  const _LocationSummaryCard({
    required this.hasLocation,
    required this.city,
    required this.district,
    required this.neighborhood,
    required this.busy,
    required this.onUseLocation,
    this.message,
  });

  final bool hasLocation;
  final String city;
  final String district;
  final String neighborhood;
  final bool busy;
  final VoidCallback? onUseLocation;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final locationText = [
      city.trim(),
      district.trim(),
      neighborhood.trim(),
    ].where((part) => part.isNotEmpty).join(' / ');
    return _InfoCard(
      title: hasLocation ? 'Konum seçildi' : 'Konum bilgisi eksik',
      body: hasLocation
          ? [
              if (locationText.isNotEmpty) locationText,
              'Harita konumu kaydedildi',
              ?message,
            ].join('\n')
          : [
              'Size yakın salonları gösterebilmemiz için konumunuzu ekleyin.',
              ?message,
            ].join('\n'),
      actionLabel: busy
          ? 'Konumunuz alınıyor...'
          : (hasLocation ? 'Konumu yeniden al' : 'Konumumu Kullan'),
      onAction: busy ? null : onUseLocation,
    );
  }
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _repository = CustomerNotificationRepository.instance;

  static const _labels = <String, String>{
    'appointment_enabled': 'Randevu push bildirimleri',
    'review_enabled': 'Yorum bildirimleri',
    'payment_enabled': 'Kapora / ödeme bildirimleri',
    'system_enabled': 'Sistem bildirimleri',
    'appt_approved': 'Randevu onaylanınca bildirim',
    'appt_reminders': 'Randevu hatırlatmaları',
    'campaigns': 'Kampanya bildirimleri',
    'channel_push': 'Uygulama bildirimi',
    'channel_email': 'E-posta bildirimi',
    'channel_sms': 'SMS bildirimi',
    'sound': 'Ses',
    'vibration': 'Titreşim',
  };

  Map<String, dynamic> _values = {
    'appointment_enabled': true,
    'review_enabled': true,
    'payment_enabled': true,
    'system_enabled': true,
    'appt_approved': true,
    'appt_reminders': true,
    'campaigns': false,
    'channel_push': true,
    'channel_email': true,
    'channel_sms': false,
    'sound': true,
    'vibration': true,
    'sound_mode': 'sound',
  };

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final remote = await _repository.getPreferences();
    if (!mounted) return;
    setState(() {
      if (remote.isNotEmpty) _values = {..._values, ...remote};
      _loading = false;
    });
  }

  Future<void> _onToggle(String key, bool value) async {
    setState(() => _values[key] = value);
    await _repository.savePreferences(_values);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bildirim tercihleri güncellendi.')),
    );
  }

  Future<void> _setSoundMode(String mode) async {
    setState(() {
      _values['sound_mode'] = mode;
      _values['sound'] = mode == 'sound';
      _values['vibration'] = mode != 'silent';
    });
    await _repository.savePreferences(_values);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bildirim tercihleri güncellendi.')),
    );
  }

  Widget _soundModeTile(String mode, String title, String subtitle) {
    final selected = (_values['sound_mode'] ?? 'sound').toString() == mode;
    return ListTile(
      tileColor: WebeyColors.warmCream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? WebeyColors.primaryGold : WebeyColors.mutedTaupe,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () => _setSoundMode(mode),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ProfileInfoScaffold(
      title: 'Bildirim Ayarları',
      icon: Icons.notifications_none_rounded,
      children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          for (final key in _labels.keys)
            if (key != 'sound' && key != 'vibration')
              SwitchListTile(
                value: _values[key] == true,
                onChanged: (value) => _onToggle(key, value),
                title: Text(_labels[key] ?? key),
                tileColor: WebeyColors.warmCream,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                activeThumbColor: WebeyColors.primaryGold,
              ),
          _soundModeTile('sound', 'Sesli', 'Webey sesi ve titreşim'),
          _soundModeTile('vibrate', 'Sadece titreşim', 'Ses çalmaz'),
          _soundModeTile('silent', 'Sessiz', 'Ses ve titreşim yok'),
        ],
      ],
    );
  }
}

class _ProfileInfoScaffold extends StatelessWidget {
  const _ProfileInfoScaffold({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      appBar: AppBar(
        backgroundColor: WebeyColors.ivory,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title),
      ),
      body: ListView(
        // Alt input/Kaydet butonunun Android navigation bar altında ezilmemesi
        // için cihazın alt güvenli alan inset'i kadar ekstra boşluk bırakılır.
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          24 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          Icon(icon, size: 42, color: WebeyColors.primaryGold),
          const SizedBox(height: 16),
          ...children.map(
            (child) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(body, style: TextStyle(color: WebeyColors.mutedTaupe)),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  const _ProfileTextField({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: WebeyColors.softWhite,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
