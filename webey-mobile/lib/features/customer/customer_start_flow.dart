import 'package:flutter/material.dart';

import '../../core/theme/webey_colors.dart';
import '../../features/auth/auth_gate.dart';
import '../splash/splash_and_legal_screens.dart';
import '../../features/customer/notifications/data/repositories/customer_notification_repository.dart';
import '../../features/customer/presentation/customer_appointments_screen.dart';
import '../../features/customer/presentation/customer_favorites_screen.dart';
import '../../features/customer/presentation/customer_home_screen.dart';
import '../../features/customer/presentation/customer_notifications_screen.dart';
import '../../features/customer/presentation/customer_profile_screen.dart';
import '../../features/customer/presentation/customer_search_screen.dart';
import '../../features/customer/presentation/salon_detail_screen.dart';
import '../../shared/models/beauty_models.dart';
import '../../shared/services/auth_service.dart';
import '../../shared/services/customer_fcm_service.dart';
import '../../shared/widgets/webey_back_handler.dart';

export 'presentation/customer_appointments_screen.dart';
export 'presentation/booking_flow.dart';
export 'presentation/customer_favorites_screen.dart';
export 'presentation/customer_home_screen.dart';
export 'presentation/customer_notifications_screen.dart';
export 'presentation/customer_profile_screen.dart';
export 'presentation/customer_search_screen.dart';
export 'presentation/legal_documents_screen.dart';
export 'presentation/salon_detail_screen.dart';

enum _CustomerStage { boot, splash, app }

class CustomerStartFlow extends StatefulWidget {
  const CustomerStartFlow({super.key});

  @override
  State<CustomerStartFlow> createState() => _CustomerStartFlowState();
}

