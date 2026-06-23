// lib/features/business/presentation/business_start_flow.dart
//
// Claude Design → Flutter dönüşümü
// Webey İşletme — 4 Ekran
// Dashboard · Onay Modal · Haftalık Takvim · İşletme Profili

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/webey_colors.dart';
import '../../splash/splash_and_legal_screens.dart';
import '../../../shared/models/beauty_models.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/services/auth_service.dart';
import '../../../shared/widgets/account_deletion_sheet.dart';
import '../../../shared/widgets/webey_back_handler.dart';
import '../../../shared/widgets/webey_toast.dart';
import '../data/models/business_appointment.dart';
import '../data/models/business_dashboard.dart';
import '../data/models/business_service_item.dart';
import '../data/models/business_staff_item.dart';
import '../data/repositories/business_repository.dart';
import 'business_campaigns_screen.dart';
import 'business_gallery_screen.dart';
import 'business_location_picker.dart';
import 'business_location_settings_screen.dart';
import 'business_management_screens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

enum _ApptTone { gold, amber, gap }

class _TodayAppt {
  const _TodayAppt({
    required this.id,
    required this.time,
    required this.dur,
    required this.tone,
    this.client,
    this.service,
    this.staff,
    this.staffInitials = '',
    this.staffColorA = WebeyColors.primaryGold,
    this.staffColorB = const Color(0xFF8C6F38),
    this.status,
    this.gapLabel,
  });
  final String id, time, dur;
  final _ApptTone tone;
  final String? client, service, staff, status, gapLabel;
  final String staffInitials;
  final Color staffColorA, staffColorB;
}

// ignore: unused_element
const _kToday = [
  _TodayAppt(
    id: 'a1',
    time: '09:00',
    dur: '90 dk',
    tone: _ApptTone.gold,
    client: 'Selin K.',
    service: 'Protez Tırnak',
    staff: 'Ece Y.',
    staffInitials: 'EY',
    staffColorA: Color(0xFFD4B574),
    staffColorB: Color(0xFF8C6F38),
    status: 'Onaylandı',
  ),
  _TodayAppt(
    id: 'a2',
    time: '10:30',
    dur: '45 dk',
    tone: _ApptTone.gold,
    client: 'Ayşe D.',
    service: 'Kalıcı Oje',
    staff: 'Mina A.',
    staffInitials: 'MA',
    staffColorA: Color(0xFFB8964E),
    staffColorB: Color(0xFF5d4a2c),
    status: 'Onaylandı',
  ),
  _TodayAppt(
    id: 'g1',
    time: '12:00',
    dur: '90 dk',
    tone: _ApptTone.gap,
    gapLabel: 'Boşluk · Mola için ideal',
  ),
  _TodayAppt(
    id: 'a3',
    time: '13:30',
    dur: '35 dk',
    tone: _ApptTone.amber,
    client: 'Fatma Y.',
    service: 'Manikür',
    staff: 'Ece Y.',
    staffInitials: 'EY',
    staffColorA: Color(0xFFD4B574),
    staffColorB: Color(0xFF8C6F38),
    status: 'Onay Bekliyor',
  ),
  _TodayAppt(
    id: 'a4',
    time: '15:00',
    dur: '75 dk',
    tone: _ApptTone.gold,
    client: 'Zeynep T.',
    service: 'Nail Art',
    staff: 'Lara D.',
    staffInitials: 'LD',
    staffColorA: Color(0xFFC7A26A),
    staffColorB: Color(0xFF806440),
    status: 'Onaylandı',
  ),
  _TodayAppt(
    id: 'a5',
    time: '16:30',
    dur: '60 dk',
    tone: _ApptTone.gold,
    client: 'Mira S.',
    service: 'Pedikür',
    staff: 'Naz Ö.',
    staffInitials: 'NÖ',
    staffColorA: Color(0xFFA0824A),
    staffColorB: Color(0xFF503e23),
    status: 'Onaylandı',
  ),
  _TodayAppt(
    id: 'a6',
    time: '18:00',
    dur: '45 dk',
    tone: _ApptTone.gold,
    client: 'Ceren A.',
    service: 'Kalıcı Oje',
    staff: 'Ece Y.',
    staffInitials: 'EY',
    staffColorA: Color(0xFFD4B574),
    staffColorB: Color(0xFF8C6F38),
    status: 'Onaylandı',
  ),
];

String _friendlyBusinessError(Object error, String fallback) {
  if (error is ApiException) {
    if (error.message.trim().isNotEmpty) return error.message;
    if (error.statusCode == 403 || error.code == 'business_required') {
      return 'Bu hesaba bagli isletme bulunamadi.';
    }
    if (error.statusCode == 401) {
      return 'Oturum suresi doldu. Lutfen tekrar giris yapin.';
    }
  }
  return fallback;
}

String _formatBusinessDate(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _formatTime(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

DateTime _mondayOf(DateTime value) {
  final day = DateTime(value.year, value.month, value.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

String _monthYearLabel(DateTime value) {
  const months = [
    'Ocak',
    'Subat',
    'Mart',
    'Nisan',
    'Mayis',
    'Haziran',
    'Temmuz',
    'Agustos',
    'Eylul',
    'Ekim',
    'Kasim',
    'Aralik',
  ];
  return '${months[value.month - 1]} ${value.year}';
}

String _shortWeekday(DateTime value) {
  const days = ['Pzt', 'Sal', 'Car', 'Per', 'Cum', 'Cmt', 'Paz'];
  return days[value.weekday - 1];
}

String _fullWeekdayTr(DateTime value) {
  const days = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  return days[value.weekday - 1];
}

String _greetingTimePrefix(DateTime value) {
  final h = value.hour;
  if (h < 6) return 'İyi geceler';
  if (h < 12) return 'Günaydın';
  if (h < 18) return 'İyi günler';
  return 'İyi akşamlar';
}

String _initialsFromName(String? name) {
  final parts = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'W';
  return parts.take(2).map((p) => p.substring(0, 1)).join().toUpperCase();
}

String _businessStatusLabel(String status) {
  return switch (status) {
    'approved' => 'Onaylandi',
    'completed' => 'Tamamlandi',
    'cancelled' => 'Iptal edildi',
    'cancellation_requested' => 'Iptal talebi',
    'rejected' || 'declined' => 'Reddedildi',
    'no_show' => 'Gelmedi',
    _ => 'Onay bekliyor',
  };
}

String _appointmentStatusMessage(String status) {
  return switch (status) {
    'approved' => 'Randevu onaylandı.',
    'completed' => 'Randevu tamamlandı.',
    'cancelled' || 'rejected' => 'Randevu iptal edildi.',
    'no_show' => 'Randevu gelmedi olarak işaretlendi.',
    'cancel_rejected' => 'İptal talebi reddedildi.',
    _ => 'Randevu güncellendi.',
  };
}

String _depositStatusMessage(String status) {
  return switch (status) {
    'paid' => 'Kapora alındı olarak işaretlendi.',
    'not_received' => 'Kapora alınmadı olarak işaretlendi.',
    'pending' => 'Kapora bekleniyor durumuna alındı.',
    'refunded' => 'Kapora iade edildi olarak işaretlendi.',
    'waived' => 'Kapora muaf olarak işaretlendi.',
    _ => 'Kapora durumu güncellendi.',
  };
}

String _moneyLabel(double value) {
  if (value <= 0) return '—';
  if (value >= 1000) {
    final text = (value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1);
    return '₺${text}k';
  }
  return '₺${value.round()}';
}

String _initials(String? name) {
  final parts = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'W';
  return parts.take(2).map((part) => part.substring(0, 1)).join().toUpperCase();
}

_TodayAppt _todayApptFromBusiness(BusinessAppointment item) {
  final isPending =
      item.status == 'pending' ||
      item.status == 'cancellation_requested' ||
      item.status == 'rejected';
  return _TodayAppt(
    id: item.id,
    time: item.time.isNotEmpty ? item.time : '—',
    dur: '${item.durationMinutes ?? 60} dk',
    tone: isPending ? _ApptTone.amber : _ApptTone.gold,
    client: item.customerName.isNotEmpty ? item.customerName : 'Musteri',
    service: item.serviceName ?? 'Randevu',
    staff: item.staffName,
    staffInitials: _initials(item.staffName),
    status: _businessStatusLabel(item.status),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SHELL — Business navigation
// ─────────────────────────────────────────────────────────────────────────────

class BusinessShell extends StatefulWidget {
  const BusinessShell({super.key, this.onLogout});

  final VoidCallback? onLogout;

  @override
  State<BusinessShell> createState() => _BusinessShellState();
}

class _BusinessShellState extends State<BusinessShell> {
  int _tab = 0;
  WebeyBackRegistration? _backRegistration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _backRegistration ??= WebeyBackScope.register(context, _handleSystemBack);
  }

  @override
  void dispose() {
    _backRegistration?.dispose();
    super.dispose();
  }

  /// Sistem geri tuşu: Dashboard dışındaki tab'lardan önce Dashboard'a dön.
  bool _handleSystemBack() {
    if (_tab != 0) {
      setState(() => _tab = 0);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: IndexedStack(
        index: _tab,
        children: [
          BusinessDashboardScreen(
            onApptTap: (id) => _showApptModal(context, id),
            onNavigateToCalendar: () => setState(() => _tab = 1),
          ),
          const BusinessCalendarScreen(),
          BusinessProfileScreen(onLogout: widget.onLogout),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFAF6F0),
          border: Border(top: BorderSide(color: Color(0xFFE8DFD4))),
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
          selectedItemColor: const Color(0xFF1C1209),
          unselectedItemColor: const Color(0xFF9C8E82),
          selectedFontSize: 10,
          unselectedFontSize: 10,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Ana Sayfa',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_today_rounded),
              label: 'Takvim',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.store_outlined),
              activeIcon: Icon(Icons.store_rounded),
              label: 'Isletme',
            ),
          ],
        ),
      ),
    );
  }

  void _showApptModal(BuildContext context, String id) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ApptDetailModal(
        apptId: id,
        onConfirm: () => Navigator.pop(context),
        onCancel: () => Navigator.pop(context),
      ),
    );
  }
}

