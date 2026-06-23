// lib/features/customer/presentation/customer_notifications_screen.dart
//
// Claude Design → Flutter dönüşümü
// Webey Beauty — Bildirimler Ekranı (dolu + boş durum)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/webey_colors.dart';
import '../notifications/data/models/customer_notification.dart';
import '../notifications/data/repositories/customer_notification_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

enum _NotifType { appointment, deposit, favourite, campaign, system }

class _Notif {
  _Notif({
    required this.id,
    required this.type,
    required this.title,
    required this.titleEmphasis,
    required this.body,
    required this.time,
    required this.group,
    this.appointmentId,
    this.ctaLabel,
    this.ctaIcon,
    this.isRead = false,
  });
  final String id, title, titleEmphasis, body, time, group;
  final _NotifType type;
  final String? appointmentId;
  final String? ctaLabel;
  final IconData? ctaIcon;
  bool isRead;
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

class CustomerNotificationsScreen extends StatefulWidget {
  const CustomerNotificationsScreen({
    super.key,
    this.onOpenAppointments,
    this.onOpenSearch,
    this.repository = CustomerNotificationRepository.instance,
  });

  final VoidCallback? onOpenAppointments;
  final VoidCallback? onOpenSearch;
  final CustomerNotificationRepository repository;

  @override
  State<CustomerNotificationsScreen> createState() =>
      _CustomerNotificationsScreenState();
}

class _CustomerNotificationsScreenState
    extends State<CustomerNotificationsScreen> {
  var _notifs = <_Notif>[];
  String _filter = 'all';
  var _loading = true;

  static const _filters = [
    (id: 'all', label: 'Tümü'),
    (id: 'unread', label: 'Okunmamış'),
    (id: 'appt', label: 'Randevu'),
    (id: 'deposit', label: 'Kapora'),
    (id: 'fav', label: 'Favoriler'),
  ];

  @override
  void initState() {
    super.initState();
    _loadNotifs();
  }

  Future<void> _loadNotifs() async {
    final result = await widget.repository.getNotifications();
    if (!mounted) return;
    setState(() {
      _notifs = result.items.map(_toNotif).toList();
      _loading = false;
    });
  }

  _Notif _toNotif(CustomerNotification n) {
    final hasAppointment =
        n.appointmentId != null && n.appointmentId!.isNotEmpty;
    final isDeposit = n.type.startsWith('deposit');
    // Randevu bildirimleri 'appt_*' tipiyle gelebilir; bekleyen "iletildi"
    // bildirimi 'info' tipinde ama data.appointment_id tasir. Her iki durumda
    // da randevu bildirimi say ve "Randevuyu Gor" aksiyonunu goster.
    final isAppt = !isDeposit && (n.type.startsWith('appt_') || hasAppointment);

    final type = isAppt
        ? _NotifType.appointment
        : isDeposit
        ? _NotifType.deposit
        : _NotifType.system;

    String group = 'DÜNDEN ÖNCE';
    String time = '';
    if (n.createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(n.createdAt);
        final now = DateTime.now();
        final diff = now.difference(dt);
        if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
          group = 'BUGÜN';
          if (diff.inMinutes < 60) {
            time = '${diff.inMinutes} dk önce';
          } else {
            time = '${diff.inHours} saat önce';
          }
        } else {
          time = '${dt.day}.${dt.month.toString().padLeft(2, '0')}';
        }
      } catch (_) {}
    }

    final lastSpace = n.title.lastIndexOf(' ');
    final mainTitle = lastSpace > 0
        ? n.title.substring(0, lastSpace + 1)
        : n.title;
    final emphasis = lastSpace > 0 ? n.title.substring(lastSpace + 1) : '';