class _CustomerStartFlowState extends State<CustomerStartFlow> {
  var _stage = _CustomerStage.boot;
  AuthUser? _bootUser;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final result = await WebeyAuthService.instance.me();
    if (!mounted) return;
    setState(() {
      if (result.success) {
        _bootUser = result.data;
        _stage = _CustomerStage.app;
      } else {
        _stage = _CustomerStage.splash;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Sistem geri tuşu: root route hiçbir zaman direkt pop olmaz;
    // interceptor'lar (tab/harita) tüketmezse çıkış onayı gösterilir.
    return WebeyExitGuard(
      child: switch (_stage) {
        _CustomerStage.boot => const _CustomerBootScreen(),
        _CustomerStage.splash => CustomerSplashScreen(
          onContinue: () => setState(() => _stage = _CustomerStage.app),
        ),
        _CustomerStage.app => CustomerShell(
          initialLoggedIn: _bootUser != null,
          initialUserName: _bootUser?.fullName,
        ),
      },
    );
  }
}

class CustomerShell extends StatefulWidget {
  const CustomerShell({
    super.key,
    this.initialLoggedIn = false,
    this.initialUserName,
  });

  final bool initialLoggedIn;
  final String? initialUserName;

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  var _index = 0;
  late bool _isLoggedIn;
  String? _userName;
  int _unreadCount = 0;
  WebeyBackRegistration? _backRegistration;

  /// Ana sayfadan kategoriyle Keşfet açıldığında uygulanacak filtre.
  String? _searchCategory;
  bool _searchCampaign = false;

  @override
  void initState() {
    super.initState();
    _isLoggedIn = widget.initialLoggedIn;
    _userName = widget.initialUserName;
    if (_isLoggedIn) {
      CustomerFcmService.instance.registerCurrentToken(reason: 'customerBoot');
      _fetchUnreadCount();
      if (_userName == null || _userName!.isEmpty) _fetchCurrentUser();
    } else {
      _bootstrapAuth();
    }
  }

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

  /// Sistem geri tuşu: ana tab dışındaysak önce Ana Sayfa'ya dön.
  bool _handleSystemBack() {
    if (_index != 0) {
      setState(() => _index = 0);
      return true;
    }
    return false;
  }

  Future<void> _bootstrapAuth() async {
    final result = await WebeyAuthService.instance.me();
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _isLoggedIn = true;
        _userName = result.data?.fullName;
      });
      CustomerFcmService.instance.registerCurrentToken(reason: 'customerMe');
      _fetchUnreadCount();
    }
  }

  Future<void> _fetchUnreadCount() async {
    final result = await CustomerNotificationRepository.instance
        .getNotifications();
    if (!mounted) return;
    setState(() => _unreadCount = result.unreadCount);
  }

  Future<void> _fetchCurrentUser() async {
    final result = await WebeyAuthService.instance.me();
    if (!mounted || !result.success) return;
    setState(() => _userName = result.data?.fullName);
  }

  void _login() {
    setState(() => _isLoggedIn = true);
    CustomerFcmService.instance.registerCurrentToken(reason: 'customerLogin');
    _fetchCurrentUser();
  }

  Future<void> _logout() async {
    await WebeyAuthService.instance.logout();
    if (!mounted) return;
    setState(() => _isLoggedIn = false);
  }

  Future<void> _openSalon(BuildContext context, Salon salon) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) =>
            SalonDetailScreen(
              salon: salon,
              isLoggedIn: _isLoggedIn,
              onAuthenticated: _login,
              onViewAppointments: () => setState(() => _index = 2),
              onGoHome: () => setState(() => _index = 0),
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      CustomerHomeScreen(
        userName: _userName,
        unreadCount: _unreadCount,
        isLoggedIn: _isLoggedIn,
        onLogin: _login,
        onOpenSearch: () => setState(() {
          _searchCategory = null;
          _searchCampaign = false;
          _index = 1;
        }),
        onOpenCategory: (slug) => setState(() {
          _searchCategory = slug;
          _searchCampaign = false;
          _index = 1;
        }),
        onOpenCampaigns: () => setState(() {
          _searchCategory = null;
          _searchCampaign = true;
          _index = 1;
        }),
        onOpenSalon: (salon) => _openSalon(context, salon),
        onOpenAppointments: () => setState(() => _index = 2),
        onOpenNotifications: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CustomerNotificationsScreen(
                onOpenAppointments: () => setState(() => _index = 2),
                onOpenSearch: () => setState(() => _index = 1),
              ),
            ),
          );
          if (mounted) _fetchUnreadCount();
        },
      ),
      CustomerSearchScreen(
        key: ValueKey('search-${_searchCategory ?? ''}-$_searchCampaign'),
        initialCategory: _searchCategory,
        initialCampaign: _searchCampaign,
        onOpenSalon: (salon) => _openSalon(context, salon),
      ),
      _isLoggedIn
          ? CustomerAppointmentsScreen(
              onNavigateToSearch: () => setState(() => _index = 1),
            )
          : AuthGateScreen(
              reason: 'Randevularını takip etmek için giriş yap',
              onAuthenticated: _login,
              onContinueGuest: () => setState(() => _index = 0),
            ),
      _isLoggedIn
          ? CustomerFavoritesScreen(
              onOpenSalon: (salon) => _openSalon(context, salon),
            )
          : AuthGateScreen(
              reason:
                  'Favori salonlarını ve koleksiyonlarını görmek için giriş yap',
              onAuthenticated: _login,
              onContinueGuest: () => setState(() => _index = 0),
            ),
      _isLoggedIn
          ? CustomerProfileScreen(
              onLogout: _logout,
              onNavigateToAppointments: () => setState(() => _index = 2),
              onNavigateToFavorites: () => setState(() => _index = 3),
              onOpenSalon: (salon) => _openSalon(context, salon),
            )
          : AuthGateScreen(
              reason: 'Profilini ve favorilerini yönetmek için giriş yap',
              onAuthenticated: _login,
              onContinueGuest: () => setState(() => _index = 0),
            ),
    ];

    return Scaffold(
      body: screens[_index],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFAF6F0), // WebeyColors.ivory
          border: Border(top: BorderSide(color: Color(0xFFE8DFD4))),
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
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
              icon: Icon(Icons.search_outlined),
              activeIcon: Icon(Icons.search_rounded),
              label: 'Keşfet',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.event_note_outlined),
              activeIcon: Icon(Icons.event_note_rounded),
              label: 'Randevularım',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.favorite_border),
              activeIcon: Icon(Icons.favorite_rounded),
              label: 'Favoriler',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerBootScreen extends StatelessWidget {
  const _CustomerBootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: WebeyColors.primaryGold,
          ),
        ),
      ),
    );
  }
}
