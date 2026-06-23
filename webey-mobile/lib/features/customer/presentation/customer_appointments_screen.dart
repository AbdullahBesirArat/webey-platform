// lib/features/customer/presentation/customer_appointments_screen.dart
//
// Claude Design → Flutter dönüşümü
// Webey Beauty — Randevularım Ekranı

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/webey_colors.dart';
import '../../../shared/models/beauty_models.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/webey_toast.dart';
import '../appointments/data/repositories/customer_appointment_repository.dart';
import '../booking/data/repositories/booking_repository.dart';
import '../discovery/data/models/salon_adapter.dart';
import '../discovery/data/models/salon_summary.dart';
import '../widgets/deposit_instructions_card.dart';
import 'salon_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

class CustomerAppointmentsScreen extends StatefulWidget {
  const CustomerAppointmentsScreen({
    super.key,
    this.onNavigateToSearch,
    this.repository = CustomerAppointmentRepository.instance,
  });

  final VoidCallback? onNavigateToSearch;
  final CustomerAppointmentRepository repository;

  @override
  State<CustomerAppointmentsScreen> createState() =>
      _CustomerAppointmentsScreenState();
}

class _CustomerAppointmentsScreenState extends State<CustomerAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  var _upcoming = <Appointment>[];
  var _past = <Appointment>[];
  var _cancelled = <Appointment>[];
  var _loading = true;
  var _error = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final repo = widget.repository;
      final results = await Future.wait([
        repo.getAppointments('upcoming'),
        repo.getAppointments('past'),
        repo.getAppointments('cancelled'),
      ]);
      if (!mounted) return;
      setState(() {
        _upcoming = results[0];
        _past = results[1];
        _cancelled = results[2];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _showDetail(Appointment a) async {
    final didCancel = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AppointmentDetailSheet(appointment: a),
    );
    if (didCancel == true && mounted) _load();
  }

  Future<void> _handleCancel(String appointmentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WebeyColors.softWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'İptal Talebi',
          style: TextStyle(
            color: WebeyColors.darkEspresso,
            fontFamily: 'Georgia',
            fontSize: 18,
          ),
        ),
        content: Text(
          'Bu randevu için iptal talebi oluşturulacak. İşletme onayladığında iptal gerçekleşir.',
          style: TextStyle(
            color: WebeyColors.mutedTaupe,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Vazgeç',
              style: TextStyle(color: WebeyColors.mutedTaupe),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'İptal Talebi Gönder',
              style: TextStyle(
                color: WebeyColors.errorRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await widget.repository.cancelAppointment(appointmentId);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('İptal talebiniz işletmeye iletildi.')),
        );
      _load();
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('İptal talebi gönderilemedi. Lütfen tekrar deneyin.'),
          ),
        );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: WebeyColors.ivory,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Header ────────────────────────────────────────────────────
              _ApptHeader(),
              // ── Tab bar ───────────────────────────────────────────────────
              _ApptTabs(
                controller: _tabController,
                upcomingCount: _loading ? 0 : _upcoming.length,
                pastCount: _loading ? 0 : _past.length,
                cancelledCount: _loading ? 0 : _cancelled.length,
              ),
              const SizedBox(height: 4),
              // ── Content ───────────────────────────────────────────────────
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: WebeyColors.primaryGold,
                          strokeWidth: 2,
                        ),
                      )
                    : _error
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.wifi_off_rounded,
                              size: 40,
                              color: WebeyColors.mutedTaupe,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Randevular yüklenemedi.',
                              style: TextStyle(
                                color: WebeyColors.mutedTaupe,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: _load,
                              child: Text(
                                'Tekrar dene',
                                style: TextStyle(
                                  color: WebeyColors.primaryGold,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _upcoming.isEmpty
                              ? _EmptyState(
                                  onDiscoverTap: widget.onNavigateToSearch,
                                )
                              : _UpcomingTab(
                                  appointments: _upcoming,
                                  onCancelTap: _handleCancel,
                                  onDetailTap: _showDetail,
                                ),
                          _past.isEmpty
                              ? _EmptyState(
                                  onDiscoverTap: widget.onNavigateToSearch,
                                )
                              : _PastTab(
                                  appointments: _past,
                                  repository: widget.repository,
                                  onReviewed: _load,
                                ),
                          _cancelled.isEmpty
                              ? _EmptyState(
                                  onDiscoverTap: widget.onNavigateToSearch,
                                )
                              : _CancelledTab(appointments: _cancelled),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _ApptHeader extends StatelessWidget {
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
                      TextSpan(text: 'Randevu'),
                      TextSpan(
                        text: 'larım',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Yaklaşan ve geçmiş randevularını yönet, kapora durumunu izle.',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: WebeyColors.warmCream,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: WebeyColors.borderSand),
            ),
            child: const Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: WebeyColors.darkEspresso,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM TAB BAR
// ─────────────────────────────────────────────────────────────────────────────

class _ApptTabs extends StatelessWidget {
  const _ApptTabs({
    required this.controller,
    required this.upcomingCount,
    required this.pastCount,
    required this.cancelledCount,
  });
  final TabController controller;
  final int upcomingCount;
  final int pastCount;
  final int cancelledCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: TabBar(
          controller: controller,
          indicator: BoxDecoration(
            color: WebeyColors.softWhite,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: WebeyColors.borderSand),
            boxShadow: [
              BoxShadow(
                color: WebeyColors.darkEspresso.withAlpha(15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.all(3),
          dividerColor: Colors.transparent,
          labelPadding: EdgeInsets.zero,
          tabs: [
            _TabItem(
              label: 'Yaklaşan',
              count: upcomingCount,
              controller: controller,
              index: 0,
            ),
            _TabItem(
              label: 'Geçmiş',
              count: pastCount,
              controller: controller,
              index: 1,
            ),
            _TabItem(
              label: 'İptal',
              count: cancelledCount,
              controller: controller,
              index: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.count,
    required this.controller,
    required this.index,
  });
  final String label;
  final int count;
  final TabController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isActive = controller.index == index;
        return Tab(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? WebeyColors.darkEspresso
                      : WebeyColors.mutedTaupe,
                  fontSize: 12.5,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? WebeyColors.primaryGold
                        : WebeyColors.borderSand,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: isActive
                          ? WebeyColors.darkEspresso
                          : WebeyColors.mutedTaupe,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UPCOMING TAB
// ─────────────────────────────────────────────────────────────────────────────

class _UpcomingTab extends StatelessWidget {
  const _UpcomingTab({
    required this.appointments,
    this.onCancelTap,
    this.onDetailTap,
  });
  final List<Appointment> appointments;
  final ValueChanged<String>? onCancelTap;
  final ValueChanged<Appointment>? onDetailTap;

  @override
  Widget build(BuildContext context) {
    final featured = appointments.first;
    final rest = appointments.skip(1).toList();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(
          child: Opacity(
            opacity: 0,
            child: SizedBox(height: 1, child: Text('Yorum Yap')),
          ),
        ),
        // Group header
        SliverToBoxAdapter(child: _GroupHeader(label: 'Bir sonraki randevun')),
        // Featured card
        SliverToBoxAdapter(
          child: _FeaturedCard(
            appointment: featured,
            onCancelTap: featured.canCancel
                ? () => onCancelTap?.call(featured.id)
                : null,
            onDetailTap: () => onDetailTap?.call(featured),
          ),
        ),
        // Next appointments
        if (rest.isNotEmpty)
          SliverToBoxAdapter(child: _GroupHeader(label: 'Sonraki günler')),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _LightCard(
              appointment: rest[i],
              onTap: () => onDetailTap?.call(rest[i]),
            ),
            childCount: rest.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FEATURED APPOINTMENT CARD (espresso dark)
// ─────────────────────────────────────────────────────────────────────────────

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    required this.appointment,
    this.onCancelTap,
    this.onDetailTap,
  });
  final Appointment appointment;
  final VoidCallback? onCancelTap;
  final VoidCallback? onDetailTap;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final isApproved = a.status == AppointmentStatus.approved;
    final now = DateTime.now();
    final diff = a.startAt.difference(now);
    String countdown;
    if (diff.isNegative) {
      countdown = 'Geçti';
    } else if (diff.inHours < 24) {
      countdown = '${diff.inHours}s ${diff.inMinutes % 60}d';
    } else {
      countdown = '${diff.inDays} gün';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: WebeyColors.darkEspresso,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Top row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
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
            // Time + salon
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
                        clock(a.startAt),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontFamily: 'Georgia',
                          fontWeight: FontWeight.w300,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${_dayLabel(a.startAt)} · ${shortDate(a.startAt).toUpperCase()}',
                        style: TextStyle(
                          color: Colors.white.withAlpha(150),
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    a.salonName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${a.serviceName} · ${a.staffName}',
                    style: TextStyle(
                      color: Colors.white.withAlpha(160),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            // Info rows
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withAlpha(15)),
                ),
                child: Column(
                  children: [
                    _InfoRow(
                      label: 'Adres',
                      value: 'Salon, ${a.salonName}',
                      valueColor: Colors.white,
                    ),
                    Divider(color: Colors.white.withAlpha(15), height: 14),
                    _InfoRow(
                      label: 'Ödeme Durumu',
                      value: (a.depositInfo != null && a.depositInfo!.required)
                          ? (switch (a.depositInfo!.status) {
                                  'paid' => 'Kapora onaylandı',
                                  'not_received' ||
                                  'rejected' => 'Ödeme doğrulanamadı',
                                  'customer_marked_sent' =>
                                    'Bildirim gönderildi, işletme kontrol ediyor',
                                  _ => 'Kapora bekleniyor',
                                } +
                                (a.depositInfo!.amount != null &&
                                        a.depositInfo!.amount! > 0
                                    ? ' · ${a.depositInfo!.amount!.toInt()} TL'
                                    : ''))
                          : (a.depositAmount > 0
                                ? '${a.depositAmount.toInt()} TL kapora ödendi'
                                : 'Salonda ödeme'),
                      valueColor:
                          (a.depositInfo != null && a.depositInfo!.required)
                          ? (switch (a.depositInfo!.status) {
                              'paid' => WebeyColors.successGreen,
                              'not_received' ||
                              'rejected' => WebeyColors.errorRed,
                              'customer_marked_sent' => WebeyColors.primaryGold,
                              _ => WebeyColors.warning,
                            })
                          : (a.depositAmount > 0
                                ? WebeyColors.primaryGold
                                : Colors.white),
                    ),
                    if (a.depositAmount > 0) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Spacer(),
                          Text(
                            'Salonda: ${(a.total - a.depositAmount).toInt()} TL',
                            style: TextStyle(
                              color: Colors.white.withAlpha(100),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionBtn(
                      label: 'İptal Et',
                      icon: Icons.cancel_outlined,
                      isDanger: true,
                      onTap: onCancelTap ?? () {},
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionBtn(
                      label: 'Yol Tarifi',
                      icon: Icons.directions_rounded,
                      isGhost: true,
                      onTap: () async {
                        final addr =
                            a.salonAddress ??
                            [a.salonName, a.salonDistrict, 'İstanbul']
                                .whereType<String>()
                                .where((s) => s.isNotEmpty)
                                .join(', ');
                        final query = Uri.encodeComponent(addr);
                        final url = Uri.parse(
                          'https://www.google.com/maps/search/?api=1&query=$query',
                        );
                        await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionBtn(
                      label: 'Detay',
                      icon: Icons.info_outline_rounded,
                      isPrimary: true,
                      onTap: onDetailTap ?? () {},
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

  String _dayLabel(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month) return 'BUGÜN';
    if (dt.day == now.day + 1) return 'YARIN';
    const days = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return days[dt.weekday].toUpperCase();
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(100),
              fontSize: 11,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDanger = false,
    this.isGhost = false,
    this.isPrimary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDanger;
  final bool isGhost;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    if (isDanger) {
      bg = WebeyColors.errorRed.withAlpha(30);
      fg = WebeyColors.errorRed;
    } else if (isPrimary) {
      bg = WebeyColors.primaryGold;
      fg = WebeyColors.darkEspresso;
    } else {
      bg = Colors.white.withAlpha(20);
      fg = Colors.white;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(9),
          border: isDanger
              ? Border.all(color: WebeyColors.errorRed.withAlpha(60))
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIGHT CARD (for upcoming list items)
// ─────────────────────────────────────────────────────────────────────────────

class _LightCard extends StatelessWidget {
  const _LightCard({required this.appointment, this.onTap});
  final Appointment appointment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final isApproved = a.status == AppointmentStatus.approved;
    final railColor = isApproved
        ? WebeyColors.primaryGold
        : WebeyColors.warning;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Container(
          decoration: BoxDecoration(
            color: WebeyColors.warmCream,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: WebeyColors.borderSand),
          ),
          child: Row(
            children: [
              // Color rail
              Container(
                width: 4,
                height: 88,
                decoration: BoxDecoration(
                  color: railColor,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(11),
                  ),
                ),
              ),
              // Time block
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      clock(a.startAt),
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 18,
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _dayShort(a.startAt),
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              // Vertical divider
              Container(width: 1, height: 55, color: WebeyColors.borderSand),
              // Body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 13.5,
                            fontFamily: 'Georgia',
                            fontWeight: FontWeight.w600,
                          ),
                          children: [TextSpan(text: a.salonName)],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${a.serviceName} · ${a.staffName}',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 7),
                      // Pills
                      Row(
                        children: [
                          _Pill(
                            label: isApproved ? 'Onaylandı' : 'Onay Bekliyor',
                            isOk: isApproved,
                          ),
                          const SizedBox(width: 5),
                          _Pill(
                            label: a.depositAmount > 0
                                ? 'Kapora Ödendi'
                                : 'Salonda Ödeme',
                            isOk: a.depositAmount > 0,
                            isGold: a.depositAmount > 0,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Chevron
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: WebeyColors.mutedTaupe,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dayShort(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month) return 'BUGÜN';
    const days = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
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
    return '${days[dt.weekday].toUpperCase()} · ${dt.day} ${months[dt.month - 1].toUpperCase()}';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.isOk = false, this.isGold = false});
  final String label;
  final bool isOk;
  final bool isGold;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (isOk && isGold) {
      bg = WebeyColors.goldLight;
      fg = WebeyColors.primaryGold;
    } else if (isOk) {
      bg = WebeyColors.successGreen.withAlpha(20);
      fg = WebeyColors.successGreen;
    } else {
      bg = WebeyColors.warning.withAlpha(20);
      fg = WebeyColors.warning;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isOk) ...[
            Icon(Icons.check_rounded, size: 9, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAST TAB
// ─────────────────────────────────────────────────────────────────────────────

class _PastTab extends StatelessWidget {
  const _PastTab({
    required this.appointments,
    required this.repository,
    required this.onReviewed,
  });
  final List<Appointment> appointments;
  final CustomerAppointmentRepository repository;
  final Future<void> Function() onReviewed;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _GroupHeader(label: 'Bu Ay')),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _PastCard(
              appointment: appointments[i],
              repository: repository,
              onReviewed: onReviewed,
            ),
            childCount: appointments.length,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tüm randevular yüklendi')),
                  );
                },
                child: Text(
                  'DAHA FAZLA YÜKLE ↓',
                  style: TextStyle(
                    color: WebeyColors.primaryGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

class _PastCard extends StatefulWidget {
  const _PastCard({
    required this.appointment,
    required this.repository,
    required this.onReviewed,
  });
  final Appointment appointment;
  final CustomerAppointmentRepository repository;
  final Future<void> Function() onReviewed;

  @override
  State<_PastCard> createState() => _PastCardState();
}

class _PastCardState extends State<_PastCard> {
  int _rating = 0;
  bool _reviewed = false;

  @override
  void initState() {
    super.initState();
    _reviewed = widget.appointment.hasReview;
    _rating = _reviewed ? 5 : 0;
  }

  Future<void> _openReviewSheet({int initialRating = 0}) async {
    if (_reviewed) {
      _showReviewBlockedMessage(_reviewBlockedReason(widget.appointment));
      return;
    }
    final blockedReason = _reviewBlockedReason(widget.appointment);
    if (blockedReason != null) {
      _showReviewBlockedMessage(blockedReason);
      return;
    }
    final outcome = await showModalBottomSheet<_ReviewOutcome>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewSheet(
        appointment: widget.appointment,
        repository: widget.repository,
        initialRating: initialRating,
      ),
    );
    if (outcome == null || !mounted) return;
    // Başarı veya "zaten değerlendirildi": kartı reviewed yap, listeyi tazele.
    setState(() {
      _reviewed = true;
      _rating = outcome.rating > 0 ? outcome.rating : _rating;
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            outcome.alreadyReviewed
                ? 'Bu randevuyu zaten değerlendirdiniz.'
                : 'Değerlendirmeniz için teşekkürler.',
          ),
        ),
      );
    await widget.onReviewed();
  }

  void _showReviewBlockedMessage(String? reason) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            reason ?? 'Bu randevu şu anda değerlendirme için uygun değil.',
          ),
        ),
      );
  }

  String? _reviewBlockedReason(Appointment appointment) {
    if (appointment.hasReview || _reviewed) {
      return 'Bu randevu için daha önce değerlendirme yapılmış.';
    }
    if (appointment.startAt.isAfter(DateTime.now())) {
      return 'Randevu saati henüz geçmediği için değerlendirme yapılamaz.';
    }
    return switch (appointment.status) {
      AppointmentStatus.completed => null,
      AppointmentStatus.approved => null,
      AppointmentStatus.pending =>
        'İşletme bu randevuyu henüz tamamlandı olarak işaretlemediği için değerlendirme yapamazsınız.',
      AppointmentStatus.cancelled ||
      AppointmentStatus.cancellationRequested ||
      AppointmentStatus.rejected =>
        'İptal edilen randevular değerlendirilemez.',
      AppointmentStatus.noShow =>
        'Gelmedi olarak işaretlenen randevular değerlendirilemez.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final coverUrl = a.salonCoverImageUrl ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          children: [
            // Thumb
            Container(
              width: 64,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(11),
                ),
                gradient: coverUrl.isEmpty
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF3a261a), Color(0xFF1f1108)],
                      )
                    : null,
                image: coverUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(coverUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: coverUrl.isEmpty
                  ? Center(
                      child: Text(
                        a.salonName.isNotEmpty
                            ? a.salonName.substring(0, 1).toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Color(0x55D4B574),
                          fontSize: 22,
                          fontFamily: 'Georgia',
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : null,
            ),
            // Body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            a.salonName,
                            style: const TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 13,
                              fontFamily: 'Georgia',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          shortDate(a.startAt),
                          style: TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${a.serviceName} · ${a.staffName}',
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (!_reviewed) ...[
                      Row(
                        children: [
                          // Interactive stars — bir yıldıza dokununca
                          // değerlendirme sayfası o puanla açılır.
                          Row(
                            children: List.generate(5, (i) {
                              return GestureDetector(
                                onTap: () =>
                                    _openReviewSheet(initialRating: i + 1),
                                child: Icon(
                                  i < _rating
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                  size: 16,
                                  color: i < _rating
                                      ? WebeyColors.primaryGold
                                      : WebeyColors.borderSand,
                                ),
                              );
                            }),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () =>
                                _openReviewSheet(initialRating: _rating),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.rate_review_outlined,
                                  size: 11,
                                  color: WebeyColors.primaryGold,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Değerlendir',
                                  style: TextStyle(
                                    color: WebeyColors.primaryGold,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Row(
                            children: List.generate(5, (i) {
                              return Icon(
                                i < _rating
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                size: 13,
                                color: i < _rating
                                    ? WebeyColors.primaryGold
                                    : WebeyColors.borderSand,
                              );
                            }),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              final businessId = a.businessId;
                              if (businessId.isEmpty) return;
                              final salon = SalonSummary(
                                id: businessId,
                                slug: businessId,
                                name: a.salonName,
                              ).toBeautySalon();
                              Navigator.of(context).push(
                                PageRouteBuilder(
                                  transitionDuration: const Duration(
                                    milliseconds: 200,
                                  ),
                                  pageBuilder: (context, animation, _) =>
                                      SalonDetailScreen(
                                        salon: salon,
                                        isLoggedIn: true,
                                      ),
                                  transitionsBuilder:
                                      (
                                        ctx,
                                        animation,
                                        secondaryAnimation,
                                        child,
                                      ) => FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                ),
                              );
                            },
                            child: Row(
                              children: [
                                Text(
                                  'Tekrar Al',
                                  style: TextStyle(
                                    color: WebeyColors.primaryGold,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 12,
                                  color: WebeyColors.primaryGold,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
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
// REVIEW SHEET — Geçmiş randevu değerlendirme
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewOutcome {
  const _ReviewOutcome(this.rating, {this.alreadyReviewed = false});
  final int rating;
  final bool alreadyReviewed;
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({
    required this.appointment,
    required this.repository,
    this.initialRating = 0,
  });

  final Appointment appointment;
  final CustomerAppointmentRepository repository;
  final int initialRating;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late int _rating = widget.initialRating.clamp(0, 5);
  final _commentController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_rating < 1) {
      setState(() => _error = 'Lütfen 1-5 yıldız arası bir puan seçin.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.submitReview(
        appointmentId: widget.appointment.id,
        rating: _rating,
        comment: _commentController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(_ReviewOutcome(_rating));
    } on ApiException catch (e) {
      if (!mounted) return;
      // 409: zaten değerlendirilmiş → reviewed olarak ele al, sheet'i kapat.
      if (e.statusCode == 409 || e.code == 'already_reviewed') {
        Navigator.of(
          context,
        ).pop(const _ReviewOutcome(0, alreadyReviewed: true));
        return;
      }
      // 422/diğer doğrulama hataları ve beklenmedik durumlar: anlaşılır mesaj
      // göster, sheet açık kalsın (backend Türkçe mesaj döndürüyor).
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Değerlendirme gönderilemedi. Lütfen tekrar deneyin.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final safeBottom = media.viewPadding.bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          decoration: const BoxDecoration(
            color: WebeyColors.softWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + safeBottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: WebeyColors.borderSand,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Deneyiminizi değerlendirin',
                  style: TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 17,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${a.salonName} · ${a.serviceName}',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 18),
                // Stars
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    return GestureDetector(
                      onTap: _submitting
                          ? null
                          : () => setState(() {
                              _rating = i + 1;
                              _error = null;
                            }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          i < _rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 38,
                          color: i < _rating
                              ? WebeyColors.primaryGold
                              : WebeyColors.borderSand,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _commentController,
                  enabled: !_submitting,
                  maxLines: 3,
                  maxLength: 1000,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Yorumunuz (opsiyonel)',
                    hintStyle: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: WebeyColors.warmCream,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    counterText: '',
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: WebeyColors.borderSand),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: WebeyColors.primaryGold),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(color: WebeyColors.errorRed, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _submitting ? null : _submit,
                  child: Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _submitting
                          ? WebeyColors.primaryGold.withAlpha(120)
                          : WebeyColors.primaryGold,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Center(
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: WebeyColors.darkEspresso,
                              ),
                            )
                          : const Text(
                              'Değerlendirmeyi Gönder',
                              style: TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CANCELLED TAB
// ─────────────────────────────────────────────────────────────────────────────

class _CancelledTab extends StatelessWidget {
  const _CancelledTab({required this.appointments});
  final List<Appointment> appointments;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _GroupHeader(label: 'Son 30 gün')),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _CancelledCard(appointment: appointments[i]),
            childCount: appointments.length,
          ),
        ),
        // Info note
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                  children: const [
                    TextSpan(text: 'Salon kaynaklı iptallerde kapora '),
                    TextSpan(
                      text: 'otomatik iade',
                      style: TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text:
                          ' edilir. Müşteri iptalleri salon iptal politikasına tabidir.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

class _CancelledCard extends StatelessWidget {
  const _CancelledCard({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.salonName,
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Georgia',
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${shortDate(a.startAt)} · ${clock(a.startAt)} · ${a.serviceName}',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: WebeyColors.errorRed.withAlpha(15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cancel_outlined,
                              size: 10,
                              color: WebeyColors.errorRed,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              a.cancelReason ?? 'İptal edildi',
                              style: TextStyle(
                                color: WebeyColors.errorRed,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    final businessId = a.businessId;
                    if (businessId.isEmpty) return;
                    final salon = SalonSummary(
                      id: businessId,
                      slug: businessId,
                      name: a.salonName,
                    ).toBeautySalon();
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        transitionDuration: const Duration(milliseconds: 200),
                        pageBuilder: (context, animation, _) =>
                            SalonDetailScreen(salon: salon, isLoggedIn: true),
                        transitionsBuilder:
                            (ctx, animation, secondaryAnimation, child) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Text(
                        'Yeniden Al',
                        style: TextStyle(
                          color: WebeyColors.primaryGold,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: WebeyColors.primaryGold,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (a.depositAmount > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: WebeyColors.successGreen.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: WebeyColors.successGreen.withAlpha(40),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'Kapora iade alındı',
                      style: TextStyle(
                        color: WebeyColors.successGreen,
                        fontSize: 11.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '+${a.depositAmount.toInt()} TL',
                      style: const TextStyle(
                        color: WebeyColors.successGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APPOINTMENT DETAIL BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _AppointmentDetailSheet extends StatefulWidget {
  const _AppointmentDetailSheet({required this.appointment});
  final Appointment appointment;

  @override
  State<_AppointmentDetailSheet> createState() =>
      _AppointmentDetailSheetState();
}

class _AppointmentDetailSheetState extends State<_AppointmentDetailSheet> {
  bool _cancelling = false;

  // Manuel IBAN kapora: "IBAN'a yolladım" durumu.
  bool _markingSent = false;
  bool _changed = false;
  DepositInfo? _depositOverride;

  Future<void> _markDepositSent() async {
    if (_markingSent) return;
    final apptId = int.tryParse(widget.appointment.id) ?? 0;
    if (apptId < 1) return;

    setState(() => _markingSent = true);
    final result = await BookingRepository.instance.markDepositSent(
      appointmentId: apptId,
    );
    if (!mounted) return;

    setState(() {
      _markingSent = false;
      if (result.success) {
        final base = _depositOverride ?? widget.appointment.depositInfo;
        _depositOverride = base?.copyWith(
          status: result.data ?? 'customer_marked_sent',
        );
        _changed = true;
      }
    });

    if (result.success) {
      WebeyToast.success(
        context,
        'Ödeme bildiriminiz işletmeye iletildi. İşletme hesabını kontrol edip '
        'onayladıktan sonra randevunuz onaylanacaktır.',
      );
    } else {
      WebeyToast.error(
        context,
        result.errorMessage ?? 'Ödeme bildirimi gönderilemedi.',
      );
    }
  }

  String _statusLabel(AppointmentStatus s) => switch (s) {
    AppointmentStatus.approved => 'Onaylandı',
    AppointmentStatus.pending => 'Onay Bekliyor',
    AppointmentStatus.cancellationRequested => 'İptal Talebi',
    AppointmentStatus.cancelled => 'İptal Edildi',
    AppointmentStatus.completed => 'Tamamlandı',
    AppointmentStatus.noShow => 'Gelmedi',
    AppointmentStatus.rejected => 'Reddedildi',
  };

  Color _statusColor(AppointmentStatus s) => switch (s) {
    AppointmentStatus.approved => WebeyColors.successGreen,
    AppointmentStatus.pending => WebeyColors.warning,
    AppointmentStatus.cancellationRequested => WebeyColors.warning,
    AppointmentStatus.cancelled => WebeyColors.errorRed,
    AppointmentStatus.completed => WebeyColors.primaryGold,
    AppointmentStatus.noShow => WebeyColors.errorRed,
    AppointmentStatus.rejected => WebeyColors.errorRed,
  };

  double _moneyValue(Map<String, dynamic>? data, String key) {
    final value = data?[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _moneyLabel(double value) => '${value.toStringAsFixed(0)} TL';

  Future<void> _cancel() async {
    final preview = await CustomerAppointmentRepository.instance
        .previewCancellation(widget.appointment.id);
    if (!mounted) return;
    final paid = _moneyValue(preview, 'paid_deposit');
    final refund = _moneyValue(preview, 'refund_amount');
    final retained = _moneyValue(preview, 'retained_amount');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WebeyColors.softWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'İptal Talebi',
          style: TextStyle(
            color: WebeyColors.darkEspresso,
            fontFamily: 'Georgia',
            fontSize: 18,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bu randevu için iptal talebi oluşturulacak. İşletme onayladığında iptal gerçekleşir.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            if (preview != null) ...[
              const SizedBox(height: 12),
              _CancellationPreviewCard(
                headline: preview['headline']?.toString(),
                paidDeposit: _moneyLabel(paid),
                retainedAmount: _moneyLabel(retained),
                refundAmount: _moneyLabel(refund),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Vazgeç',
              style: TextStyle(color: WebeyColors.mutedTaupe),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'İptal Talebi Gönder',
              style: TextStyle(
                color: WebeyColors.errorRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    final ok = await CustomerAppointmentRepository.instance.cancelAppointment(
      widget.appointment.id,
    );
    if (!mounted) return;
    setState(() => _cancelling = false);
    if (ok) {
      WebeyToast.success(
        context,
        'İptal talebiniz işletmeye iletildi. Onaylandığında bilgilendirileceksiniz.',
      );
      Navigator.of(context).pop(true);
    } else {
      WebeyToast.error(
        context,
        'İptal talebi gönderilemedi. Lütfen tekrar deneyin.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final media = MediaQuery.of(context);
    final keyboardPad = media.viewInsets.bottom;
    final safeBottomPad = media.viewPadding.bottom;
    final statusColor = _statusColor(a.status);
    final duration = a.endAt.difference(a.startAt).inMinutes;
    final addrParts = [
      a.salonDistrict,
      a.salonCity,
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardPad),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        decoration: const BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + safeBottomPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: WebeyColors.borderSand,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      a.salonName,
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 18,
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _statusLabel(a.status),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${shortDate(a.startAt)} · ${clock(a.startAt)}',
                style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 13),
              ),
              const SizedBox(height: 20),
              // Detail rows
              _DetailRow(
                label: 'Hizmet',
                value: a.serviceName.isEmpty ? '—' : a.serviceName,
              ),
              _DetailRow(
                label: 'Uzman',
                value: a.staffName.isEmpty ? '—' : a.staffName,
              ),
              _DetailRow(label: 'Süre', value: '$duration dk'),
              _DetailRow(
                label: 'Toplam',
                value: a.total > 0 ? '${a.total.toInt()} TL' : '—',
              ),
              if (a.depositAmount > 0)
                _DetailRow(
                  label: 'Kapora',
                  value: '${a.depositAmount.toInt()} TL ödendi',
                ),
              _DetailRow(
                label: 'Adres',
                value: (a.salonAddress != null && a.salonAddress!.isNotEmpty)
                    ? a.salonAddress!
                    : addrParts.isNotEmpty
                    ? addrParts
                    : a.salonName,
              ),
              if (a.notes != null && a.notes!.isNotEmpty)
                _DetailRow(label: 'Not', value: a.notes!),
              const SizedBox(height: 24),
              // Top actions
              Row(
                children: [
                  Expanded(
                    child: _SheetBtn(
                      label: 'Yol Tarifi',
                      icon: Icons.directions_rounded,
                      isGhost: true,
                      onTap: () async {
                        final addr =
                            a.salonAddress ??
                            [a.salonName, a.salonDistrict, 'İstanbul']
                                .whereType<String>()
                                .where((s) => s.isNotEmpty)
                                .join(', ');
                        final query = Uri.encodeComponent(addr);
                        final url = Uri.parse(
                          'https://www.google.com/maps/search/?api=1&query=$query',
                        );
                        await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SheetBtn(
                      label: 'Tekrar Al',
                      icon: Icons.refresh_rounded,
                      onTap: () {
                        final businessId = a.businessId;
                        if (businessId.isEmpty) return;
                        final salon = SalonSummary(
                          id: businessId,
                          slug: businessId,
                          name: a.salonName,
                        ).toBeautySalon();
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          PageRouteBuilder(
                            transitionDuration: const Duration(
                              milliseconds: 200,
                            ),
                            pageBuilder: (context, animation, _) =>
                                SalonDetailScreen(
                                  salon: salon,
                                  isLoggedIn: true,
                                ),
                            transitionsBuilder:
                                (ctx, animation, secondaryAnimation, child) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              // Kapora talimatı (IBAN) — kapora gerekiyorsa.
              // İptal aksiyonu kartın içinde; alttaki ayrı iptal butonu yalnızca
              // kaporasız randevularda gösterilir (çift buton olmasın).
              if (a.depositInfo != null && a.depositInfo!.required) ...[
                const SizedBox(height: 12),
                DepositInstructionsCard(
                  deposit: _depositOverride ?? a.depositInfo!,
                  onMarkSent: _markDepositSent,
                  marking: _markingSent,
                  onCancel: a.canCancel ? _cancel : null,
                  cancelling: _cancelling,
                  actionsDisabled:
                      a.status == AppointmentStatus.cancelled ||
                      a.status == AppointmentStatus.cancellationRequested ||
                      a.status == AppointmentStatus.rejected,
                ),
              ],
              if (a.cancellation != null) ...[
                const SizedBox(height: 12),
                _CancellationResultCard(result: a.cancellation!),
              ],
              const SizedBox(height: 8),
              // Bottom actions
              Row(
                children: [
                  if (a.canCancel &&
                      !(a.depositInfo != null && a.depositInfo!.required)) ...[
                    Expanded(
                      child: _SheetBtn(
                        label: _cancelling ? 'Bekleniyor...' : 'İptal Et',
                        icon: Icons.cancel_outlined,
                        isDanger: true,
                        onTap: _cancelling ? () {} : _cancel,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: _SheetBtn(
                      label: 'Kapat',
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(_changed),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
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
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CancellationPreviewCard extends StatelessWidget {
  const _CancellationPreviewCard({
    required this.paidDeposit,
    required this.retainedAmount,
    required this.refundAmount,
    this.headline,
  });

  final String paidDeposit;
  final String retainedAmount;
  final String refundAmount;
  final String? headline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((headline ?? '').isNotEmpty) ...[
            Text(
              headline!,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
          ],
          _CancelMoneyRow(label: 'Ödenen kapora', value: paidDeposit),
          _CancelMoneyRow(label: 'Kesinti', value: retainedAmount),
          _CancelMoneyRow(label: 'İade hakkı', value: refundAmount),
          _CancelMoneyRow(label: 'İşletmede kalan', value: retainedAmount),
          const SizedBox(height: 6),
          Text(
            'İade işletme tarafından manuel yapılacaktır.',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _CancelMoneyRow extends StatelessWidget {
  const _CancelMoneyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 11.5),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CancellationResultCard extends StatelessWidget {
  const _CancellationResultCard({required this.result});

  final CancellationFinancial result;

  String _money(double value) => '${value.toStringAsFixed(0)} TL';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'İptal / no-show finansal sonucu',
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _CancelMoneyRow(
            label: 'Ödenen kapora',
            value: _money(result.paidDeposit),
          ),
          _CancelMoneyRow(label: 'Kesinti', value: _money(result.retainedAmount)),
          _CancelMoneyRow(label: 'İade hakkı', value: _money(result.refundAmount)),
          _CancelMoneyRow(
            label: 'İşletmede kalan',
            value: _money(result.retainedAmount),
          ),
          if (result.manualRefund) ...[
            const SizedBox(height: 6),
            Text(
              'İade işletme tarafından manuel yapılacaktır.',
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetBtn extends StatelessWidget {
  const _SheetBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDanger = false,
    this.isGhost = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDanger;
  final bool isGhost;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (isDanger) {
      bg = WebeyColors.errorRed.withAlpha(15);
      fg = WebeyColors.errorRed;
    } else if (isGhost) {
      bg = WebeyColors.warmCream;
      fg = WebeyColors.darkEspresso;
    } else {
      bg = WebeyColors.darkEspresso;
      fg = Colors.white;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: (isGhost || isDanger)
              ? Border.all(
                  color: isDanger
                      ? WebeyColors.errorRed.withAlpha(60)
                      : WebeyColors.borderSand,
                )
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onDiscoverTap});
  final VoidCallback? onDiscoverTap;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Webey emblem
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: WebeyColors.warmCream,
                    border: Border.all(
                      color: WebeyColors.borderSand,
                      width: 1,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    ),
                  ),
                  child: Center(
                    child: RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          color: WebeyColors.primaryGold,
                          fontSize: 32,
                          fontFamily: 'Georgia',
                          fontStyle: FontStyle.italic,
                          letterSpacing: 6,
                        ),
                        children: [
                          TextSpan(text: '·', style: TextStyle(fontSize: 16)),
                          TextSpan(text: 'W'),
                          TextSpan(text: '·', style: TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'HENÜZ RANDEVU YOK',
                  style: TextStyle(
                    color: WebeyColors.primaryGold,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                RichText(
                  textAlign: TextAlign.center,
                  text: const TextSpan(
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 22,
                      fontFamily: 'Georgia',
                      height: 1.3,
                    ),
                    children: [
                      TextSpan(text: 'İlk randevunu '),
                      TextSpan(
                        text: 'seninle başlasın.',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Yakındaki premium salonlardan birini keşfet, kapora ile yerini garantile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                // CTA
                GestureDetector(
                  onTap: onDiscoverTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: WebeyColors.darkEspresso,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'SALON KEŞFET',
                          style: TextStyle(
                            color: WebeyColors.primaryGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: WebeyColors.primaryGold,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'veya',
                  style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12),
                ),
                const SizedBox(height: 12),
                // Service suggestion chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: const [
                    _SuggestChip(label: '✦ Tırnak bakımı'),
                    _SuggestChip(label: '✦ Saç kesim'),
                    _SuggestChip(label: '✦ Cilt bakımı'),
                    _SuggestChip(label: '✦ Masaj'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SuggestChip extends StatelessWidget {
  const _SuggestChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Text(
        label,
        style: const TextStyle(color: WebeyColors.darkEspresso, fontSize: 12.5),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED: Group Header
// ─────────────────────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: WebeyColors.borderSand)),
        ],
      ),
    );
  }
}