    return _Notif(
      id: n.id,
      type: type,
      title: mainTitle,
      titleEmphasis: emphasis,
      body: n.body,
      time: time,
      group: group,
      appointmentId: n.appointmentId,
      isRead: n.read,
      ctaLabel: isAppt ? 'RANDEVUYU GÖR' : null,
      ctaIcon: isAppt ? Icons.calendar_today_outlined : null,
    );
  }

  int get _unreadCount => _notifs.where((n) => !n.isRead).length;

  List<_Notif> get _filtered {
    switch (_filter) {
      case 'unread':
        return _notifs.where((n) => !n.isRead).toList();
      case 'appt':
        return _notifs.where((n) => n.type == _NotifType.appointment).toList();
      case 'deposit':
        return _notifs.where((n) => n.type == _NotifType.deposit).toList();
      case 'fav':
        return _notifs.where((n) => n.type == _NotifType.favourite).toList();
      default:
        return _notifs;
    }
  }

  void _markAllRead() {
    setState(() {
      for (final n in _notifs) {
        n.isRead = true;
      }
    });
    widget.repository.markAllAsRead();
  }

  void _markRead(String id) {
    setState(() {
      _notifs.firstWhere((n) => n.id == id).isRead = true;
    });
    widget.repository.markAsRead(id);
  }

  Map<String, List<_Notif>> get _grouped {
    final result = <String, List<_Notif>>{};
    for (final n in _filtered) {
      result.putIfAbsent(n.group, () => []).add(n);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _filtered.isEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: WebeyColors.ivory,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Header ───────────────────────────────────────────────────
              _NotifHeader(
                onBack: () => Navigator.maybePop(context),
                onFilter: () {},
              ),
              // ── Unread summary banner ─────────────────────────────────────
              if (_unreadCount > 0 && _filter == 'all')
                _UnreadBanner(count: _unreadCount, onMarkAll: _markAllRead),
              // ── Filter chips ──────────────────────────────────────────────
              _FilterChips(
                filters: _filters,
                activeFilter: _filter,
                unreadCount: _unreadCount,
                totalCount: _notifs.length,
                onChanged: (f) => setState(() => _filter = f),
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
                    : isEmpty
                    ? _EmptyState(onDiscoverTap: widget.onOpenSearch)
                    : _NotifList(
                        grouped: _grouped,
                        onMarkRead: _markRead,
                        onOpenAppointments: widget.onOpenAppointments,
                        onOpenSearch: widget.onOpenSearch,
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

class _NotifHeader extends StatelessWidget {
  const _NotifHeader({required this.onBack, required this.onFilter});
  final VoidCallback onBack, onFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: const Icon(
                Icons.chevron_left_rounded,
                size: 20,
                color: WebeyColors.darkEspresso,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 22,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w600,
                    ),
                    children: [
                      TextSpan(text: 'Bildirim'),
                      TextSpan(
                        text: 'ler',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Randevu ve salon güncellemeleriniz',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onFilter,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: const Icon(
                Icons.tune_rounded,
                size: 16,
                color: WebeyColors.darkEspresso,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UNREAD BANNER
// ─────────────────────────────────────────────────────────────────────────────

class _UnreadBanner extends StatelessWidget {
  const _UnreadBanner({required this.count, required this.onMarkAll});
  final int count;
  final VoidCallback onMarkAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: WebeyColors.primaryGold,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count okunmamış bildirim',
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Randevu, kapora ve favori salon bildirimlerinizi buradan takip edin.',
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onMarkAll,
              child: Column(
                children: [
                  Text(
                    'TÜMÜNÜ OKUNDU',
                    style: TextStyle(
                      color: WebeyColors.primaryGold,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'İŞARETLE',
                    style: TextStyle(
                      color: WebeyColors.primaryGold,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Icon(
                    Icons.check_rounded,
                    size: 11,
                    color: WebeyColors.primaryGold,
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

// ─────────────────────────────────────────────────────────────────────────────
// FILTER CHIPS
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.filters,
    required this.activeFilter,
    required this.unreadCount,
    required this.totalCount,
    required this.onChanged,
  });
  final List<({String id, String label})> filters;
  final String activeFilter;
  final int unreadCount;
  final int totalCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 34,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: filters.length,
          itemBuilder: (_, i) {
            final f = filters[i];
            final isActive = activeFilter == f.id;
            final showBadge = f.id == 'unread' && unreadCount > 0;
            return GestureDetector(
              onTap: () => onChanged(f.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: isActive
                      ? WebeyColors.primaryGold
                      : WebeyColors.softWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? WebeyColors.primaryGold
                        : WebeyColors.borderSand,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      f.label,
                      style: TextStyle(
                        color: isActive
                            ? WebeyColors.darkEspresso
                            : WebeyColors.darkEspresso,
                        fontSize: 12.5,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (showBadge || (f.id == 'all' && unreadCount > 0)) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? WebeyColors.darkEspresso
                              : WebeyColors.primaryGold,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          f.id == 'all' ? '$totalCount' : '$unreadCount',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
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
// NOTIFICATION LIST
// ─────────────────────────────────────────────────────────────────────────────

class _NotifList extends StatelessWidget {
  const _NotifList({
    required this.grouped,
    required this.onMarkRead,
    required this.onOpenAppointments,
    required this.onOpenSearch,
  });
  final Map<String, List<_Notif>> grouped;
  final ValueChanged<String> onMarkRead;
  final VoidCallback? onOpenAppointments;
  final VoidCallback? onOpenSearch;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        for (final entry in grouped.entries) ...[
          // Group label
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Text(
                entry.key,
                style: TextStyle(
                  color: WebeyColors.mutedTaupe,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          // Cards
          SliverList(
            delegate: SliverChildBuilderDelegate((context, i) {
              final n = entry.value[i];
              return _NotifCard(
                notif: n,
                onTap: () => onMarkRead(n.id),
                onCta: () {
                  onMarkRead(n.id);
                  if (n.type == _NotifType.appointment) {
                    // Bildirimler ekrani Navigator ile push edildigi icin,
                    // alttaki sekmeyi degistirmeden once bu rotayi kapat;
                    // aksi halde sekme degissin de gorunmez (eski hata).
                    Navigator.of(context).pop();
                    onOpenAppointments?.call();
                  } else if (n.type == _NotifType.favourite ||
                      n.type == _NotifType.campaign) {
                    Navigator.of(context).pop();
                    onOpenSearch?.call();
                  }
                },
              );
            }, childCount: entry.value.length),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION CARD
// ─────────────────────────────────────────────────────────────────────────────

class _NotifCard extends StatelessWidget {
  const _NotifCard({
    required this.notif,
    required this.onTap,
    required this.onCta,
  });
  final _Notif notif;
  final VoidCallback onTap;
  final VoidCallback onCta;

  Color get _railColor {
    switch (notif.type) {
      case _NotifType.appointment:
        return WebeyColors.primaryGold;
      case _NotifType.deposit:
        return WebeyColors.successGreen;
      case _NotifType.favourite:
        return WebeyColors.blushRose;
      case _NotifType.campaign:
        return const Color(0xFFB8964E);
      case _NotifType.system:
        return WebeyColors.mutedTaupe;
    }
  }

  Color get _iconBg {
    switch (notif.type) {
      case _NotifType.appointment:
        return WebeyColors.goldLight;
      case _NotifType.deposit:
        return WebeyColors.successGreen.withAlpha(20);
      case _NotifType.favourite:
        return WebeyColors.blushRose.withAlpha(30);
      case _NotifType.campaign:
        return WebeyColors.goldLight;
      case _NotifType.system:
        return WebeyColors.warmCream;
    }
  }

  IconData get _icon {
    switch (notif.type) {
      case _NotifType.appointment:
        return Icons.calendar_today_outlined;
      case _NotifType.deposit:
        return Icons.check_circle_outline_rounded;
      case _NotifType.favourite:
        return Icons.favorite_border_rounded;
      case _NotifType.campaign:
        return Icons.local_offer_outlined;
      case _NotifType.system:
        return Icons.star_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        decoration: BoxDecoration(
          color: notif.isRead ? WebeyColors.softWhite : WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notif.isRead
                ? WebeyColors.borderSand
                : WebeyColors.primaryGold.withAlpha(60),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left rail
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: notif.isRead ? Colors.transparent : _railColor,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(11),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 13, 12, 13),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _iconBg,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(_icon, size: 17, color: _railColor),
                      ),
                      const SizedBox(width: 10),
                      // Text + CTA
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      style: TextStyle(
                                        color: WebeyColors.darkEspresso,
                                        fontSize: 13,
                                        fontWeight: notif.isRead
                                            ? FontWeight.w500
                                            : FontWeight.w600,
                                      ),
                                      children: [
                                        TextSpan(text: notif.title),
                                        TextSpan(
                                          text: notif.titleEmphasis,
                                          style: const TextStyle(
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  children: [
                                    Text(
                                      notif.time,
                                      style: TextStyle(
                                        color: WebeyColors.mutedTaupe,
                                        fontSize: 10,
                                      ),
                                    ),
                                    if (!notif.isRead) ...[
                                      const SizedBox(width: 5),
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: WebeyColors.primaryGold,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              notif.body,
                              style: TextStyle(
                                color: WebeyColors.mutedTaupe,
                                fontSize: 12,
                                height: 1.45,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (notif.ctaLabel != null) ...[
                              const SizedBox(height: 10),
                              GestureDetector(
                                onTap: onCta,
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
                                      Text(
                                        notif.ctaLabel!,
                                        style: TextStyle(
                                          color: WebeyColors.primaryGold,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 13,
                                        color: WebeyColors.primaryGold,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onDiscoverTap});
  final VoidCallback? onDiscoverTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bell emblem
            Stack(
              alignment: Alignment.center,
              children: [
                // Outer dashed ring
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: WebeyColors.primaryGold.withAlpha(50),
                      width: 1,
                      // dashed effect via strokeAlign
                    ),
                  ),
                ),
                // Decorative dots
                Positioned(
                  left: 8,
                  top: 55,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: WebeyColors.primaryGold,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 62,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: WebeyColors.primaryGold.withAlpha(120),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 58,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8C6F38),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                // Inner circle
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: WebeyColors.warmCream,
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.notifications_none_rounded,
                      size: 36,
                      color: WebeyColors.primaryGold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'SESSİZ · SAKİN',
              style: TextStyle(
                color: WebeyColors.primaryGold,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            RichText(
              textAlign: TextAlign.center,
              text: const TextSpan(
                style: TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 24,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
                children: [
                  TextSpan(text: 'Henüz '),
                  TextSpan(
                    text: 'bildiriminiz',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: WebeyColors.primaryGold,
                    ),
                  ),
                  TextSpan(text: '\nyok.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Randevu, kapora ve salon güncellemeleriniz burada görünecek. Sizi yormadan, tam zamanında.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: onDiscoverTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 13,
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
                        fontSize: 11.5,
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
          ],
        ),
      ),
    );
  }
}