// ignore: unused_element
class _BizTabBar extends StatelessWidget {
  const _BizTabBar({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _tabs = [
    (icon: Icons.home_outlined, label: 'Ana Sayfa'),
    (icon: Icons.calendar_today_outlined, label: 'Takvim'),
    (icon: Icons.store_outlined, label: 'İşletme'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72 + MediaQuery.of(context).padding.bottom,
      decoration: BoxDecoration(
        color: WebeyColors.ivory,
        border: Border(top: BorderSide(color: WebeyColors.borderSand)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(_tabs.length, (i) {
            final isActive = currentIndex == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _tabs[i].icon,
                      size: 22,
                      color: isActive
                          ? WebeyColors.darkEspresso
                          : WebeyColors.mutedTaupe,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _tabs[i].label,
                      style: TextStyle(
                        color: isActive
                            ? WebeyColors.darkEspresso
                            : WebeyColors.mutedTaupe,
                        fontSize: 10,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(height: 4),
                      Container(
                        width: 18,
                        height: 3,
                        decoration: BoxDecoration(
                          color: WebeyColors.primaryGold,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 1 — Dashboard
// ─────────────────────────────────────────────────────────────────────────────

class BusinessDashboardScreen extends StatefulWidget {
  const BusinessDashboardScreen({
    super.key,
    this.onAddAppointment,
    this.onApptTap,
    this.onNavigateToCalendar,
    this.repository = BusinessRepository.instance,
  });
  final VoidCallback? onAddAppointment;
  final ValueChanged<String>? onApptTap;

  /// Aksiyon bekleyen randevu kartına basınca Takvim sekmesine geçmek için.
  final VoidCallback? onNavigateToCalendar;
  final BusinessRepository repository;

  @override
  State<BusinessDashboardScreen> createState() =>
      _BusinessDashboardScreenState();
}

class _BusinessDashboardScreenState extends State<BusinessDashboardScreen> {
  BusinessDashboard? _dashboard;
  var _loading = true;
  String? _busyAppointmentId;
  String? _error;
  AuthUser? _profile;
  int _unreadNotifCount = 0;
  bool _locationMissing = false;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _loadProfile();
    _loadUnreadNotifCount();
    _checkLocationMissing();
  }

  /// Salon konumu eksikse dashboard'da kalıcı uyarı gösterilir.
  Future<void> _checkLocationMissing() async {
    try {
      final profile = await widget.repository.getBusinessProfile();
      if (!mounted) return;
      double? coord(Object? v) {
        final parsed = v is num
            ? v.toDouble()
            : double.tryParse(v?.toString() ?? '');
        if (parsed == null || parsed.abs() < 0.0001) return null;
        return parsed;
      }

      setState(() {
        _locationMissing =
            coord(profile['latitude']) == null ||
            coord(profile['longitude']) == null;
      });
    } catch (_) {
      // Sessizce yut — uyarı gizli kalır, dashboard kırılmaz.
    }
  }

  Future<void> _loadUnreadNotifCount() async {
    try {
      final data = await widget.repository.getBusinessNotifications(
        limit: 1,
        unreadOnly: true,
      );
      if (!mounted) return;
      final count = (data['unread_count'] as num?)?.toInt() ?? 0;
      setState(() => _unreadNotifCount = count);
    } catch (_) {
      // Sessizce yut — badge gizli kalır, UI kırılmaz.
    }
  }

  Future<void> _showNotificationsSheet(BuildContext ctx) async {
    await Navigator.push<void>(
      ctx,
      MaterialPageRoute(builder: (_) => const BusinessNotificationsScreen()),
    );
    if (!mounted) return;
    await _loadUnreadNotifCount();
  }

  Future<void> _onAddAppointment() async {
    final created = await showAppointmentCreateSheet(
      context,
      repository: widget.repository,
    );
    if (created == null || !mounted) return;
    WebeyToast.success(context, 'Randevu oluşturuldu.');
    if (widget.onAddAppointment != null) widget.onAddAppointment!();
    await _loadDashboard();
  }

  Future<void> _openDashboardSearch(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WebeyColors.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const BusinessDashboardSearchSheet(),
    );
  }

  Future<void> _loadProfile() async {
    try {
      final result = await WebeyAuthService.instance.businessMe();
      if (!mounted) return;
      if (result.success && result.data != null) {
        setState(() => _profile = result.data);
      }
    } catch (_) {
      // greeting fall-back handled in UI
    }
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dashboard = await widget.repository.getDashboard();
      if (!mounted) return;
      setState(() => _dashboard = dashboard);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyBusinessError(
          error,
          'Dashboard yuklenemedi. Lutfen tekrar deneyin.',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (mounted) {
      unawaited(_loadUnreadNotifCount());
    }
  }

  Future<void> _updateAppointment(
    BusinessAppointment appointment,
    String status,
  ) async {
    if (_busyAppointmentId != null) return;
    setState(() => _busyAppointmentId = appointment.id);
    try {
      await widget.repository.updateAppointmentStatus(
        appointmentId: int.tryParse(appointment.id) ?? 0,
        status: status,
      );
      if (!mounted) return;
      await _loadDashboard();
      if (!mounted) return;
      WebeyToast.success(context, _appointmentStatusMessage(status));
    } catch (error) {
      if (!mounted) return;
      WebeyToast.error(
        context,
        _friendlyBusinessError(error, 'Randevu durumu guncellenemedi.'),
      );
    } finally {
      if (mounted) setState(() => _busyAppointmentId = null);
    }
  }

  Future<void> _updateDeposit(
    BusinessAppointment appointment,
    String status,
  ) async {
    if (_busyAppointmentId != null) return;
    setState(() => _busyAppointmentId = appointment.id);
    try {
      await widget.repository.markAppointmentDeposit(
        appointmentId: int.tryParse(appointment.id) ?? 0,
        status: status,
      );
      if (!mounted) return;
      await _loadDashboard();
      if (!mounted) return;
      WebeyToast.info(context, _depositStatusMessage(status));
    } catch (error) {
      if (!mounted) return;
      WebeyToast.error(
        context,
        _friendlyBusinessError(error, 'Kapora durumu güncellenemedi.'),
      );
    } finally {
      if (mounted) setState(() => _busyAppointmentId = null);
    }
  }

  Future<void> _confirmDeposit(
    BusinessAppointment appointment,
    String action,
  ) async {
    if (_busyAppointmentId != null) return;
    setState(() => _busyAppointmentId = appointment.id);
    try {
      final res = await widget.repository.confirmAppointmentDeposit(
        appointmentId: int.tryParse(appointment.id) ?? 0,
        action: action,
      );
      if (!mounted) return;
      await _loadDashboard();
      if (!mounted) return;
      final msg =
          res['message']?.toString() ??
          (action == 'confirm'
              ? 'Kapora onaylandı ve randevu onaylandı.'
              : 'Kapora alınmadı olarak işaretlendi.');
      WebeyToast.success(context, msg);
    } catch (error) {
      if (!mounted) return;
      WebeyToast.error(
        context,
        _friendlyBusinessError(error, 'Kapora durumu güncellenemedi.'),
      );
    } finally {
      if (mounted) setState(() => _busyAppointmentId = null);
    }
  }

  void _showAppointmentActions(BusinessAppointment appointment) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _BusinessAppointmentActionsSheet(
        appointment: appointment,
        onStatus: (status) {
          Navigator.pop(context);
          _updateAppointment(appointment, status);
        },
        onDeposit: (status) {
          Navigator.pop(context);
          _updateDeposit(appointment, status);
        },
        onConfirmDeposit: (action) {
          Navigator.pop(context);
          _confirmDeposit(appointment, action);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    final todayItems = dashboard?.todayItems ?? const <BusinessAppointment>[];
    final pendingItems =
        dashboard?.pendingItems ?? const <BusinessAppointment>[];
    final timelineItems = todayItems.map(_todayApptFromBusiness).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: WebeyColors.ivory,
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: _loadDashboard,
                color: WebeyColors.primaryGold,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    // TopBar
                    SliverToBoxAdapter(
                      child: _BizTopBar(
                        businessName: _profile?.fullName,
                        initials: _initialsFromName(_profile?.fullName),
                        onBell: () => _showNotificationsSheet(context),
                        showNotificationBadge: _unreadNotifCount > 0,
                      ),
                    ),
                    // Greeting
                    SliverToBoxAdapter(
                      child: _Greeting(
                        todayCount: dashboard?.summary.todayAppointments ?? 0,
                        pendingCount:
                            dashboard?.summary.pendingAppointments ?? 0,
                        userName: _profile?.fullName,
                      ),
                    ),
                    // Stats
                    SliverToBoxAdapter(
                      child: dashboard == null
                          ? const _DashboardLoadingBlock()
                          : _StatsRow(summary: dashboard.summary),
                    ),
                    // Abonelik uyarısı (yalnızca overdue/suspended/cancelled)
                    const SliverToBoxAdapter(
                      child: _DashboardSubscriptionBanner(),
                    ),
                    // Salon konumu eksik uyarısı (kalıcı)
                    if (_locationMissing)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          child: GestureDetector(
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const BusinessLocationSettingsScreen(),
                                ),
                              );
                              if (mounted) _checkLocationMissing();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: WebeyColors.warmCream,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: WebeyColors.primaryGold.withAlpha(140),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_off_outlined,
                                    size: 20,
                                    color: WebeyColors.primaryGold,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: const [
                                        Text(
                                          'Salon konumunuz eksik',
                                          style: TextStyle(
                                            color: WebeyColors.darkEspresso,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Haritada görünmek için konumunuzu '
                                          'ekleyin.',
                                          style: TextStyle(
                                            color: WebeyColors.mutedTaupe,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 20,
                                    color: WebeyColors.mutedTaupe,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Pending banner
                    if (pendingItems.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _PendingBanner(
                          items: pendingItems,
                          busyAppointmentId: _busyAppointmentId,
                          onCardTap: widget.onNavigateToCalendar,
                          onApprove: (item) {
                            final status =
                                item.status == 'cancellation_requested'
                                ? 'cancelled'
                                : 'approved';
                            _updateAppointment(item, status);
                          },
                          onReject: (item) {
                            final status =
                                item.status == 'cancellation_requested'
                                ? 'cancel_rejected'
                                : 'cancelled';
                            _updateAppointment(item, status);
                          },
                        ),
                      ),
                    if (_error != null)
                      SliverToBoxAdapter(
                        child: _BusinessInlineState(
                          message: _error!,
                          actionLabel: 'Tekrar dene',
                          onAction: _loadDashboard,
                        ),
                      ),
                    // Timeline header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'BUGÜNÜN TAKVİMİ',
                                    style: TextStyle(
                                      color: WebeyColors.primaryGold,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    todayItems.isEmpty
                                        ? 'Bugun randevu yok'
                                        : '${todayItems.length} randevu',
                                    style: TextStyle(
                                      color: WebeyColors.darkEspresso,
                                      fontSize: 16,
                                      fontFamily: 'Georgia',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const BusinessCalendarScreen(),
                                ),
                              ),
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
                    ),
                    // Timeline
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      sliver: timelineItems.isEmpty
                          ? SliverToBoxAdapter(
                              child: _loading
                                  ? const _BusinessInlineState(
                                      message: 'Yükleniyor...',
                                    )
                                  : const _TodayTimelineEmptyState(),
                            )
                          : SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, i) => _TimelineRow(
                                  appt: timelineItems[i],
                                  isLast: i == timelineItems.length - 1,
                                  onTap: () =>
                                      _showAppointmentActions(todayItems[i]),
                                ),
                                childCount: timelineItems.length,
                              ),
                            ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
              ),
            ),
            // FAB bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _FabBar(
                onAdd: _onAddAppointment,
                onSearch: () => _openDashboardSearch(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bugünün Takvimi — boş durum ──────────────────────────────────────────────

class _TodayTimelineEmptyState extends StatelessWidget {
  const _TodayTimelineEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: WebeyColors.warmCream,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_available_outlined,
              color: WebeyColors.primaryGold,
              size: 22,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Bugün için randevu yok',
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Yeni bir randevu eklemek için aşağıdaki "Randevu Ekle" butonunu kullanabilirsiniz.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Business TopBar ──────────────────────────────────────────────────────────

class _BizTopBar extends StatelessWidget {
  const _BizTopBar({
    this.businessName,
    this.initials,
    this.onBell,
    this.showNotificationBadge = false,
  });

  final String? businessName;
  final String? initials;
  final VoidCallback? onBell;
  final bool showNotificationBadge;

  @override
  Widget build(BuildContext context) {
    final displayInitials = (initials ?? '').isNotEmpty ? initials! : 'W';
    final subtitle = (businessName ?? '').isNotEmpty
        ? businessName!
        : 'İşletme Paneli';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          // Brand
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: WebeyColors.darkEspresso,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(
                'W',
                style: TextStyle(
                  color: WebeyColors.primaryGold,
                  fontSize: 16,
                  fontFamily: 'Georgia',
                  fontStyle: FontStyle.italic,
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
                  'Webey · İşletme',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 13,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Bell
          GestureDetector(
            onTap: onBell,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: WebeyColors.warmCream,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    size: 18,
                    color: WebeyColors.darkEspresso,
                  ),
                ),
                if (showNotificationBadge)
                  Positioned(
                    top: 7,
                    right: 8,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: WebeyColors.primaryGold,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: WebeyColors.warmCream,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFD4B574), Color(0xFF8C6F38)],
              ),
            ),
            child: Center(
              child: Text(
                displayInitials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Greeting ─────────────────────────────────────────────────────────────────

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.todayCount,
    required this.pendingCount,
    this.userName,
  });

  final int todayCount;
  final int pendingCount;
  final String? userName;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final prefix = _greetingTimePrefix(now);
    final trimmed = (userName ?? '').trim();
    final hasName = trimmed.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BUGÜN · ${_fullWeekdayTr(now).toUpperCase()}',
            style: TextStyle(
              color: WebeyColors.primaryGold,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          RichText(
            // Uzun işletme adlarında başlık kontrollü şekilde en fazla 3 satıra
            // sarsın, taşma yerine "…" göstersin.
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 22,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
              children: [
                TextSpan(text: hasName ? '$prefix, ' : 'Hoş geldiniz'),
                if (hasName)
                  TextSpan(
                    text: '$trimmed.',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 13,
                height: 1.4,
              ),
              children: [
                TextSpan(text: 'Bugün '),
                TextSpan(
                  text: '$todayCount randevu',
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: ' ve '),
                TextSpan(
                  text: '$pendingCount onay',
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const TextSpan(text: ' sizi bekliyor.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats Row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.summary});

  final BusinessDashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final revenue = _moneyLabel(summary.monthlyRevenueEstimate);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          // Dark featured card
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: WebeyColors.darkEspresso,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BUGÜN · BEKLENEN',
                    style: TextStyle(
                      color: Colors.white.withAlpha(120),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                      children: [TextSpan(text: revenue)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: Color(0xAAFFFFFF),
                        fontSize: 11,
                      ),
                      children: [
                        TextSpan(
                          text: '${summary.todayAppointments} randevu',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' · ${summary.pendingAppointments} onay bekliyor',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Light cards
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: WebeyColors.softWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BU HAFTA',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 20,
                            fontFamily: 'Georgia',
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                          children: [
                            TextSpan(text: '${summary.upcomingAppointments}'),
                            const TextSpan(
                              text: ' randevu',
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${summary.completedThisMonth} tamamlandı',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: WebeyColors.softWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'İPTAL / GELMEDİ',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${summary.cancelledThisMonth}',
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 20,
                          fontFamily: 'Georgia',
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'bu ay',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pending Banner ────────────────────────────────────────────────────────────

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({
    required this.items,
    required this.busyAppointmentId,
    required this.onApprove,
    required this.onReject,
    this.onCardTap,
  });

  final List<BusinessAppointment> items;
  final String? busyAppointmentId;
  final ValueChanged<BusinessAppointment> onApprove;
  final ValueChanged<BusinessAppointment> onReject;

  /// Kartın boş alanına basınca Takvim'e götürür (onay/red butonları hariç).
  final VoidCallback? onCardTap;

  @override
  Widget build(BuildContext context) {
    final first = items.first;
    final isUpdating = busyAppointmentId == first.id;
    final isCancelRequest = first.status == 'cancellation_requested';
    final names = items
        .take(2)
        .map((item) => '${item.customerName} · ${item.time}')
        .join(' ve ');
    final approveLabel = isCancelRequest ? 'İptali Onayla' : 'Onayla';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCardTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: WebeyColors.warning.withAlpha(15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: WebeyColors.warning.withAlpha(60)),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: WebeyColors.warning.withAlpha(25),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      isCancelRequest
                          ? Icons.cancel_schedule_send_rounded
                          : Icons.bolt_rounded,
                      size: 18,
                      color: WebeyColors.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        children: [
                          TextSpan(
                            text: isCancelRequest
                                ? 'İptal talebi'
                                : '${items.length} randevu',
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: isCancelRequest
                                ? ' var'
                                : ' aksiyon bekliyor',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      names,
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: isUpdating ? null : () => onReject(first),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: WebeyColors.errorRed.withAlpha(12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: WebeyColors.errorRed.withAlpha(45),
                    ),
                  ),
                  child: isUpdating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isCancelRequest
                              ? Icons.undo_rounded
                              : Icons.close_rounded,
                          size: 14,
                          color: WebeyColors.errorRed,
                        ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: isUpdating ? null : () => onApprove(first),
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
                      if (isUpdating)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: WebeyColors.primaryGold,
                          ),
                        )
                      else ...[
                        Text(
                          approveLabel,
                          style: TextStyle(
                            color: WebeyColors.primaryGold,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 12,
                          color: WebeyColors.primaryGold,
                        ),
                      ],
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

// Dashboard'da yalnızca overdue/suspended/cancelled durumunda görünen abonelik
// uyarısı. Kendi verisini çeker; hata/normal durumda hiçbir şey göstermez.
// Ödeme/satın alma CTA YOK — yalnızca "Webey Paketim" ekranına yönlendirir.
class _DashboardSubscriptionBanner extends StatefulWidget {
  const _DashboardSubscriptionBanner();

  @override
  State<_DashboardSubscriptionBanner> createState() =>
      _DashboardSubscriptionBannerState();
}

class _DashboardSubscriptionBannerState
    extends State<_DashboardSubscriptionBanner> {
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await BusinessRepository.instance.getSubscription();
      final sub = data['subscription'];
      final status = sub is Map ? sub['status']?.toString() : null;
      if (!mounted) return;
      setState(() => _status = status);
    } catch (_) {
      // Sessizce yok say — uyarı göstermeyiz.
    }
  }

  ({String text, Color color})? _alert(String? status) {
    switch (status) {
      case 'overdue':
        return (
          text:
              'Aboneliğinizin ödeme tarihi geçti. Görünürlüğünüz etkilenmeden '
              'önce Webey ekibiyle iletişime geçin.',
          color: WebeyColors.errorRed,
        );
      case 'suspended':
        return (
          text:
              'Aboneliğiniz askıya alındı. Müşteri uygulamasında görünürlüğünüz '
              'kısıtlanmış olabilir.',
          color: WebeyColors.errorRed,
        );
      case 'cancelled':
        return (
          text: 'Aboneliğiniz iptal edildi. Webey ekibiyle iletişime geçin.',
          color: WebeyColors.mutedTaupe,
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final alert = _alert(_status);
    if (alert == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BusinessSubscriptionScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: WebeyColors.alpha(alert.color, 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: WebeyColors.alpha(alert.color, 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 20, color: alert.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  alert.text,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: WebeyColors.mutedTaupe,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Timeline Row ──────────────────────────────────────────────────────────────

class _DashboardLoadingBlock extends StatelessWidget {
  const _DashboardLoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
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

class _BusinessInlineState extends StatelessWidget {
  const _BusinessInlineState({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12.5),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: TextStyle(
                  color: WebeyColors.primaryGold,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BusinessAppointmentActionsSheet extends StatelessWidget {
  const _BusinessAppointmentActionsSheet({
    required this.appointment,
    required this.onStatus,
    required this.onDeposit,
    required this.onConfirmDeposit,
  });

  final BusinessAppointment appointment;
  final ValueChanged<String> onStatus;
  final ValueChanged<String> onDeposit;
  final ValueChanged<String> onConfirmDeposit;

  Future<void> _confirmOutcome(
    BuildContext context, {
    required String status,
    required String title,
  }) async {
    final ok = await showWebeyConfirmDialog(
      context,
      icon: status == 'completed'
          ? Icons.task_alt_rounded
          : Icons.person_off_outlined,
      title: title,
      message: 'Bu işlem müşteri geçmişine yansıtılacaktır.',
      cancelLabel: 'Vazgeç',
      confirmLabel: status == 'completed' ? 'Geldi' : 'Gelmedi',
    );
    if (ok == true && context.mounted) {
      onStatus(status);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCancellationRequest =
        appointment.status == 'cancellation_requested';
    final isPending = appointment.status == 'pending';
    final isApproved = appointment.status == 'approved';
    final canMarkOutcome = appointment.canMarkCustomerOutcome;
    final actions = <Widget>[
      if (isCancellationRequest) ...[
        _StatusActionChip(
          label: 'İptali Reddet',
          icon: Icons.undo_rounded,
          onTap: () => onStatus('cancel_rejected'),
        ),
        _StatusActionChip(
          label: 'İptali Onayla',
          icon: Icons.check_rounded,
          danger: true,
          onTap: () => onStatus('cancelled'),
        ),
      ],
      if (isPending)
        _StatusActionChip(
          label: 'Onayla',
          icon: Icons.check_rounded,
          onTap: () => onStatus('approved'),
        ),
      if (isPending || isApproved)
        _StatusActionChip(
          label: 'İptal',
          icon: Icons.cancel_outlined,
          danger: true,
          onTap: () => onStatus('cancelled'),
        ),
      if (canMarkOutcome) ...[
        _StatusActionChip(
          label: 'Geldi',
          icon: Icons.task_alt_rounded,
          onTap: () => _confirmOutcome(
            context,
            status: 'completed',
            title: 'Bu randevuyu geldi olarak işaretlemek istiyor musunuz?',
          ),
        ),
        if (DateTime.now().millisecondsSinceEpoch < 0)
          _StatusActionChip(
            label: 'Tamamlandı',
            icon: Icons.task_alt_rounded,
            onTap: () => _confirmOutcome(
              context,
              status: 'completed',
              title: 'Bu randevuyu geldi olarak işaretlemek istiyor musunuz?',
            ),
          ),
        _StatusActionChip(
          label: 'Gelmedi',
          icon: Icons.person_off_outlined,
          danger: true,
          onTap: () => _confirmOutcome(
            context,
            status: 'no_show',
            title: 'Bu randevuyu gelmedi olarak işaretlemek istiyor musunuz?',
          ),
        ),
      ],
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: WebeyColors.ivory,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
          const SizedBox(height: 16),
          Text(
            appointment.customerName.isEmpty
                ? 'Randevu'
                : appointment.customerName,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 18,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${appointment.time} · ${appointment.serviceName ?? 'Randevu'}'
            '${appointment.staffName == null ? '' : ' · ${appointment.staffName}'}',
            style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12.5),
          ),
          if (appointment.depositRequired) ...[
            const SizedBox(height: 14),
            _BusinessDepositPanel(
              appointment: appointment,
              onDeposit: onDeposit,
              onConfirmDeposit: onConfirmDeposit,
            ),
          ],
          if (canMarkOutcome) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.help_outline_rounded,
                    size: 18,
                    color: WebeyColors.primaryGold,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Müşteri geldi mi?',
                      style: TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: actions.isEmpty
                ? [
                    Text(
                      'Bu randevu için uygun aksiyon yok.',
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 12.5,
                      ),
                    ),
                  ]
                : actions,
          ),
        ],
      ),
    );
  }
}

// Randevu detayinda kapora durumu + manuel isaretleme (MVP IBAN akisi).
class _BusinessDepositPanel extends StatelessWidget {
  const _BusinessDepositPanel({
    required this.appointment,
    required this.onDeposit,
    required this.onConfirmDeposit,
  });

  final BusinessAppointment appointment;
  final ValueChanged<String> onDeposit;

  /// Manuel IBAN onay/red: action 'confirm' | 'reject'.
  final ValueChanged<String> onConfirmDeposit;

  ({String label, Color color, Color bg}) _statusStyle(String? status) {
    switch (status) {
      case 'paid':
        return (
          label: 'Kapora alındı',
          color: WebeyColors.successGreen,
          bg: WebeyColors.successGreen.withAlpha(28),
        );
      case 'not_received':
        return (
          label: 'Kapora alınmadı',
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
          label: 'Müşteri gönderdiğini bildirdi',
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
    final status = appointment.depositStatus;
    final style = _statusStyle(status);
    final amount = appointment.depositAmount;
    // Gerçek kod backend'den gelir; eski randevular için legacy fallback.
    final refCode =
        appointment.depositReferenceCode ?? 'WEBEY-APT-${appointment.id}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 15,
                color: WebeyColors.primaryGold,
              ),
              const SizedBox(width: 7),
              Text(
                amount != null && amount > 0
                    ? 'Kapora · ${amount.toInt()} TL'
                    : 'Kapora',
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: style.bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  style.label,
                  style: TextStyle(
                    color: style.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Açıklama kodu: $refCode',
            style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 11.5),
          ),
          const SizedBox(height: 4),
          Text(
            'Kapora doğrudan salon hesabınıza gönderilir. Geldiğinde işaretleyin.',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          if (appointment.cancellation != null) ...[
            const SizedBox(height: 10),
            _BusinessCancellationResult(result: appointment.cancellation!),
          ],
          // Müşteri "IBAN'a yolladım" dediyse: öne çıkan onay/red aksiyonu.
          if (status == 'customer_marked_sent') ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: WebeyColors.primaryGold.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'IBAN ödeme bildirimi',
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Müşteri kaporayı IBAN\'a gönderdiğini bildirdi. '
                    'Lütfen banka hesabınızı kontrol edin.',
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => onConfirmDeposit('confirm'),
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: WebeyColors.successGreen,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text(
                          'Para geldi, randevuyu onayla',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onConfirmDeposit('reject'),
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: WebeyColors.errorRed.withAlpha(140),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Para gelmedi',
                          style: TextStyle(
                            color: WebeyColors.errorRed,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => onDeposit('paid'),
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: status == 'paid'
                            ? WebeyColors.successGreen
                            : WebeyColors.successGreen.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          'Kapora Alındı',
                          style: TextStyle(
                            color: status == 'paid'
                                ? Colors.white
                                : WebeyColors.successGreen,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onDeposit('not_received'),
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: status == 'not_received'
                            ? WebeyColors.errorRed
                            : WebeyColors.errorRed.withAlpha(24),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          'Kapora Alınmadı',
                          style: TextStyle(
                            color: status == 'not_received'
                                ? Colors.white
                                : WebeyColors.errorRed,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (status == 'paid' || status == 'not_received') ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => onDeposit('pending'),
                child: Text(
                  'Bekleniyor durumuna geri al',
                  style: TextStyle(
                    color: WebeyColors.primaryGold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _BusinessCancellationResult extends StatelessWidget {
  const _BusinessCancellationResult({required this.result});

  final CancellationFinancial result;

  String _money(double value) => '${value.toStringAsFixed(0)} TL';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'İptal / no-show sonucu',
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _BusinessMoneyRow(
            label: 'Ödenen kapora',
            value: _money(result.paidDeposit),
          ),
          _BusinessMoneyRow(
            label: 'Kesinti',
            value: _money(result.retainedAmount),
          ),
          _BusinessMoneyRow(
            label: 'İade hakkı',
            value: _money(result.refundAmount),
          ),
          _BusinessMoneyRow(
            label: 'İşletmede kalan',
            value: _money(result.retainedAmount),
          ),
          if (result.manualRefund) ...[
            const SizedBox(height: 5),
            Text(
              'İade işletme tarafından manuel yapılacaktır.',
              style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _BusinessMoneyRow extends StatelessWidget {
  const _BusinessMoneyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 11),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusActionChip extends StatelessWidget {
  const _StatusActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? WebeyColors.errorRed : WebeyColors.darkEspresso;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: danger
              ? WebeyColors.errorRed.withAlpha(10)
              : WebeyColors.goldLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: danger
                ? WebeyColors.errorRed.withAlpha(45)
                : WebeyColors.primaryGold.withAlpha(60),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.appt,
    required this.isLast,
    required this.onTap,
  });
  final _TodayAppt appt;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isGap = appt.tone == _ApptTone.gap;
    final isAmber = appt.tone == _ApptTone.amber;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Time column
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appt.time,
                  style: TextStyle(
                    color: isGap
                        ? WebeyColors.mutedTaupe.withAlpha(100)
                        : WebeyColors.darkEspresso,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Georgia',
                  ),
                ),
                Text(
                  appt.dur,
                  style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 10),
                ),
              ],
            ),
          ),
          // Rail
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isGap
                        ? WebeyColors.borderSand
                        : isAmber
                        ? WebeyColors.warning
                        : WebeyColors.primaryGold,
                    border: isGap
                        ? Border.all(
                            color: WebeyColors.borderSand,
                            width: 1.5,
                            strokeAlign: BorderSide.strokeAlignOutside,
                          )
                        : null,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: isGap
                          ? WebeyColors.borderSand.withAlpha(100)
                          : WebeyColors.borderSand,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Card
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
              child: isGap
                  ? _GapCard(label: appt.gapLabel!)
                  : _ApptCard(appt: appt, isAmber: isAmber, onTap: onTap),
            ),
          ),
        ],
      ),
    );
  }
}

class _GapCard extends StatelessWidget {
  const _GapCard({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: WebeyColors.borderSand,
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12),
            ),
          ),
          GestureDetector(
            onTap: () => WebeyToast.info(
              context,
              'Randevu eklemek için takvim sayfasını kullanın',
            ),
            child: Text(
              '+ Müşteri ekle',
              style: TextStyle(
                color: WebeyColors.primaryGold,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApptCard extends StatelessWidget {
  const _ApptCard({
    required this.appt,
    required this.isAmber,
    required this.onTap,
  });
  final _TodayAppt appt;
  final bool isAmber;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: isAmber
              ? WebeyColors.warning.withAlpha(10)
              : WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isAmber
                ? WebeyColors.warning.withAlpha(60)
                : WebeyColors.borderSand,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appt.client!,
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isAmber
                        ? WebeyColors.warning.withAlpha(20)
                        : WebeyColors.goldLight,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    appt.status!,
                    style: TextStyle(
                      color: isAmber
                          ? WebeyColors.warning
                          : WebeyColors.primaryGold,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    appt.service!,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                // Staff avatar
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [appt.staffColorA, appt.staffColorB],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      appt.staffInitials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: WebeyColors.warmCream,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: Text(
                    appt.dur,
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 10,
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

// ── FAB Bar ───────────────────────────────────────────────────────────────────

class _FabBar extends StatelessWidget {
  const _FabBar({required this.onAdd, this.onSearch});
  final VoidCallback onAdd;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: WebeyColors.ivory,
        border: Border(top: BorderSide(color: WebeyColors.borderSand)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onSearch,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: const Icon(
                Icons.search_rounded,
                size: 18,
                color: WebeyColors.darkEspresso,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onAdd,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: WebeyColors.primaryGold,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: WebeyColors.darkEspresso,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Randevu Ekle',
                      style: TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
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

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 2 — Appointment Detail Modal
// ─────────────────────────────────────────────────────────────────────────────

class ApptDetailModal extends StatelessWidget {
  const ApptDetailModal({
    super.key,
    required this.apptId,
    required this.onConfirm,
    required this.onCancel,
  });
  final String apptId;
  final VoidCallback onConfirm, onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: WebeyColors.ivory,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: WebeyColors.borderSand,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                children: [
                  // Header
                  Row(
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
                                  fontSize: 18,
                                  fontFamily: 'Georgia',
                                  fontWeight: FontWeight.w600,
                                ),
                                children: [
                                  TextSpan(text: 'Randevu '),
                                  TextSpan(
                                    text: 'Detayı',
                                    style: TextStyle(
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Müşteriye onay veya iptal bildirimi gönderilecek.',
                              style: TextStyle(
                                color: WebeyColors.mutedTaupe,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: WebeyColors.warmCream,
                            shape: BoxShape.circle,
                            border: Border.all(color: WebeyColors.borderSand),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: WebeyColors.mutedTaupe,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Appointment card
                  Container(
                    decoration: BoxDecoration(
                      color: WebeyColors.darkEspresso,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 13, 14, 0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: WebeyColors.warning.withAlpha(30),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: WebeyColors.warning.withAlpha(80),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: WebeyColors.warning,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Onay Bekliyor',
                                      style: TextStyle(
                                        color: WebeyColors.warning,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'RDV-2849',
                                style: TextStyle(
                                  color: Colors.white.withAlpha(80),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Client
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFFD4B574),
                                      Color(0xFF8C6F38),
                                    ],
                                  ),
                                ),
                                child: const Center(
                                  child: Text(
                                    'F',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Fatma Yılmaz',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        '4 randevu geçmişi',
                                        style: TextStyle(
                                          color: Colors.white.withAlpha(160),
                                          fontSize: 11.5,
                                        ),
                                      ),
                                      Text(
                                        ' · ',
                                        style: TextStyle(
                                          color: Colors.white.withAlpha(60),
                                        ),
                                      ),
                                      Icon(
                                        Icons.star_rounded,
                                        size: 11,
                                        color: WebeyColors.primaryGold,
                                      ),
                                      Text(
                                        ' 4.8',
                                        style: TextStyle(
                                          color: Colors.white.withAlpha(180),
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Detail rows
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                          child: Column(
                            children: [
                              Divider(
                                color: Colors.white.withAlpha(15),
                                height: 1,
                              ),
                              const SizedBox(height: 10),
                              _ModalDetailRow(
                                icon: Icons.spa_outlined,
                                label: 'Hizmet · Uzman',
                                value: 'Manikür',
                                italic: '· Ece Yıldız',
                              ),
                              const SizedBox(height: 8),
                              _ModalDetailRow(
                                icon: Icons.calendar_today_outlined,
                                label: 'Tarih ve Saat',
                                value: '20 May Sal · 13:30',
                                italic: '— 35 dk',
                              ),
                              const SizedBox(height: 8),
                              _ModalDetailRow(
                                icon: Icons.account_balance_wallet_outlined,
                                label: 'Ödeme',
                                value: 'Kapora yok',
                                italic: '· Salonda · 450 TL',
                              ),
                              const SizedBox(height: 10),
                              // Note
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(10),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.white.withAlpha(15),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Müşteri notu',
                                      style: TextStyle(
                                        color: Colors.white.withAlpha(100),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Hassas tırnak yapısı, nazik uygulama rica ederim.',
                                      style: TextStyle(
                                        color: Colors.white.withAlpha(180),
                                        fontSize: 12.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onCancel,
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: WebeyColors.errorRed.withAlpha(12),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: WebeyColors.errorRed.withAlpha(50),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.cancel_outlined,
                                  size: 15,
                                  color: WebeyColors.errorRed,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'İptal Et',
                                  style: TextStyle(
                                    color: WebeyColors.errorRed,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: onConfirm,
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: WebeyColors.primaryGold,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_rounded,
                                  size: 15,
                                  color: WebeyColors.darkEspresso,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Onayla',
                                  style: TextStyle(
                                    color: WebeyColors.darkEspresso,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 11,
                        color: WebeyColors.mutedTaupe,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Onayladıktan sonra müşteriye bildirim gönderilir.',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModalDetailRow extends StatelessWidget {
  const _ModalDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.italic,
  });
  final IconData icon;
  final String label, value;
  final String? italic;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: Colors.white.withAlpha(120)),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withAlpha(100),
                fontSize: 10,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 2),
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  TextSpan(text: value),
                  if (italic != null)
                    TextSpan(
                      text: ' $italic',
                      style: TextStyle(
                        color: Colors.white.withAlpha(140),
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 3 — Calendar
// ─────────────────────────────────────────────────────────────────────────────

class BusinessCalendarScreen extends StatefulWidget {
  const BusinessCalendarScreen({
    super.key,
    this.onAddAppointment,
    this.initialStatusFilter = 'all',
    this.repository = BusinessRepository.instance,
  });

  final VoidCallback? onAddAppointment;

  /// Açılışta uygulanacak durum filtresi (Aksiyon Merkezi yönlendirmesi için).
  final String initialStatusFilter;
  final BusinessRepository repository;

  @override
  State<BusinessCalendarScreen> createState() => _BusinessCalendarScreenState();
}

class _StaffChipData {
  const _StaffChipData({
    required this.id,
    required this.label,
    required this.initial,
  });

  final String id;
  final String label;
  final String initial;
}

class _BusinessCalendarScreenState extends State<BusinessCalendarScreen> {
  int _activeDay = DateTime.now().weekday - 1;
  int _weekOffsetDays = 0;
  String _activeStaff = 'all';
  late String _statusFilter = widget.initialStatusFilter;
  String _searchQuery = '';
  var _appointments = <BusinessAppointment>[];
  var _weekAppointments = <BusinessAppointment>[];
  var _staffItems = <_StaffChipData>[];
  var _loading = true;
  String? _busyAppointmentId;
  String? _error;

  List<DateTime> get _dynamicWeek => List.generate(
    7,
    (index) =>
        _mondayOf(DateTime.now()).add(Duration(days: index + _weekOffsetDays)),
  );

  void _prevWeek() {
    setState(() {
      _weekOffsetDays -= 7;
      _activeDay = 0;
    });
    _loadAppointments();
    _loadWeekAppointments();
  }

  void _nextWeek() {
    setState(() {
      _weekOffsetDays += 7;
      _activeDay = 0;
    });
    _loadAppointments();
    _loadWeekAppointments();
  }

  DateTime get _selectedDate =>
      _dynamicWeek[_activeDay.clamp(0, _dynamicWeek.length - 1)];

  String get _selectedDateParam => _formatBusinessDate(_selectedDate);

  List<_StaffChipData> get _staffChips => [
    const _StaffChipData(id: 'all', label: 'Tümü', initial: ''),
    ..._staffItems,
  ];

  @override
  void initState() {
    super.initState();
    _loadAppointments();
    _loadWeekAppointments();
    _loadStaff();
  }

  // Hafta seridindeki gun bazli nokta gostergeleri icin: gorunen haftanin
  // tum randevularini tek istekte ceker. Secili gun listesinden ayri tutulur
  // ki gun degistirmek noktalari bozmasin.
  Future<void> _loadWeekAppointments() async {
    final week = _dynamicWeek;
    try {
      final items = await widget.repository.getAppointments(
        status: 'all',
        from: _formatBusinessDate(week.first),
        to: _formatBusinessDate(week.last),
        limit: 50,
      );
      if (!mounted) return;
      setState(() => _weekAppointments = items);
    } catch (_) {
      // Sessizce gec; noktalar gizli kalir, takvim calismaya devam eder.
    }
  }

  // Gorunen haftadaki her gun icin (aktif personel/durum filtresine gore)
  // randevu sayisini yyyy-MM-dd anahtariyla dondurur.
  Map<String, int> _weekCountByDay(_StaffChipData activeChip) {
    final counts = <String, int>{};
    for (final item in _weekAppointments) {
      if (_activeStaff != 'all' &&
          _initials(item.staffName) != activeChip.initial) {
        continue;
      }
      if (_statusFilter != 'all' && item.status != _statusFilter) {
        continue;
      }
      final key = _formatBusinessDate(item.startsAt);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _loadStaff() async {
    try {
      final items = await widget.repository.getStaff();
      if (!mounted) return;
      setState(() {
        _staffItems = items
            .where((s) => s.isActive && s.name.trim().isNotEmpty)
            .map(
              (s) => _StaffChipData(
                id: (s.id ?? s.name).toString(),
                label: s.name,
                initial: _initials(s.name),
              ),
            )
            .toList();
      });
    } catch (_) {
      // Sessizce geç; takvim "Tümü" ile çalışmaya devam eder.
    }
  }

  Future<void> _loadAppointments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final today = _formatBusinessDate(DateTime.now());
      final items = await widget.repository.getAppointments(
        status: _selectedDateParam == today ? 'today' : 'all',
        date: _selectedDateParam,
        limit: 50,
      );
      if (!mounted) return;
      setState(() => _appointments = items);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyBusinessError(error, 'Randevular yuklenemedi.');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateAppointment(
    BusinessAppointment appointment,
    String status,
  ) async {
    if (_busyAppointmentId != null) return;
    setState(() => _busyAppointmentId = appointment.id);
    try {
      await widget.repository.updateAppointmentStatus(
        appointmentId: int.tryParse(appointment.id) ?? 0,
        status: status,
      );
      if (!mounted) return;
      await _loadAppointments();
      if (!mounted) return;
      await _loadWeekAppointments();
      if (!mounted) return;
      WebeyToast.success(context, _appointmentStatusMessage(status));
    } catch (error) {
      if (!mounted) return;
      WebeyToast.error(
        context,
        _friendlyBusinessError(error, 'Randevu durumu guncellenemedi.'),
      );
    } finally {
      if (mounted) setState(() => _busyAppointmentId = null);
    }
  }

  Future<void> _updateDeposit(
    BusinessAppointment appointment,
    String status,
  ) async {
    if (_busyAppointmentId != null) return;
    setState(() => _busyAppointmentId = appointment.id);
    try {
      await widget.repository.markAppointmentDeposit(
        appointmentId: int.tryParse(appointment.id) ?? 0,
        status: status,
      );
      if (!mounted) return;
      await _loadAppointments();
      if (!mounted) return;
      WebeyToast.info(context, _depositStatusMessage(status));
    } catch (error) {
      if (!mounted) return;
      WebeyToast.error(
        context,
        _friendlyBusinessError(error, 'Kapora durumu güncellenemedi.'),
      );
    } finally {
      if (mounted) setState(() => _busyAppointmentId = null);
    }
  }

  Future<void> _confirmDeposit(
    BusinessAppointment appointment,
    String action,
  ) async {
    if (_busyAppointmentId != null) return;
    setState(() => _busyAppointmentId = appointment.id);
    try {
      final res = await widget.repository.confirmAppointmentDeposit(
        appointmentId: int.tryParse(appointment.id) ?? 0,
        action: action,
      );
      if (!mounted) return;
      await _loadAppointments();
      if (!mounted) return;
      final msg =
          res['message']?.toString() ??
          (action == 'confirm'
              ? 'Kapora onaylandı ve randevu onaylandı.'
              : 'Kapora alınmadı olarak işaretlendi.');
      WebeyToast.success(context, msg);
    } catch (error) {
      if (!mounted) return;
      WebeyToast.error(
        context,
        _friendlyBusinessError(error, 'Kapora durumu güncellenemedi.'),
      );
    } finally {
      if (mounted) setState(() => _busyAppointmentId = null);
    }
  }

  void _showAppointmentActions(BusinessAppointment appointment) {
    if (_busyAppointmentId != null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _BusinessAppointmentActionsSheet(
        appointment: appointment,
        onStatus: (status) {
          Navigator.pop(context);
          _updateAppointment(appointment, status);
        },
        onDeposit: (status) {
          Navigator.pop(context);
          _updateDeposit(appointment, status);
        },
        onConfirmDeposit: (action) {
          Navigator.pop(context);
          _confirmDeposit(appointment, action);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final week = _dynamicWeek;
    final staffChips = _staffChips;
    final activeChip = staffChips.firstWhere(
      (chip) => chip.id == _activeStaff,
      orElse: () => staffChips.first,
    );
    final filteredAppointments = _appointments.where((item) {
      if (_activeStaff != 'all' &&
          _initials(item.staffName) != activeChip.initial) {
        return false;
      }
      if (_statusFilter != 'all' && item.status != _statusFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final hay = [
          item.customerName,
          item.serviceName ?? '',
          item.staffName ?? '',
        ].join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
    final countByDay = _weekCountByDay(activeChip);
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        Container(
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
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                _monthYearLabel(_selectedDate),
                                style: TextStyle(
                                  color: WebeyColors.primaryGold,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Text(
                                'Takvim',
                                style: TextStyle(
                                  color: WebeyColors.darkEspresso,
                                  fontSize: 18,
                                  fontFamily: 'Georgia',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: _openFilterSheet,
                          behavior: HitTestBehavior.opaque,
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
                  ),
                ),
                // Week nav
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Row(
                      children: [
                        Text(
                          '${week.first.day} — ${week.last.day} ${_monthYearLabel(week.last).split(' ').first}',
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            _NavBtn(
                              icon: Icons.chevron_left_rounded,
                              onTap: _prevWeek,
                            ),
                            const SizedBox(width: 6),
                            _NavBtn(
                              icon: Icons.chevron_right_rounded,
                              onTap: _nextWeek,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Week strip
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Row(
                      children: List.generate(week.length, (i) {
                        final d = week[i];
                        final isActive = _activeDay == i;
                        final dayCount =
                            countByDay[_formatBusinessDate(d)] ?? 0;
                        final dayDots = dayCount > 3 ? 3 : dayCount;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _activeDay = i);
                              _loadAppointments();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? WebeyColors.darkEspresso
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    _shortWeekday(d),
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.white.withAlpha(160)
                                          : WebeyColors.mutedTaupe,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${d.day}',
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.white
                                          : WebeyColors.darkEspresso,
                                      fontSize: 15,
                                      fontFamily: 'Georgia',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(
                                      dayDots,
                                      (dotIndex) => Container(
                                        width: 4,
                                        height: 4,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: dotIndex == 2
                                              ? WebeyColors.warning
                                              : (isActive
                                                    ? WebeyColors.primaryGold
                                                    : WebeyColors.primaryGold
                                                          .withAlpha(120)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                // Staff strip
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      height: 34,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: staffChips.length,
                        itemBuilder: (_, i) {
                          final s = staffChips[i];
                          final isActive = _activeStaff == s.id;
                          return GestureDetector(
                            onTap: () => setState(() => _activeStaff = s.id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(right: 8),
                              padding: EdgeInsets.symmetric(
                                horizontal: s.initial.isEmpty ? 14 : 8,
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
                                  if (s.initial.isNotEmpty) ...[
                                    Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: WebeyColors.primaryGold
                                            .withAlpha(80),
                                      ),
                                      child: Center(
                                        child: Text(
                                          s.initial,
                                          style: TextStyle(
                                            color: isActive
                                                ? Colors.white
                                                : WebeyColors.darkEspresso,
                                            fontSize: 8,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                  ],
                                  Text(
                                    s.label,
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
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                // Calendar grid
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: _loading
                      ? const SliverToBoxAdapter(
                          child: _DashboardLoadingBlock(),
                        )
                      : _error != null
                      ? SliverToBoxAdapter(
                          child: _BusinessInlineState(
                            message: _error!,
                            actionLabel: 'Tekrar dene',
                            onAction: _loadAppointments,
                          ),
                        )
                      : filteredAppointments.isEmpty
                      ? const SliverToBoxAdapter(
                          child: _BusinessInlineState(
                            message: 'Seçili gün için randevu bulunmuyor.',
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate((context, i) {
                            final item = filteredAppointments[i];
                            final isAmber =
                                item.status == 'pending' ||
                                item.status == 'cancellation_requested';
                            return _CalRow(
                              time: item.time,
                              name: item.customerName,
                              svc:
                                  '${item.serviceName ?? 'Randevu'} · ${_businessStatusLabel(item.status)}',
                              isAmber: isAmber,
                              isGap: false,
                              isNow:
                                  item.date ==
                                      _formatBusinessDate(DateTime.now()) &&
                                  item.time == _formatTime(DateTime.now()),
                              isTall: i == 0,
                              onTap: () => _showAppointmentActions(item),
                            );
                          }, childCount: filteredAppointments.length),
                        ),
                ),
                // Week stats
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: WebeyColors.softWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: Row(
                        children: [
                          _CalStat(
                            value: '${filteredAppointments.length}',
                            unit: '',
                            label: 'Secili gun',
                          ),
                          _CalDivider(),
                          _CalStat(
                            value:
                                '${_appointments.map((e) => e.staffName).where((e) => e != null && e.isNotEmpty).toSet().length}',
                            unit: ' uzm.',
                            label: 'Aktif personel',
                          ),
                          _CalDivider(),
                          _CalStat(
                            value:
                                '${_appointments.where((e) => e.isPendingAction).length}',
                            unit: '',
                            label: 'Bekleyen',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _FabBar(
              onAdd: _onAddAppointment,
              onSearch: _openSearchSheet,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onAddAppointment() async {
    final created = await showAppointmentCreateSheet(
      context,
      initialDate: _selectedDate,
      repository: widget.repository,
    );
    if (created == null || !mounted) return;
    WebeyToast.success(context, 'Randevu oluşturuldu.');
    if (widget.onAddAppointment != null) widget.onAddAppointment!();
    if (created.date.isNotEmpty && created.date != _selectedDateParam) {
      final mondayOfCreated = _mondayOf(DateTime.parse(created.date));
      final mondayOfNow = _mondayOf(DateTime.now());
      final offset = mondayOfCreated.difference(mondayOfNow).inDays;
      final idx = DateTime.parse(created.date).weekday - 1;
      setState(() {
        _weekOffsetDays = offset;
        _activeDay = idx;
      });
    }
    await _loadAppointments();
    if (!mounted) return;
    await _loadWeekAppointments();
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_CalendarFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CalendarFilterSheet(
        initialStatus: _statusFilter,
        initialStaff: _activeStaff,
        staffChips: _staffChips,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _statusFilter = result.status;
        _activeStaff = result.staffId;
      });
    }
  }

  Future<void> _openSearchSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CalendarSearchSheet(initial: _searchQuery),
    );
    if (result == null) return;
    if (!mounted) return;
    setState(() => _searchQuery = result.trim());
  }
}

class _CalRow extends StatelessWidget {
  const _CalRow({
    required this.time,
    required this.name,
    required this.svc,
    required this.isAmber,
    required this.isGap,
    required this.isNow,
    required this.isTall,
    this.onTap,
  });
  final String time, name, svc;
  final bool isAmber, isGap, isNow, isTall;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time
            SizedBox(
              width: 48,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  time,
                  style: TextStyle(
                    color: isNow
                        ? WebeyColors.primaryGold
                        : WebeyColors.mutedTaupe,
                    fontSize: 11,
                    fontWeight: isNow ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ),
            // Block
            Expanded(
              child: Stack(
                children: [
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.all(10),
                    height: isTall ? 88 : 58,
                    decoration: BoxDecoration(
                      color: isGap
                          ? Colors.transparent
                          : isAmber
                          ? WebeyColors.warning.withAlpha(12)
                          : WebeyColors.goldLight,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: isGap
                            ? WebeyColors.borderSand
                            : isAmber
                            ? WebeyColors.warning.withAlpha(60)
                            : WebeyColors.primaryGold.withAlpha(60),
                        style: isGap ? BorderStyle.solid : BorderStyle.solid,
                      ),
                    ),
                    child: isGap
                        ? Row(
                            children: [
                              const Icon(
                                Icons.add_rounded,
                                size: 12,
                                color: WebeyColors.mutedTaupe,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Boşluk',
                                style: TextStyle(
                                  color: WebeyColors.mutedTaupe,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: WebeyColors.darkEspresso,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                svc,
                                style: TextStyle(
                                  color: isAmber
                                      ? WebeyColors.warning
                                      : WebeyColors.mutedTaupe,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                  ),
                  if (isNow)
                    Positioned(
                      left: 4,
                      top: 0,
                      right: 0,
                      child: Container(
                        height: 2,
                        color: WebeyColors.primaryGold,
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

class _CalStat extends StatelessWidget {
  const _CalStat({
    required this.value,
    required this.unit,
    required this.label,
  });
  final String value, unit, label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 20,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
              ),
              children: [
                TextSpan(text: value),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: unit,
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _CalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 40, color: WebeyColors.borderSand);
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Icon(icon, size: 16, color: WebeyColors.darkEspresso),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 4 — Business Profile / Settings
// ─────────────────────────────────────────────────────────────────────────────

class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({super.key, this.onLogout});

  final VoidCallback? onLogout;

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final _repository = BusinessRepository.instance;
  Map<String, dynamic>? _profile;
  bool _profileLoading = true;
  String? _profileError;
  bool _autoConfirm = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _profileLoading = true;
      _profileError = null;
    });
    try {
      final profile = await _repository.getBusinessProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _profileLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _profileError = _friendlyBusinessError(
          error,
          'İşletme profili yüklenemedi.',
        );
        _profileLoading = false;
      });
    }
  }

  String get _profileLocation {
    final district = _profile?['district']?.toString() ?? '';
    final city = _profile?['city']?.toString() ?? '';
    if (district.isEmpty && city.isEmpty) return '';
    if (district.isEmpty) return city;
    if (city.isEmpty) return district;
    return '$district · $city';
  }

  Future<void> _openProfileEditor() async {
    final profile = _profile;
    if (profile == null) return;
    final nameCtrl = TextEditingController(
      text: profile['name']?.toString() ?? '',
    );
    final descCtrl = TextEditingController(
      text:
          profile['about']?.toString() ??
          profile['description']?.toString() ??
          '',
    );
    final phoneCtrl = TextEditingController(
      text: profile['phone']?.toString() ?? '',
    );
    final cityCtrl = TextEditingController(
      text: profile['city']?.toString() ?? '',
    );
    final districtCtrl = TextEditingController(
      text: profile['district']?.toString() ?? '',
    );
    final addressCtrl = TextEditingController(
      text:
          profile['address_line']?.toString() ??
          profile['address']?.toString() ??
          '',
    );

    double? parseCoord(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '');
    }

    // Haritada seçilen konum; mevcut kayıtlı koordinatla başlar.
    var pickedLat = parseCoord(profile['latitude']);
    var pickedLng = parseCoord(profile['longitude']);

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var isSaving = false;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> save() async {
              if (isSaving) return;
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                WebeyToast.error(sheetContext, 'İşletme adı boş olamaz.');
                return;
              }
              setSheetState(() => isSaving = true);
              try {
                final updated = await _repository.saveBusinessProfile({
                  ...profile,
                  'name': name,
                  'about': descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim().isEmpty
                      ? null
                      : phoneCtrl.text.trim(),
                  'city': cityCtrl.text.trim().isEmpty
                      ? null
                      : cityCtrl.text.trim(),
                  'district': districtCtrl.text.trim().isEmpty
                      ? null
                      : districtCtrl.text.trim(),
                  'address_line': addressCtrl.text.trim().isEmpty
                      ? null
                      : addressCtrl.text.trim(),
                  'latitude': pickedLat,
                  'longitude': pickedLng,
                });
                if (!mounted) return;
                setState(() => _profile = updated);
                if (sheetContext.mounted) Navigator.pop(sheetContext, true);
              } catch (error) {
                if (!sheetContext.mounted) return;
                WebeyToast.error(
                  sheetContext,
                  _friendlyBusinessError(
                    error,
                    'İşletme profili kaydedilemedi.',
                  ),
                );
                setSheetState(() => isSaving = false);
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                ),
                child: Material(
                  color: WebeyColors.softWhite,
                  borderRadius: BorderRadius.circular(28),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(sheetContext).size.height * 0.88,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'İşletme Bilgileri',
                              style: TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 18,
                                fontFamily: 'Georgia',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _ProfileTextField(
                              controller: nameCtrl,
                              label: 'İşletme Adı',
                            ),
                            const SizedBox(height: 10),
                            _ProfileTextField(
                              controller: descCtrl,
                              label: 'Açıklama',
                              maxLines: 3,
                            ),
                            const SizedBox(height: 10),
                            _ProfileTextField(
                              controller: phoneCtrl,
                              label: 'Telefon',
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _ProfileTextField(
                                    controller: cityCtrl,
                                    label: 'Şehir',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _ProfileTextField(
                                    controller: districtCtrl,
                                    label: 'İlçe',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _ProfileTextField(
                              controller: addressCtrl,
                              label: 'Adres',
                              maxLines: 2,
                            ),
                            const SizedBox(height: 10),
                            // ── Haritada konum seç ────────────────────────
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: WebeyColors.warmCream,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: WebeyColors.borderSand,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    pickedLat != null && pickedLng != null
                                        ? Icons.where_to_vote_rounded
                                        : Icons.location_on_outlined,
                                    size: 20,
                                    color:
                                        pickedLat != null && pickedLng != null
                                        ? WebeyColors.successGreen
                                        : WebeyColors.primaryGold,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      pickedLat != null && pickedLng != null
                                          ? 'Salon konumu haritada işaretli.'
                                          : 'Salonunuz müşteri haritasında '
                                                'görünsün.',
                                      style: const TextStyle(
                                        color: WebeyColors.darkEspresso,
                                        fontSize: 12,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: isSaving
                                        ? null
                                        : () async {
                                            final picked =
                                                await Navigator.of(
                                                  sheetContext,
                                                ).push<
                                                  BusinessLocationPickResult
                                                >(
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        BusinessLocationPickerScreen(
                                                          initialLatitude:
                                                              pickedLat,
                                                          initialLongitude:
                                                              pickedLng,
                                                        ),
                                                  ),
                                                );
                                            if (picked != null) {
                                              setSheetState(() {
                                                pickedLat = picked.latitude;
                                                pickedLng = picked.longitude;
                                              });
                                            }
                                          },
                                    child: Text(
                                      pickedLat != null && pickedLng != null
                                          ? 'Düzenle'
                                          : 'Haritada seç',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Spacer(),
                                TextButton(
                                  onPressed: isSaving
                                      ? null
                                      : () => Navigator.pop(sheetContext),
                                  child: const Text('Vazgeç'),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(96, 44),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                  ),
                                  onPressed: isSaving ? null : save,
                                  child: isSaving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: WebeyColors.darkEspresso,
                                          ),
                                        )
                                      : const Text('Kaydet'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == true && mounted) {
      WebeyToast.success(context, 'İşletme bilgileri güncellendi.');
    }
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  List<_BizMenuItem> _salonMenu(BuildContext context) => [
    _BizMenuItem(
      name: 'Hizmetler ve Fiyatlar',
      sub: 'Hizmet kataloğu ve süreler',
      icon: Icons.content_cut_rounded,
      onTap: () => _push(context, const BusinessServicesScreen()),
    ),
    _BizMenuItem(
      name: 'Kampanyalar',
      sub: 'İndirim ve fırsatlarını yönet',
      icon: Icons.local_offer_outlined,
      onTap: () => _push(context, const BusinessCampaignsScreen()),
    ),
    _BizMenuItem(
      name: 'Personel Yönetimi',
      sub: 'Uzman profilleri ve müsaitlik',
      icon: Icons.people_outline_rounded,
      onTap: () => _push(context, const BusinessStaffScreen()),
    ),
    _BizMenuItem(
      name: 'Çalışma Saatleri',
      sub: 'Haftalık plan ve istisnalar',
      icon: Icons.schedule_rounded,
      onTap: () => _push(context, const BusinessHoursScreen()),
    ),
    _BizMenuItem(
      name: 'Salon Konumu',
      sub: 'Haritada görünüm ve yol tarifi',
      icon: Icons.place_outlined,
      onTap: () => _push(context, const BusinessLocationSettingsScreen()),
    ),
    _BizMenuItem(
      name: 'Fotoğraf Galerisi',
      sub: 'Salon ve çalışma fotoğrafları',
      icon: Icons.photo_library_outlined,
      onTap: () => _push(context, const BusinessGalleryScreen()),
    ),
    _BizMenuItem(
      name: 'Müşteriler',
      sub: 'Müşteri geçmişi ve tekrar ziyaretler',
      icon: Icons.person_search_outlined,
      onTap: () => _push(context, const BusinessCustomersScreen()),
    ),
    _BizMenuItem(
      name: 'Yorumlar',
      sub: 'Müşteri puanları ve son değerlendirmeler',
      icon: Icons.rate_review_outlined,
      onTap: () => _push(context, const BusinessReviewsScreen()),
    ),
  ];

  List<_BizMenuItem> _apptMenu(BuildContext context) => [
    _BizMenuItem(
      name: 'Kapora Politikası',
      sub: 'Garantili kapora oranı',
      icon: Icons.account_balance_wallet_outlined,
      onTap: () => _push(context, const BusinessDepositPolicyScreen()),
    ),
    _BizMenuItem(
      name: 'Kapora Ödeme Bilgileri',
      sub: 'IBAN ve hesap sahibi (kapora doğrudan salona)',
      icon: Icons.account_balance_outlined,
      onTap: () => _push(context, const BusinessPaymentSettingsScreen()),
    ),
    _BizMenuItem(
      name: 'İptal Politikası',
      sub: 'Ücretsiz iptal süresi ve no-show kuralı',
      icon: Icons.cancel_outlined,
      onTap: () => _push(context, const BusinessCancellationPolicyScreen()),
    ),
    _BizMenuItem(
      name: 'Bildirim Tercihleri',
      sub: 'Müşteri ve uzman bildirimleri',
      icon: Icons.notifications_outlined,
      onTap: () =>
          _push(context, const BusinessNotificationPreferencesScreen()),
    ),
  ];

  List<_BizMenuItem> _financeMenu(BuildContext context) => [
    _BizMenuItem(
      name: 'Webey Paketim',
      sub: 'Abonelik ve görünürlük durumu',
      icon: Icons.workspace_premium_outlined,
      onTap: () => _push(context, const BusinessSubscriptionScreen()),
    ),
    _BizMenuItem(
      name: 'Gelir Raporu',
      sub: 'Aylık ve yıllık özet',
      icon: Icons.bar_chart_rounded,
      value: 'Mayıs',
      onTap: () => _push(context, const BusinessRevenueScreen()),
    ),
    _BizMenuItem(
      name: 'Kapora Geçmişi',
      sub: 'Tahsil edilen ve iade edilen',
      icon: Icons.account_balance_wallet_outlined,
      onTap: () => _push(context, const BusinessRevenueDepositScreen()),
    ),
    _BizMenuItem(
      name: 'Fatura ve Ödemeler',
      sub: 'Webey komisyon ve faturaları',
      icon: Icons.receipt_outlined,
      onTap: () => _push(context, const BusinessInvoicesScreen()),
    ),
  ];

  List<_BizMenuItem> _performanceMenu(BuildContext context) => [
    _BizMenuItem(
      name: 'Analitik',
      sub: 'Gelir, doluluk ve hizmet performansı',
      icon: Icons.insights_outlined,
      onTap: () => _push(context, const BusinessAnalyticsScreen()),
    ),
    _BizMenuItem(
      name: 'Aksiyon Merkezi',
      sub: 'Bugün odaklanılacak işler',
      icon: Icons.task_alt_outlined,
      onTap: () => _push(
        context,
        BusinessActionCenterScreen(
          onOpenCalendar: (filter) {
            // Aksiyon filtresi → takvim durum filtresi eşlemesi.
            final status = switch (filter) {
              'pending' => 'pending',
              'outcome' => 'approved',
              _ => 'all',
            };
            _push(context, BusinessCalendarScreen(initialStatusFilter: status));
          },
        ),
      ),
    ),
    _BizMenuItem(
      name: 'Yayına Hazırlık',
      sub: 'Profil tamamlanma checklisti',
      icon: Icons.verified_outlined,
      onTap: () => _push(
        context,
        LaunchReadinessScreen(onEditBusinessInfo: _openProfileEditor),
      ),
    ),
  ];

  List<_BizMenuItem> _growthMenu(BuildContext context) => [
    _BizMenuItem(
      name: 'Boost Paketleri',
      sub: 'Salonunu aramada öne çıkar',
      icon: Icons.campaign_outlined,
      onTap: () => _push(context, const BusinessPromotionBoostScreen()),
    ),
  ];

  List<_BizMenuItem> _supportMenu(BuildContext context) => [
    _BizMenuItem(
      name: 'Webey Destek',
      sub: 'Sohbet, SSS ve telefon',
      icon: Icons.help_outline_rounded,
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _BusinessSupportSheet(),
      ),
    ),
    _BizMenuItem(
      name: 'Sözleşme ve Politikalar',
      sub: 'Hizmet sözleşmesi ve KVKK',
      icon: Icons.description_outlined,
      onTap: () => _push(context, const LegalDocumentsScreen()),
    ),
    _BizMenuItem(
      name: 'Hesabımı Sil',
      sub: 'Hesap silme talebi oluştur',
      icon: Icons.delete_outline_rounded,
      onTap: () => WebeyAccountDeletionSheet.show(context),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    Container(
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
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Webey · İşletme',
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 16,
                                fontFamily: 'Georgia',
                                fontWeight: FontWeight.w500,
                              ),
                              children: [
                                TextSpan(text: 'İşletme '),
                                TextSpan(
                                  text: 'Profili',
                                  style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: WebeyColors.primaryGold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: WebeyColors.warmCream,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: const Icon(
                        Icons.notifications_none_rounded,
                        size: 18,
                        color: WebeyColors.darkEspresso,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Business card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: WebeyColors.softWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: WebeyColors.darkEspresso,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                'W',
                                style: TextStyle(
                                  color: WebeyColors.primaryGold,
                                  fontSize: 22,
                                  fontFamily: 'Georgia',
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_profileLoading)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: WebeyColors.primaryGold,
                                    ),
                                  )
                                else if (_profileError != null)
                                  Text(
                                    'Profil yüklenemedi',
                                    style: TextStyle(
                                      color: WebeyColors.mutedTaupe,
                                      fontSize: 11,
                                    ),
                                  )
                                else ...[
                                  Text(
                                    (_profile?['name']?.toString() ?? 'İşletme')
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      color: WebeyColors.primaryGold,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _profile?['name']?.toString() ?? 'İşletme',
                                    style: const TextStyle(
                                      color: WebeyColors.darkEspresso,
                                      fontSize: 15,
                                      fontFamily: 'Georgia',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (_profileLocation.isNotEmpty)
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.location_on_outlined,
                                          size: 10,
                                          color: WebeyColors.mutedTaupe,
                                        ),
                                        const SizedBox(width: 3),
                                        Flexible(
                                          child: Text(
                                            _profileLocation,
                                            style: const TextStyle(
                                              color: WebeyColors.mutedTaupe,
                                              fontSize: 11.5,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: _profileLoading ? null : _openProfileEditor,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: WebeyColors.warmCream,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: WebeyColors.borderSand,
                                ),
                              ),
                              child: const Icon(
                                Icons.edit_outlined,
                                size: 13,
                                color: WebeyColors.darkEspresso,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Menus
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BizMenuSection(
                      title: 'SALON YÖNETİMİ',
                      items: _salonMenu(context),
                    ),
                    const SizedBox(height: 16),
                    _BizMenuSection(
                      title: 'RANDEVU AYARLARI',
                      items: _apptMenu(context),
                      toggle: _BizToggleItem(
                        name: 'Otomatik Onay',
                        sub: 'Yakında — değişiklikler henüz kaydedilmiyor',
                        icon: Icons.bolt_rounded,
                        value: _autoConfirm,
                        onChanged: (v) => setState(() => _autoConfirm = v),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _BizMenuSection(
                      title: 'FİNANSAL',
                      items: _financeMenu(context),
                    ),
                    const SizedBox(height: 16),
                    _BizMenuSection(
                      title: 'PERFORMANS',
                      items: _performanceMenu(context),
                    ),
                    const SizedBox(height: 16),
                    _BizMenuSection(
                      title: 'BÜYÜME',
                      items: _growthMenu(context),
                    ),
                    const SizedBox(height: 16),
                    _BizMenuSection(
                      title: 'DESTEK',
                      items: _supportMenu(context),
                    ),
                    const SizedBox(height: 16),
                    // Sign out
                    GestureDetector(
                      onTap: widget.onLogout,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: WebeyColors.errorRed.withAlpha(10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: WebeyColors.errorRed.withAlpha(40),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.logout_rounded,
                              size: 15,
                              color: WebeyColors.errorRed,
                            ),
                            const SizedBox(width: 7),
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
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'Webey İşletme\nSürüm ${AppInfo.version} · İstanbul',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 100),
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

class _BizMenuItem {
  const _BizMenuItem({
    required this.name,
    required this.sub,
    required this.icon,
    this.value,
    this.onTap,
  });
  final String name, sub;
  final IconData icon;
  final String? value;
  final VoidCallback? onTap;
}

// Webey Destek bottom sheet — iletişim seçenekleri + SSS.
class _BusinessSupportSheet extends StatelessWidget {
  const _BusinessSupportSheet();

  static const _supportEmail = 'destek@webey.com.tr';
  static const _supportPhone = '+908502550000';
  static const _whatsappUrl = 'https://wa.me/908502550000';

  static const _faq = [
    (
      'Randevu nasıl onaylanır?',
      'Randevular sekmesinden bekleyen randevuya dokunup "Onayla" deyin.',
    ),
    (
      'Kapora IBAN nasıl çalışır?',
      'Kapora Ödeme Bilgileri\'ne IBAN girin. Müşteri kaporayı IBAN\'a gönderdiğini bildirir, siz "Evet, para geldi" ile onaylarsınız.',
    ),
    (
      'Fotoğraf nasıl eklenir?',
      'Galeri ekranında "Fotoğraf ekle" ile seçim yapıp Kaydet\'e basın.',
    ),
    (
      'Yorumlara nasıl cevap verilir?',
      'Yorumlar ekranında ilgili yorumda "Cevapla" butonunu kullanın.',
    ),
    (
      'Müşteri bilgileri nerede?',
      'Müşteriler ekranında gerçek müşteri listesi ve detayları yer alır.',
    ),
  ];

  Future<void> _launch(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
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
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: WebeyColors.ivory,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: WebeyColors.borderSand,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                20 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                const Text(
                  'Webey Destek',
                  style: TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 20,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sorularınız için bize ulaşın veya sık sorulanlara göz atın.',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                _SupportContactTile(
                  icon: Icons.chat_rounded,
                  label: 'WhatsApp ile yaz',
                  onTap: () => _launch(context, _whatsappUrl),
                ),
                _SupportContactTile(
                  icon: Icons.mail_outline_rounded,
                  label: _supportEmail,
                  onTap: () => _launch(context, 'mailto:$_supportEmail'),
                ),
                _SupportContactTile(
                  icon: Icons.call_rounded,
                  label: 'Telefonla ara',
                  onTap: () => _launch(context, 'tel:$_supportPhone'),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Sık Sorulan Sorular',
                  style: TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ..._faq.map(
                  (item) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: WebeyColors.softWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: WebeyColors.borderSand),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$1,
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.$2,
                          style: TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportContactTile extends StatelessWidget {
  const _SupportContactTile({
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
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: WebeyColors.primaryGold),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
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
    );
  }
}

class _BizToggleItem {
  const _BizToggleItem({
    required this.name,
    required this.sub,
    required this.icon,
    required this.value,
    required this.onChanged,
  });
  final String name, sub;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
}

class _BizMenuSection extends StatelessWidget {
  const _BizMenuSection({
    required this.title,
    required this.items,
    this.toggle,
  });
  final String title;
  final List<_BizMenuItem> items;
  final _BizToggleItem? toggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: WebeyColors.mutedTaupe,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: WebeyColors.softWhite,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: WebeyColors.borderSand),
          ),
          child: Column(
            children: [
              ...List.generate(items.length, (i) {
                final item = items[i];
                final isLast = i == items.length - 1 && toggle == null;
                return Column(
                  children: [
                    _BizMenuRow(item: item),
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
              if (toggle != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Divider(height: 1, color: WebeyColors.borderSand),
                ),
                _BizToggleRow(item: toggle!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BizMenuRow extends StatelessWidget {
  const _BizMenuRow({required this.item});
  final _BizMenuItem item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.onTap ?? () {},
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
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
            if (item.value != null) ...[
              Text(
                item.value!,
                style: const TextStyle(
                  color: WebeyColors.mutedTaupe,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 4),
            ],
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

class _BizToggleRow extends StatelessWidget {
  const _BizToggleRow({required this.item});
  final _BizToggleItem item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => item.onChanged(!item.value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
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
            // Toggle switch
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 26,
              decoration: BoxDecoration(
                color: item.value
                    ? WebeyColors.primaryGold
                    : WebeyColors.borderSand,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: item.value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  const _ProfileTextField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: WebeyColors.darkEspresso, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: WebeyColors.mutedTaupe,
          fontSize: 12,
        ),
        filled: true,
        fillColor: WebeyColors.warmCream,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: WebeyColors.borderSand),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: WebeyColors.primaryGold),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared bottom sheets — notifications + appointment create
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showBusinessNotificationsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _NotificationsSheet(),
  );
}

class _NotificationsSheet extends StatefulWidget {
  const _NotificationsSheet();

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  final _repository = BusinessRepository.instance;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await _repository.getBusinessNotifications(limit: 30);
      if (!mounted) return;
      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      setState(() {
        _items = items;
        _unread = (data['unread_count'] as num?)?.toInt() ?? 0;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyBusinessError(error, 'Bildirimler alınamadı.');
        _isLoading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    try {
      final remaining = await _repository.markBusinessNotificationRead(
        markAll: true,
      );
      if (!mounted) return;
      setState(() {
        _unread = remaining;
        _items = _items.map((m) => {...m, 'read': true}).toList();
      });
    } catch (_) {}
  }

  String _formatRelative(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'az önce';
    if (diff.inHours < 1) return '${diff.inMinutes} dk önce';
    if (diff.inDays < 1) return '${diff.inHours} saat önce';
    if (diff.inDays < 7) return '${diff.inDays} gün önce';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: WebeyColors.ivory,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
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
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                'Bildirimler',
                style: TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 20,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (_unread > 0)
                TextButton(
                  onPressed: _markAllRead,
                  child: const Text('Tümünü okundu işaretle'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 13,
                ),
              ),
            )
          else if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    color: WebeyColors.mutedTaupe,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Henüz bildirim yok.',
                      style: TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final item in _items)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: item['read'] == true
                              ? WebeyColors.softWhite
                              : WebeyColors.goldLight,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: item['read'] == true
                                ? WebeyColors.borderSand
                                : WebeyColors.primaryGold.withAlpha(60),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item['title']?.toString() ?? 'Bildirim',
                                    style: const TextStyle(
                                      color: WebeyColors.darkEspresso,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatRelative(
                                    item['created_at']?.toString() ?? '',
                                  ),
                                  style: const TextStyle(
                                    color: WebeyColors.mutedTaupe,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item['body']?.toString() ?? '',
                              style: const TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

Future<BusinessServiceItem?> _showAppointmentServicePicker(
  BuildContext context, {
  required List<BusinessServiceItem> services,
  required int? selectedId,
}) {
  return showModalBottomSheet<BusinessServiceItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AppointmentSelectionSheet<BusinessServiceItem>(
      title: 'Hizmet seç',
      description: 'Randevunun süresini ve fiyatını belirleyen hizmeti seç.',
      emptyTitle: 'Aktif hizmet yok',
      emptyMessage: 'Randevu oluşturmak için önce aktif bir hizmet ekleyin.',
      items: services,
      selectedId: selectedId,
      idOf: (item) => item.id,
      cardBuilder: (context, item, selected) => _AppointmentOptionCard(
        selected: selected,
        icon: Icons.spa_outlined,
        title: item.name,
        subtitle:
            '${item.durationMinutes} dk · ${item.price.toStringAsFixed(0)} TL',
        badge: item.category,
      ),
    ),
  );
}

Future<BusinessStaffItem?> _showAppointmentStaffPicker(
  BuildContext context, {
  required List<BusinessStaffItem> staff,
  required int? selectedId,
}) {
  return showModalBottomSheet<BusinessStaffItem?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AppointmentSelectionSheet<BusinessStaffItem?>(
      title: 'Personel seç',
      description:
          'Personel seçimi opsiyoneldir; boş bırakırsan salon atama yapabilir.',
      emptyTitle: 'Aktif personel bulunmuyor',
      emptyMessage: 'Randevuyu personel seçmeden oluşturabilirsin.',
      items: [null, ...staff],
      selectedId: selectedId,
      idOf: (item) => item?.id,
      cardBuilder: (context, item, selected) => item == null
          ? _AppointmentOptionCard(
              selected: selectedId == null,
              icon: Icons.auto_awesome_outlined,
              title: 'Personel seçilmedi',
              subtitle: 'Randevu personel atanmadan oluşturulur',
            )
          : _AppointmentOptionCard(
              selected: selected,
              icon: Icons.person_outline_rounded,
              title: item.name,
              subtitle: item.role ?? 'Personel',
              badge: item.serviceIds.isNotEmpty
                  ? '${item.serviceIds.length} hizmet'
                  : null,
            ),
    ),
  );
}

class _AppointmentSelectionSheet<T> extends StatelessWidget {
  const _AppointmentSelectionSheet({
    required this.title,
    required this.description,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.items,
    required this.selectedId,
    required this.idOf,
    required this.cardBuilder,
  });

  final String title;
  final String description;
  final String emptyTitle;
  final String emptyMessage;
  final List<T> items;
  final int? selectedId;
  final int? Function(T item) idOf;
  final Widget Function(BuildContext context, T item, bool selected)
  cardBuilder;

  @override
  Widget build(BuildContext context) {
    final realItems = items.where((item) => item != null).toList();
    final showEmpty = items.isEmpty || (items.length == 1 && realItems.isEmpty);
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * .75,
        ),
        decoration: const BoxDecoration(
          color: WebeyColors.ivory,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: WebeyColors.borderSand,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 20,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: showEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: _BusinessInlineState(
                        message: '$emptyTitle. $emptyMessage',
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        20 + MediaQuery.of(context).padding.bottom,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final selected = idOf(item) == selectedId;
                        return GestureDetector(
                          onTap: () => Navigator.of(context).pop(item),
                          child: cardBuilder(context, item, selected),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentOptionCard extends StatelessWidget {
  const _AppointmentOptionCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? WebeyColors.warmCream : WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? WebeyColors.primaryGold : WebeyColors.borderSand,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF8C6F38)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (badge != null && badge!.trim().isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              badge!,
              style: const TextStyle(
                color: Color(0xFF8C6F38),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Icon(
            selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
            color: selected ? const Color(0xFF8C6F38) : WebeyColors.mutedTaupe,
          ),
        ],
      ),
    );
  }
}

Future<BusinessAppointment?> showAppointmentCreateSheet(
  BuildContext context, {
  DateTime? initialDate,
  BusinessRepository repository = BusinessRepository.instance,
}) {
  return showModalBottomSheet<BusinessAppointment>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AppointmentCreateSheet(
      initialDate: initialDate,
      repository: repository,
    ),
  );
}

class _AppointmentCreateSheet extends StatefulWidget {
  const _AppointmentCreateSheet({this.initialDate, required this.repository});

  final DateTime? initialDate;
  final BusinessRepository repository;

  @override
  State<_AppointmentCreateSheet> createState() =>
      _AppointmentCreateSheetState();
}

class _AppointmentCreateSheetState extends State<_AppointmentCreateSheet> {
  final _customerCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _picked;

  var _loading = true;
  var _saving = false;
  String? _loadError;
  String? _saveError;
  List<BusinessServiceItem> _services = const [];
  List<BusinessStaffItem> _staff = const [];
  BusinessServiceItem? _selectedService;
  BusinessStaffItem? _selectedStaff;

  @override
  void initState() {
    super.initState();
    _picked = widget.initialDate;
    _loadOptions();
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        widget.repository.getServices(),
        widget.repository.getStaff(),
      ]);
      if (!mounted) return;
      final services = (results[0] as List<BusinessServiceItem>)
          .where((s) => s.isActive)
          .toList();
      final staff = (results[1] as List<BusinessStaffItem>)
          .where((s) => s.isActive && s.name.trim().isNotEmpty)
          .toList();
      setState(() {
        _services = services;
        _staff = staff;
        _selectedService = services.isNotEmpty ? services.first : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _loadError = _friendlyBusinessError(
          error,
          'Hizmet ve personel listesi yüklenemedi.',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final base = _picked ?? now;
    final day = await showDatePicker(
      context: context,
      initialDate: base.isBefore(now) ? now : base,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null) return;
    if (!mounted) return;
    final time = await _pickQuarterTime(TimeOfDay.fromDateTime(base));
    if (time == null) return;
    setState(() {
      _picked = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    });
  }

  Future<TimeOfDay?> _pickQuarterTime(TimeOfDay initial) async {
    var hour = initial.hour.clamp(8, 23).toInt();
    const minutes = [0, 15, 30, 45];
    var minute = minutes.reduce(
      (a, b) =>
          (initial.minute - a).abs() <= (initial.minute - b).abs() ? a : b,
    );

    return showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Container(
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                20 + MediaQuery.of(sheetContext).padding.bottom,
              ),
              decoration: const BoxDecoration(
                color: WebeyColors.ivory,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Randevu saati',
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 18,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var h = 8; h <= 23; h++)
                        ChoiceChip(
                          label: Text(h.toString().padLeft(2, '0')),
                          selected: hour == h,
                          onSelected: (_) => setSheetState(() => hour = h),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in minutes)
                        ChoiceChip(
                          label: Text(m.toString().padLeft(2, '0')),
                          selected: minute == m,
                          onSelected: (_) => setSheetState(() => minute = m),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(
                        sheetContext,
                      ).pop(TimeOfDay(hour: hour, minute: minute)),
                      child: Text(
                        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} seç',
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _save() async {
    final name = _customerCtrl.text.trim();
    final phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (name.isEmpty) {
      setState(() => _saveError = 'Müşteri adı zorunlu.');
      return;
    }
    if (phone.isNotEmpty && phone.length != 10 && phone.length != 11) {
      setState(() => _saveError = 'Telefon numarası 10 veya 11 hane olmalı.');
      return;
    }
    if (_selectedService == null || _selectedService!.id == null) {
      setState(() => _saveError = 'Hizmet seçin.');
      return;
    }
    if (_picked == null) {
      setState(() => _saveError = 'Tarih ve saat seçin.');
      return;
    }
    if (![0, 15, 30, 45].contains(_picked!.minute)) {
      setState(
        () => _saveError = 'Randevu dakikası 00, 15, 30 veya 45 olmalı.',
      );
      return;
    }
    if (_picked!.isBefore(DateTime.now())) {
      setState(() => _saveError = 'Geçmiş bir tarih veya saat seçilemez.');
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final created = await widget.repository.createAppointment(
        customerName: name,
        customerPhone: phone,
        serviceId: _selectedService!.id!,
        staffId: _selectedStaff?.id,
        appointmentDate: _formatBusinessDate(_picked!),
        appointmentTime: _formatTime(_picked!),
        notes: _notesCtrl.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saveError = _friendlyBusinessError(
          error,
          'Randevu oluşturulamadı, lütfen tekrar deneyin.',
        );
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _picked == null
        ? 'Tarih / saat seçin'
        : '${_formatBusinessDate(_picked!)} · ${_formatTime(_picked!)}';
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: WebeyColors.ivory,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          20 + MediaQuery.of(context).padding.bottom,
        ),
        child: SingleChildScrollView(
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
              const SizedBox(height: 14),
              const Text(
                'Yeni Randevu',
                style: TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 20,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_loadError != null)
                _BusinessInlineState(
                  message: _loadError!,
                  actionLabel: 'Tekrar dene',
                  onAction: _loadOptions,
                )
              else if (_services.isEmpty) ...[
                _BusinessInlineState(
                  message:
                      'Önce hizmet ekleyin: Randevu oluşturmak için en az bir aktif hizmet gerekir.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Kapat'),
                  ),
                ),
              ] else ...[
                _sheetField(controller: _customerCtrl, hint: 'Müşteri adı *'),
                const SizedBox(height: 10),
                _sheetField(
                  controller: _phoneCtrl,
                  hint: '05xx xxx xx xx',
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                ),
                const SizedBox(height: 10),
                _appointmentPickerField(
                  icon: Icons.spa_outlined,
                  title: _selectedService?.name ?? 'Hizmet seçin *',
                  subtitle: _selectedService == null
                      ? 'Randevu için hizmet zorunlu'
                      : '${_selectedService!.durationMinutes} dk · ${_selectedService!.price.toStringAsFixed(0)} TL',
                  onTap: _pickService,
                ),
                const SizedBox(height: 10),
                _appointmentPickerField(
                  icon: Icons.person_outline_rounded,
                  title: _selectedStaff?.name ?? 'Personel seçilmedi',
                  subtitle:
                      _selectedStaff?.role ??
                      (_staff.isEmpty
                          ? 'Aktif personel bulunmuyor. Opsiyonel.'
                          : 'Randevuya personel ata'),
                  onTap: _pickStaff,
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pickDateTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: WebeyColors.warmCream,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: WebeyColors.borderSand),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.event_outlined,
                          size: 18,
                          color: WebeyColors.mutedTaupe,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            dateLabel,
                            style: const TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _sheetField(
                  controller: _notesCtrl,
                  hint: 'Not (opsiyonel)',
                  maxLines: 2,
                ),
                if (_saveError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _saveError!,
                    style: const TextStyle(
                      color: WebeyColors.errorRed,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Kaydet'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickService() async {
    final result = await _showAppointmentServicePicker(
      context,
      services: _services,
      selectedId: _selectedService?.id,
    );
    if (!mounted || result == null) return;
    setState(() => _selectedService = result);
  }

  Future<void> _pickStaff() async {
    final result = await _showAppointmentStaffPicker(
      context,
      staff: _staff,
      selectedId: _selectedStaff?.id,
    );
    if (!mounted) return;
    setState(() => _selectedStaff = result);
  }

  Widget _appointmentPickerField({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: WebeyColors.mutedTaupe),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: WebeyColors.mutedTaupe,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      decoration: InputDecoration(hintText: hint),
    );
  }
}

class _CalendarFilters {
  const _CalendarFilters({required this.status, required this.staffId});
  final String status;
  final String staffId;
}

class _CalendarFilterSheet extends StatefulWidget {
  const _CalendarFilterSheet({
    required this.initialStatus,
    required this.initialStaff,
    required this.staffChips,
  });

  final String initialStatus;
  final String initialStaff;
  final List<_StaffChipData> staffChips;

  @override
  State<_CalendarFilterSheet> createState() => _CalendarFilterSheetState();
}

class _CalendarFilterSheetState extends State<_CalendarFilterSheet> {
  late String _status = widget.initialStatus;
  late String _staffId = widget.initialStaff;

  static const _statusOptions = [
    ('all', 'Tümü'),
    ('pending', 'Bekleyen'),
    ('approved', 'Onaylı'),
    ('completed', 'Tamamlandı'),
    ('cancelled', 'İptal'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: WebeyColors.ivory,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
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
          const SizedBox(height: 14),
          const Text(
            'Filtrele',
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 20,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'DURUM',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final opt in _statusOptions)
                ChoiceChip(
                  label: Text(opt.$2),
                  selected: _status == opt.$1,
                  onSelected: (_) => setState(() => _status = opt.$1),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'PERSONEL',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final chip in widget.staffChips)
                ChoiceChip(
                  label: Text(chip.label),
                  selected: _staffId == chip.id,
                  onSelected: (_) => setState(() => _staffId = chip.id),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(
                context,
                _CalendarFilters(status: _status, staffId: _staffId),
              ),
              child: const Text('Uygula'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarSearchSheet extends StatefulWidget {
  const _CalendarSearchSheet({required this.initial});
  final String initial;

  @override
  State<_CalendarSearchSheet> createState() => _CalendarSearchSheetState();
}

class _CalendarSearchSheetState extends State<_CalendarSearchSheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: WebeyColors.ivory,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          20 + MediaQuery.of(context).padding.bottom,
        ),
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
            const SizedBox(height: 14),
            const Text(
              'Randevu Ara',
              style: TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 20,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Müşteri adı, hizmet veya personel',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, ''),
                    child: const Text('Temizle'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _ctrl.text),
                    child: const Text('Ara'),
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
