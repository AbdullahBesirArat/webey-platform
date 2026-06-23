// lib/features/customer/presentation/booking_flow.dart
//
// Claude Design → Flutter dönüşümü
// Webey Beauty — 5 Adımlı Randevu Akışı
// Ekranlar: Hizmet → Uzman → Tarih/Saat → Onay → Başarılı

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/storage/secure_token_storage.dart';
import '../../../core/theme/webey_colors.dart';
import '../../../shared/widgets/webey_back_handler.dart';
import '../../../shared/widgets/webey_toast.dart';
import '../../auth/auth_gate.dart';
import '../../../shared/models/beauty_models.dart';
import '../booking/data/booking_catalog.dart';
import '../booking/data/models/booking_catalog_models.dart';
import '../booking/data/models/booking_models.dart';
import '../discovery/data/models/salon_campaign.dart';
import '../booking/data/repositories/booking_repository.dart';
import '../appointments/data/repositories/customer_appointment_repository.dart';
import '../widgets/deposit_instructions_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BOOKING STATE
// ─────────────────────────────────────────────────────────────────────────────

class BookingState {
  const BookingState({
    this.serviceId,
    this.staffId,
    this.selectedDate,
    this.selectedTime,
    this.startsAt,
    this.endsAt,
    this.durationMinutes,
    this.lockToken,
    this.note = '',
  });
  final String? serviceId;
  final String? staffId;
  final DateTime? selectedDate;
  final String? selectedTime;
  final String? startsAt;
  final String? endsAt;
  final int? durationMinutes;
  final String? lockToken;
  final String note;

  BookingState copyWith({
    String? serviceId,
    String? staffId,
    DateTime? selectedDate,
    String? selectedTime,
    String? startsAt,
    String? endsAt,
    int? durationMinutes,
    String? lockToken,
    bool clearLockToken = false,
    String? note,
  }) => BookingState(
    serviceId: serviceId ?? this.serviceId,
    staffId: staffId ?? this.staffId,
    selectedDate: selectedDate ?? this.selectedDate,
    selectedTime: selectedTime ?? this.selectedTime,
    startsAt: startsAt ?? this.startsAt,
    endsAt: endsAt ?? this.endsAt,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    lockToken: clearLockToken ? null : (lockToken ?? this.lockToken),
    note: note ?? this.note,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT — BookingFlow
// ─────────────────────────────────────────────────────────────────────────────

class BookingFlow extends StatefulWidget {
  const BookingFlow({
    super.key,
    required this.salon,
    required this.onComplete,
    required this.onCancel,
    required this.onHome,
    this.isLoggedIn = false,
    this.onAuthenticated,
    this.initialServices,
    this.initialStaff,
    this.depositRatePct,
    this.depositPreview,
  });
  final Salon salon;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final VoidCallback onHome;
  final bool isLoggedIn;
  final VoidCallback? onAuthenticated;
  final List<BookingServiceOption>? initialServices;
  final List<BookingStaffOption>? initialStaff;

  /// Salonun gerçek kapora oranı (%). null ise tutar booking sonrası gösterilir.
  final int? depositRatePct;

  /// Kapora gerekiyorsa salonun IBAN bilgileri (randevu oluşmadan önizleme).
  final DepositInfo? depositPreview;

  @override
  State<BookingFlow> createState() => _BookingFlowState();
}

class _BookingFlowState extends State<BookingFlow> with WidgetsBindingObserver {
  static const _repository = BookingRepository.instance;
  static const _bookingWindow = Duration(minutes: 5);

  late final BookingCatalog _catalog;
  int _step = 0;
  late BookingState _booking;
  DateTime? _bookingExpiresAt;
  Timer? _bookingTimer;
  int _remainingSeconds = _bookingWindow.inSeconds;
  bool _timerStopped = false;

  List<BookingAvailabilitySlot> _slots = const [];
  bool _loadingSlots = false;
  String? _slotsError;
  bool _locking = false;

  // Akıllı öneriler (gerçek availability taramasından)
  List<BookingSmartSuggestion> _suggestions = const [];
  bool _loadingSuggestions = false;
  String? _suggestionsSignature; // tekrar tarama yapmamak için
  bool _confirming = false;
  String? _confirmError;

  // Deposit state
  //
  // MVP: Webey ödeme tahsil etmez. Kapora doğrudan salonun IBAN'ına yapılır,
  // bu yüzden eski online (iyzico) ödeme ekranı customer akışında gösterilmez.
  // BookingDepositScreen kodu silinmedi; yalnızca bu bayrakla bypass edildi.
  // Online tahsilat tekrar açılırsa bu bayrağı true yapmak yeterli.
  // (const değil; aksi halde aşağıdaki dal "dead code" olarak işaretlenir.)
  final bool _onlineDepositEnabled = false;

  BookingResult? _bookingResult;
  // Kilitlenen slot için sunucunun döndürdüğü kampanya teklifi / uyumsuzluk nedeni.
  SalonCampaign? _campaignQuote;
  String? _campaignReason;
  bool _depositRequired = false;
  double? _depositAmount;
  bool _depositPaid = false;
  bool _depositStarting = false;
  String? _depositError;
  String? _depositCheckoutUrl;

  // Manuel IBAN kapora: "IBAN'a parayı gönderdim" durumu.
  bool _markingDepositSent = false;
  DepositInfo? _depositOverride;

  // Randevu iptali (success ekranındaki "Randevuyu iptal et").
  bool _cancellingAppointment = false;
  bool _appointmentCancelRequested = false;

  // Banka açıklama kodu adayı: confirm ekranında gösterilir, book.php'ye
  // gönderilir; backend doğrular/benzersizleştirir (çakışmazsa aynı kod kalır).
  String? _depositReferenceCandidate;

  String get _depositReferenceCode => _depositReferenceCandidate ??=
      _generateDepositReferenceCandidate(widget.salon.name);
  Timer? _depositPollTimer;
  int _depositPollCount = 0;
  static const _depositPollMaxSeconds = 60;
  static const _depositPollIntervalSeconds = 3;

  int get _businessId => int.tryParse(widget.salon.id) ?? 0;

  BookingServiceOption? get _selectedService =>
      _catalog.serviceByKey(_booking.serviceId);

  BookingStaffOption? get _selectedStaff =>
      _catalog.staffByKey(_booking.staffId);

  int get _serviceId => _selectedService?.id ?? 0;

  int? get _staffId => _selectedStaff?.id;

  int get _durationMinutes =>
      _selectedService?.durationMinutes ?? _booking.durationMinutes ?? 60;

  bool get _canBook => _selectedService?.isBookable ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _catalog = BookingCatalog(
      services: widget.initialServices,
      staff: widget.initialStaff,
    );
    final defaultService = _catalog.defaultService;
    final defaultStaff = _catalog.defaultStaff;
    _booking = BookingState(
      serviceId: defaultService.key,
      staffId: defaultStaff.key,
      selectedDate: DateTime.now(),
      durationMinutes: defaultService.durationMinutes,
    );
    _startBookingTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bookingTimer?.cancel();
    _depositPollTimer?.cancel();
    _releaseLock();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncBookingTimer();
    }
  }

  void _startBookingTimer() {
    _bookingExpiresAt = DateTime.now().add(_bookingWindow);
    _remainingSeconds = _bookingWindow.inSeconds;
    _timerStopped = false;
    _bookingTimer?.cancel();
    _bookingTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _syncBookingTimer(),
    );
  }

  void _stopBookingTimer() {
    _timerStopped = true;
    _bookingTimer?.cancel();
  }

  void _syncBookingTimer() {
    if (!mounted || _timerStopped) return;
    final expiresAt = _bookingExpiresAt;
    if (expiresAt == null) return;
    final remaining = expiresAt.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      _expireBookingFlow();
      return;
    }
    if (remaining != _remainingSeconds) {
      setState(() => _remainingSeconds = remaining);
    }
  }

  String get _timerLabel {
    final seconds = _remainingSeconds.clamp(0, _bookingWindow.inSeconds);
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  bool get _timerWarning => _remainingSeconds <= 60;

  Future<void> _expireBookingFlow() async {
    if (_timerStopped) return;
    _stopBookingTimer();
    await _releaseLock();
    if (!mounted) return;
    final defaultService = _catalog.defaultService;
    final defaultStaff = _catalog.defaultStaff;
    setState(() {
      _step = 0;
      _booking = BookingState(
        serviceId: defaultService.key,
        staffId: defaultStaff.key,
        selectedDate: DateTime.now(),
        durationMinutes: defaultService.durationMinutes,
      );
      _slots = const [];
      _slotsError = null;
      _suggestions = const [];
      _suggestionsSignature = null;
      _locking = false;
      _confirming = false;
      _confirmError = null;
    });
    WebeyToast.error(
      context,
      'Randevu oluşturma süreniz doldu, lütfen tekrar başlayın.',
    );
    _startBookingTimer();
  }

  Future<void> _releaseLock() async {
    final token = _booking.lockToken;
    if (token == null || token.isEmpty) return;
    await _repository.unlockSlot(lockToken: token);
    if (mounted && _booking.lockToken == token) {
      setState(() => _booking = _booking.copyWith(clearLockToken: true));
    }
  }

  Future<bool> _hasAuthToken() async {
    if (widget.isLoggedIn) return true;
    final token = await const SecureTokenStorage().readToken();
    return token != null && token.isNotEmpty;
  }

  Future<bool> _requireAuth({required String reason}) async {
    if (await _hasAuthToken()) return true;
    if (!mounted) return false;
    var authed = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => AuthGateScreen(
          reason: reason,
          onAuthenticated: () {
            authed = true;
            widget.onAuthenticated?.call();
            Navigator.of(ctx).pop();
          },
          onContinueGuest: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
    if (!mounted) return false;
    return authed || await _hasAuthToken();
  }

  void _next() {
    if (_step < 5) setState(() => _step++);
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      _releaseLock();
      widget.onCancel();
    }
  }

  Future<void> _abortFlow() async {
    await _releaseLock();
    if (mounted) widget.onCancel();
  }

  Future<void> _loadAvailability(DateTime date) async {
    if (_businessId < 1 || _serviceId < 1) return;
    setState(() {
      _loadingSlots = true;
      _slotsError = null;
    });
    final result = await _repository.getAvailability(
      businessId: _businessId,
      serviceId: _serviceId,
      date: date,
      staffId: _staffId,
      durationMinutes: _durationMinutes,
    );
    if (!mounted) return;
    if (result.success && result.data != null) {
      setState(() {
        _slots = result.data!.items;
        _loadingSlots = false;
        _slotsError = null;
      });
    } else {
      setState(() {
        _slots = const [];
        _loadingSlots = false;
        _slotsError =
            result.errorMessage ??
            'Müsait saatler yüklenemedi. Lütfen tekrar deneyin.';
      });
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static const _monthShortTr = [
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

  String _suggestionTitle(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Bugün';
    if (diff == 1) return 'Yarın';
    return '${day.day} ${_monthShortTr[day.month - 1]}';
  }

  // Önümüzdeki 7 günü gerçek availability endpoint'inden tarayıp akıllı
  // önerileri üretir. Sadece available=true ve gelecekteki slotlar kullanılır.
  Future<void> _loadSuggestions() async {
    if (_businessId < 1 || _serviceId < 1) return;
    final signature =
        '$_businessId-$_serviceId-${_staffId ?? 0}-$_durationMinutes';
    if (signature == _suggestionsSignature && _suggestions.isNotEmpty) return;

    setState(() {
      _loadingSuggestions = true;
      _suggestionsSignature = signature;
    });
    debugPrint('[smart] suggestions loading started sig=$signature');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const scanDays = 7;

    final results = await Future.wait(
      List.generate(scanDays, (i) {
        final day = today.add(Duration(days: i));
        return _repository.getAvailability(
          businessId: _businessId,
          serviceId: _serviceId,
          date: day,
          staffId: _staffId,
          durationMinutes: _durationMinutes,
        );
      }),
    );
    if (!mounted) return;

    // Tüm günlerdeki gerçek available + gelecekteki slotları topla.
    final available =
        <({DateTime dt, DateTime day, String time, String startsAt})>[];
    for (final r in results) {
      if (!r.success || r.data == null) continue;
      for (final slot in r.data!.items) {
        if (!slot.available) continue;
        final dt = DateTime.tryParse(slot.startsAt.replaceFirst(' ', 'T'));
        if (dt == null || !dt.isAfter(now)) continue;
        available.add((
          dt: dt,
          day: DateTime(dt.year, dt.month, dt.day),
          time: slot.time.isNotEmpty
              ? slot.time
              : '${_two(dt.hour)}:${_two(dt.minute)}',
          startsAt: slot.startsAt,
        ));
      }
    }
    available.sort((a, b) => a.dt.compareTo(b.dt));
    debugPrint(
      '[smart] scanned days=$scanDays available slots=${available.length}',
    );

    final suggestions = <BookingSmartSuggestion>[];
    final usedKeys = <String>{};

    void add(
      BookingSuggestionKind kind,
      String label,
      ({DateTime dt, DateTime day, String time, String startsAt}) s,
    ) {
      final key = '${s.day.year}-${s.day.month}-${s.day.day} ${s.time}';
      if (usedKeys.contains(key)) return;
      usedKeys.add(key);
      suggestions.add(
        BookingSmartSuggestion(
          kind: kind,
          label: label,
          titleText: _suggestionTitle(s.day),
          date: s.day,
          time: s.time,
          startsAt: s.startsAt,
        ),
      );
    }

    if (available.isNotEmpty) {
      // 1) EN YAKIN (uzman seçiliyse FAVORİ UZMAN) — global en erken slot.
      final earliest = available.first;
      if (_staffId != null) {
        add(BookingSuggestionKind.favoriteStaff, 'FAVORİ UZMAN', earliest);
      } else {
        add(BookingSuggestionKind.earliest, 'EN YAKIN', earliest);
      }

      // 2) DAHA SAKİN SAAT — sakin saat aralıklarına göre (10-12, 14-16, 16+).
      bool inWindow(int h, int lo, int hi) => h >= lo && h < hi;
      ({DateTime dt, DateTime day, String time, String startsAt})? calmer;
      for (final window in [
        (lo: 10, hi: 12),
        (lo: 14, hi: 16),
        (lo: 16, hi: 24),
      ]) {
        for (final s in available) {
          final key = '${s.day.year}-${s.day.month}-${s.day.day} ${s.time}';
          if (usedKeys.contains(key)) continue;
          if (inWindow(s.dt.hour, window.lo, window.hi)) {
            calmer = s;
            break;
          }
        }
        if (calmer != null) break;
      }
      if (calmer != null) {
        add(BookingSuggestionKind.calmer, 'DAHA SAKİN SAAT', calmer);
      }

      // 3) ALTERNATİF GÜN — en erken slotun gününden SONRAKİ ilk müsait gün.
      ({DateTime dt, DateTime day, String time, String startsAt})? altDay;
      for (final s in available) {
        if (s.day.isAfter(earliest.day)) {
          final key = '${s.day.year}-${s.day.month}-${s.day.day} ${s.time}';
          if (!usedKeys.contains(key)) {
            altDay = s;
            break;
          }
        }
      }
      if (altDay != null) {
        add(BookingSuggestionKind.alternativeDay, 'ALTERNATİF GÜN', altDay);
      }
    }

    final capped = suggestions.take(3).toList();
    debugPrint(
      '[smart] chosen suggestions=${capped.map((e) => '${e.label}:${e.titleText} ${e.time}').join(', ')}',
    );
    if (!mounted) return;
    setState(() {
      _suggestions = capped;
      _loadingSuggestions = false;
    });
  }

  // Öneri kartına basınca: o güne geç, availability'yi yükle, slotu kilitle.
  Future<void> _onSuggestionTap(BookingSmartSuggestion s) async {
    debugPrint('[smart] selected suggestion ${s.titleText} ${s.time}');
    await _releaseLock();
    setState(() {
      _booking = _booking.copyWith(
        selectedDate: s.date,
        clearLockToken: true,
        selectedTime: null,
        startsAt: null,
        endsAt: null,
      );
    });
    await _loadAvailability(s.date);
    if (!mounted) return;
    BookingAvailabilitySlot? match;
    for (final slot in _slots) {
      if (slot.available && slot.time == s.time) {
        match = slot;
        break;
      }
    }
    if (match == null) {
      _showSnack('Bu saat artık müsait değil, lütfen başka bir saat seçin.');
      // Öneriler değişmiş olabilir; yeniden tara.
      _suggestionsSignature = null;
      await _loadSuggestions();
      return;
    }
    await _lockSlot(match);
  }

  Future<bool> _lockSlot(BookingAvailabilitySlot slot) async {
    if (!slot.available) return false;
    if (!await _requireAuth(
      reason: 'Randevu saatini ayırmak için giriş yapın',
    )) {
      return false;
    }

    setState(() => _locking = true);
    await _releaseLock();

    final result = await _repository.lockSlot(
      businessId: _businessId,
      serviceId: _serviceId,
      startsAt: slot.startsAt,
      staffId: _staffId,
      durationMinutes: _durationMinutes,
    );
    if (!mounted) return false;

    if (result.success && result.data != null && result.data!.locked) {
      setState(() {
        _booking = _booking.copyWith(
          selectedTime: slot.time,
          startsAt: result.data!.startsAt,
          endsAt: result.data!.endsAt,
          lockToken: result.data!.lockToken,
        );
        _campaignQuote = result.data!.campaign;
        _campaignReason = result.data!.campaignReason;
        _locking = false;
      });
      return true;
    }

    setState(() => _locking = false);
    _showSnack(
      result.errorMessage ??
          'Bu saat artık müsait değil. Lütfen başka bir saat seçin.',
    );
    await _loadAvailability(_booking.selectedDate ?? DateTime.now());
    return false;
  }

  /// Kapora gerekiyor mu? (salonun gerçek politikası — confirm ekranı için)
  bool get _depositRequiredForBooking =>
      (widget.depositPreview?.required ?? false) ||
      (widget.depositRatePct ?? 0) > 0;

  /// Yeni akış: kapora gerekiyorsa randevu yalnızca müşteri "IBAN'a parayı
  /// attım" dediğinde oluşturulur ve deposit_status doğrudan
  /// customer_marked_sent yazılır. Kaporasız salonlarda klasik oluşturma.
  Future<void> _confirmBooking() async {
    if (!_canBook) {
      _showSnack('Bu hizmet için randevu oluşturma yakında aktif.');
      return;
    }
    final startsAt = _booking.startsAt;
    if (startsAt == null || startsAt.isEmpty) {
      _showSnack('Lütfen müsait bir saat seçin.');
      return;
    }
    final depositSent = _depositRequiredForBooking;
    // Kapora gerekli ama salon IBAN'ı yoksa randevu OLUŞTURULMAZ.
    if (depositSent && !(widget.depositPreview?.hasIban ?? false)) {
      WebeyToast.error(
        context,
        'Salonun kapora ödeme bilgileri eksik. Lütfen daha sonra tekrar deneyin.',
      );
      return;
    }
    if (!await _requireAuth(reason: 'Randevu oluşturmak için giriş yapın')) {
      return;
    }

    setState(() {
      _confirming = true;
      _confirmError = null;
    });

    final result = await _repository.bookAppointment(
      businessId: _businessId,
      serviceId: _serviceId,
      startsAt: startsAt,
      staffId: _staffId,
      durationMinutes: _durationMinutes,
      lockToken: _booking.lockToken,
      notes: _booking.note,
      depositSent: depositSent,
      depositReferenceCode: depositSent ? _depositReferenceCode : null,
    );

    if (!mounted) return;

    if (result.success && result.data != null) {
      final br = result.data!;
      _stopBookingTimer();
      setState(() {
        _confirming = false;
        _booking = _booking.copyWith(clearLockToken: true);
        _bookingResult = br;
        _depositRequired = br.depositRequired;
        _depositAmount = br.depositAmount;
        _depositPaid = false;
        _depositError = null;
        _depositCheckoutUrl = null;
      });
      // Kaporalı akışta toast YOK: success ekranı durumu kendisi anlatır
      // (büyük toast üst bölümü kapatıyordu). Kaporasızda kısa onay yeterli.
      if (!depositSent) {
        WebeyToast.success(context, 'Randevunuz oluşturuldu.');
      }
      _next(); // step 3 → 4 (deposit or skip)
      return;
    }

    setState(() {
      _confirming = false;
      _confirmError =
          result.errorMessage ??
          'Randevu oluşturulamadı. Lütfen tekrar deneyin.';
    });
    WebeyToast.error(context, _confirmError!);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    WebeyToast.info(context, message);
  }

  /// Manuel IBAN kapora: müşteri "IBAN'a yolladım" der.
  Future<void> _markDepositSent() async {
    if (_markingDepositSent) return;
    final apptId = int.tryParse(_bookingResult?.appointmentId ?? '') ?? 0;
    if (apptId < 1) return;

    setState(() => _markingDepositSent = true);
    final result = await _repository.markDepositSent(appointmentId: apptId);
    if (!mounted) return;

    setState(() {
      _markingDepositSent = false;
      if (result.success) {
        final base = _depositOverride ?? _bookingResult?.deposit;
        _depositOverride = base?.copyWith(
          status: result.data ?? 'customer_marked_sent',
        );
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

  /// Success ekranından randevu iptali (IBAN ödeme bekleyen randevu).
  Future<void> _cancelAppointment() async {
    if (_cancellingAppointment || _appointmentCancelRequested) return;
    final apptId = _bookingResult?.appointmentId ?? '';
    if (apptId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WebeyColors.softWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Randevuyu iptal et',
          style: TextStyle(
            color: WebeyColors.darkEspresso,
            fontFamily: 'Georgia',
            fontSize: 18,
          ),
        ),
        content: const Text(
          'Bu randevu için iptal talebi oluşturulacak. İşletme onayladığında '
          'iptal gerçekleşir.',
          style: TextStyle(fontSize: 13, height: 1.5),
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
              'Randevuyu iptal et',
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

    setState(() => _cancellingAppointment = true);
    final ok = await CustomerAppointmentRepository.instance.cancelAppointment(
      apptId,
    );
    if (!mounted) return;

    setState(() {
      _cancellingAppointment = false;
      _appointmentCancelRequested = ok;
    });

    if (ok) {
      WebeyToast.success(
        context,
        'İptal talebiniz işletmeye iletildi. Onaylandığında bilgilendirileceksiniz.',
      );
    } else {
      WebeyToast.error(
        context,
        'İptal talebi gönderilemedi. Lütfen tekrar deneyin.',
      );
    }
  }

  Future<void> _startDepositPayment() async {
    final apptId = int.tryParse(_bookingResult?.appointmentId ?? '') ?? 0;
    if (apptId < 1) return;

    setState(() {
      _depositStarting = true;
      _depositError = null;
    });

    final result = await _repository.startDepositPayment(appointmentId: apptId);
    if (!mounted) return;

    if (!result.success || result.data == null) {
      setState(() {
        _depositStarting = false;
        _depositError = result.errorMessage ?? 'Ödeme başlatılamadı.';
      });
      return;
    }

    final dr = result.data!;

    if (dr.alreadyPaid) {
      setState(() {
        _depositStarting = false;
        _depositPaid = true;
      });
      _next(); // deposit → success
      return;
    }

    final url = dr.checkoutUrl ?? '';
    if (url.isEmpty) {
      setState(() {
        _depositStarting = false;
        _depositError = 'Ödeme sayfası adresi alınamadı.';
      });
      return;
    }

    setState(() {
      _depositStarting = false;
      _depositCheckoutUrl = url;
    });

    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _depositError = 'Tarayıcı açılamadı. Lütfen tekrar deneyin.',
      );
      return;
    }

    _startDepositPoll(apptId);
  }

  void _startDepositPoll(int appointmentId) {
    _depositPollTimer?.cancel();
    _depositPollCount = 0;
    _depositPollTimer = Timer.periodic(
      const Duration(seconds: _depositPollIntervalSeconds),
      (_) => _checkDepositStatus(appointmentId),
    );
  }

  Future<void> _checkDepositStatus(int appointmentId) async {
    final maxPolls = _depositPollMaxSeconds ~/ _depositPollIntervalSeconds;
    _depositPollCount++;

    if (_depositPollCount > maxPolls) {
      _depositPollTimer?.cancel();
      if (mounted) {
        setState(
          () => _depositError =
              'Ödeme doğrulanamadı. Randevularım sayfasından kontrol edebilirsiniz.',
        );
      }
      return;
    }

    final result = await _repository.getDepositStatus(
      appointmentId: appointmentId,
    );
    if (!mounted) return;

    if (!result.success || result.data == null) return;

    final status = result.data!;
    if (status.isPaid) {
      _depositPollTimer?.cancel();
      setState(() {
        _depositPaid = true;
        _depositError = null;
      });
      _next(); // deposit → success
    } else if (status.isFailed || status.isCancelled) {
      _depositPollTimer?.cancel();
      setState(
        () => _depositError = 'Ödeme başarısız oldu. Tekrar deneyebilirsiniz.',
      );
    }
  }

  /// Sistem geri tuşu: route'u komple kapatmak yerine adım adım geri sarar.
  /// - Success ekranı (randevu oluştu): salon detayına dön.
  /// - Ara adımlar: bir önceki adıma dön.
  /// - İlk adım: akıştan çıkmadan önce onay sor.
  Future<void> _handleSystemBack() async {
    if (_step >= 4) {
      widget.onCancel();
      return;
    }
    if (_step > 0) {
      _back();
      return;
    }
    final leave = await showWebeyConfirmDialog(
      context,
      icon: Icons.event_busy_rounded,
      title: 'Randevu oluşturma işleminden çıkmak istiyor musunuz?',
      message: 'Seçimleriniz kaydedilmeden akıştan çıkacaksınız.',
      cancelLabel: 'Vazgeç',
      confirmLabel: 'Çık',
    );
    if (leave == true && mounted) {
      _abortFlow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _releaseLock();
        } else {
          _handleSystemBack();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: WebeyColors.ivory,
          body: SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, animation) {
                return SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(1.0, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                  child: child,
                );
              },
              child: _buildStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return BookingServiceScreen(
          key: const ValueKey(0),
          salon: widget.salon,
          services: _catalog.services,
          showCategoryChips: _catalog.usesMockServices,
          selectedServiceId: _booking.serviceId,
          timerLabel: _timerLabel,
          timerWarning: _timerWarning,
          onBack: _back,
          onNext: (id) {
            final service = _catalog.serviceByKey(id);
            _releaseLock();
            setState(
              () => _booking = _booking.copyWith(
                serviceId: id,
                durationMinutes: service?.durationMinutes,
                clearLockToken: true,
                selectedTime: null,
                startsAt: null,
                endsAt: null,
              ),
            );
            _next();
          },
        );
      case 1:
        return BookingStaffScreen(
          key: const ValueKey(1),
          staff: _catalog.staff,
          selectedStaffId: _booking.staffId,
          timerLabel: _timerLabel,
          timerWarning: _timerWarning,
          onBack: _back,
          onNext: (id) {
            _releaseLock();
            setState(
              () => _booking = _booking.copyWith(
                staffId: id,
                clearLockToken: true,
                selectedTime: null,
                startsAt: null,
                endsAt: null,
              ),
            );
            _loadAvailability(_booking.selectedDate ?? DateTime.now());
            _loadSuggestions();
            _next();
          },
        );
      case 2:
        return BookingDateTimeScreen(
          key: ValueKey('dt-${_booking.selectedDate?.millisecondsSinceEpoch}'),
          selectedDate: _booking.selectedDate,
          selectedTime: _booking.selectedTime,
          staffName: _selectedStaff?.name ?? 'Uzman',
          durationLabel: '$_durationMinutes dk',
          slots: _slots,
          loadingSlots: _loadingSlots,
          slotsError: _slotsError,
          locking: _locking,
          suggestions: _suggestions,
          loadingSuggestions: _loadingSuggestions,
          timerLabel: _timerLabel,
          timerWarning: _timerWarning,
          onSuggestionTap: _onSuggestionTap,
          onBack: _back,
          onDateChanged: (date) {
            _releaseLock();
            setState(
              () => _booking = _booking.copyWith(
                selectedDate: date,
                clearLockToken: true,
                selectedTime: null,
                startsAt: null,
                endsAt: null,
              ),
            );
            _loadAvailability(date);
          },
          onSlotSelected: _lockSlot,
          onNext: () {
            if (_booking.lockToken == null || _booking.selectedTime == null) {
              _showSnack('Lütfen müsait bir saat seçin.');
              return;
            }
            _next();
          },
        );
      case 3:
        return BookingConfirmScreen(
          key: const ValueKey(3),
          salon: widget.salon,
          booking: _booking,
          catalog: _catalog,
          canConfirm: _canBook,
          depositRatePct: widget.depositRatePct,
          depositPreview: widget.depositPreview,
          depositReferenceCode: _depositRequiredForBooking
              ? _depositReferenceCode
              : null,
          campaign: _campaignQuote,
          campaignReason: _campaignReason,
          timerLabel: _timerLabel,
          timerWarning: _timerWarning,
          onBack: _back,
          onAbort: _abortFlow,
          onConfirm: _confirmBooking,
          confirming: _confirming,
          confirmError: _confirmError,
          onNoteChanged: (n) =>
              setState(() => _booking = _booking.copyWith(note: n)),
        );
      case 4:
        // Online (iyzico) ödeme ekranı yalnızca explicit online tahsilat
        // modunda gösterilir. MVP'de manuel IBAN modu aktif olduğundan
        // (kapora doğrudan salona), bu ekran atlanır ve doğrudan başarı
        // ekranına geçilir; kapora talimatı (IBAN) success'te gösterilir.
        if (_onlineDepositEnabled && _depositRequired && !_depositPaid) {
          return BookingDepositScreen(
            key: const ValueKey(4),
            salon: widget.salon,
            booking: _booking,
            catalog: _catalog,
            depositAmount: _depositAmount,
            checkoutUrl: _depositCheckoutUrl,
            starting: _depositStarting,
            error: _depositError,
            onStartPayment: _startDepositPayment,
            onSkip: _next,
          );
        }
        // Manuel IBAN kapora veya kaporasız: doğrudan başarı ekranı.
        // Kapora gerekiyorsa DepositInstructionsCard IBAN/tutar/açıklama kodunu
        // (IBAN eksikse uygun mesajı) gösterir.
        return BookingSuccessScreen(
          key: const ValueKey('success-nodeposit'),
          salon: widget.salon,
          booking: _booking,
          catalog: _catalog,
          depositPaid: false,
          depositAmount: null,
          deposit: _depositOverride ?? _bookingResult?.deposit,
          campaign: _bookingResult?.campaign ?? _campaignQuote,
          finalAmount: _bookingResult?.finalAmount,
          remainingAmount: _bookingResult?.remainingAmount,
          onMarkDepositSent: _markDepositSent,
          markingDepositSent: _markingDepositSent,
          onCancelAppointment: _cancelAppointment,
          cancellingAppointment: _cancellingAppointment,
          appointmentCancelRequested: _appointmentCancelRequested,
          onViewAppointments: widget.onComplete,
          onHome: widget.onHome,
        );
      case 5:
        return BookingSuccessScreen(
          key: const ValueKey(5),
          salon: widget.salon,
          booking: _booking,
          catalog: _catalog,
          depositPaid: _depositPaid,
          depositAmount: _depositAmount,
          deposit: _depositOverride ?? _bookingResult?.deposit,
          campaign: _bookingResult?.campaign ?? _campaignQuote,
          finalAmount: _bookingResult?.finalAmount,
          remainingAmount: _bookingResult?.remainingAmount,
          onMarkDepositSent: _markDepositSent,
          markingDepositSent: _markingDepositSent,
          onCancelAppointment: _cancelAppointment,
          cancellingAppointment: _cancellingAppointment,
          appointmentCancelRequested: _appointmentCancelRequested,
          onViewAppointments: widget.onComplete,
          onHome: widget.onHome,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// İşletme adından banka açıklama kodu adayı: WEBEY-{SLUG}-{RASTGELE}.
/// Türkçe karakterler sadeleştirilir (Ğ→G, Ü→U, Ş→S, İ→I, Ö→O, Ç→C);
/// ilk kelimeden max 8 karakter alınır. Nihai/benzersiz kod backend'de
/// üretilir — bu yalnızca confirm ekranı önizlemesi için adaydır.
String _generateDepositReferenceCandidate(String salonName) {
  const trMap = {
    'Ğ': 'G',
    'ğ': 'G',
    'Ü': 'U',
    'ü': 'U',
    'Ş': 'S',
    'ş': 'S',
    'İ': 'I',
    'ı': 'I',
    'i': 'I',
    'Ö': 'O',
    'ö': 'O',
    'Ç': 'C',
    'ç': 'C',
  };
  final trimmed = salonName.trim();
  final first = trimmed.isEmpty ? '' : trimmed.split(RegExp(r'\s+')).first;
  final buf = StringBuffer();
  for (final ch in first.split('')) {
    final up = (trMap[ch] ?? ch).toUpperCase();
    if (RegExp(r'^[A-Z0-9]$').hasMatch(up)) buf.write(up);
    if (buf.length >= 8) break;
  }
  final slug = buf.isEmpty ? 'SALON' : buf.toString();
  final rnd = 100000 + Random().nextInt(900000);
  return 'WEBEY-$slug-$rnd';
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED: Booking Header with step progress
// ─────────────────────────────────────────────────────────────────────────────

class _BookingHeader extends StatelessWidget {
  const _BookingHeader({
    required this.step,
    required this.total,
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.timerLabel,
    this.timerWarning = false,
  });
  final int step, total;
  final String title, subtitle;
  final VoidCallback onBack;
  final String? timerLabel;
  final bool timerWarning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    Text(
                      'ADIM $step / $total',
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: List.generate(total, (i) {
                        final state = i + 1 < step
                            ? _DotState.done
                            : (i + 1 == step
                                  ? _DotState.active
                                  : _DotState.inactive);
                        return _ProgressDot(
                          state: state,
                          index: i,
                          total: total,
                        );
                      }),
                    ),
                  ],
                ),
              ),
              if (timerLabel != null) ...[
                const SizedBox(width: 12),
                _BookingTimerPill(label: timerLabel!, warning: timerWarning),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 22,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

enum _DotState { done, active, inactive }

class _ProgressDot extends StatelessWidget {
  const _ProgressDot({
    required this.state,
    required this.index,
    required this.total,
  });
  final _DotState state;
  final int index, total;

  @override
  Widget build(BuildContext context) {
    final isLast = index == total - 1;
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: state == _DotState.active ? 22 : 8,
          height: 6,
          decoration: BoxDecoration(
            color: state == _DotState.done
                ? WebeyColors.primaryGold
                : state == _DotState.active
                ? WebeyColors.darkEspresso
                : WebeyColors.borderSand,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        if (!isLast) const SizedBox(width: 4),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED: Mini Salon Card
// ─────────────────────────────────────────────────────────────────────────────

class _BookingTimerPill extends StatelessWidget {
  const _BookingTimerPill({required this.label, required this.warning});

  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? WebeyColors.errorRed : WebeyColors.primaryGold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(95)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniSalonCard extends StatelessWidget {
  const _MiniSalonCard({required this.salon});
  final Salon salon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3a261a), Color(0xFF1f1108)],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    salon.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 13,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 10,
                        color: WebeyColors.primaryGold,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${salon.rating.toStringAsFixed(1)} · ${salon.district}',
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: WebeyColors.goldLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: WebeyColors.primaryGold.withAlpha(60),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 10,
                    color: WebeyColors.primaryGold,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Garantili',
                    style: TextStyle(
                      color: WebeyColors.primaryGold,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
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

// ─────────────────────────────────────────────────────────────────────────────
// SHARED: Sticky Bottom Bar
// ─────────────────────────────────────────────────────────────────────────────

class _StickyBar extends StatelessWidget {
  const _StickyBar({
    required this.label,
    required this.value,
    required this.btnLabel,
    required this.onTap,
    this.subValue,
  });
  final String label, value, btnLabel;
  final VoidCallback onTap;
  final String? subValue;

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      TextSpan(text: value),
                      if (subValue != null)
                        TextSpan(
                          text: ' · $subValue',
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
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              decoration: BoxDecoration(
                color: WebeyColors.primaryGold,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    btnLabel,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: WebeyColors.darkEspresso,
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
// SCREEN 1 — Hizmet Seçimi
// ─────────────────────────────────────────────────────────────────────────────

const _kCats = [
  'Tümü',
  'Tırnak',
  'Saç',
  'Cilt Bakımı',
  'Makyaj',
  'Kaş & Kirpik',
];

class BookingServiceScreen extends StatefulWidget {
  const BookingServiceScreen({
    super.key,
    required this.salon,
    required this.services,
    required this.showCategoryChips,
    required this.selectedServiceId,
    required this.timerLabel,
    required this.timerWarning,
    required this.onBack,
    required this.onNext,
  });
  final Salon salon;
  final List<BookingServiceOption> services;
  final bool showCategoryChips;
  final String? selectedServiceId;
  final String timerLabel;
  final bool timerWarning;
  final VoidCallback onBack;
  final ValueChanged<String> onNext;

  @override
  State<BookingServiceScreen> createState() => _BookingServiceScreenState();
}

class _BookingServiceScreenState extends State<BookingServiceScreen> {
  late String _sel;
  String _cat = 'Tümü';

  @override
  void initState() {
    super.initState();
    _sel = widget.selectedServiceId ?? widget.services.first.key;
  }

  BookingServiceOption get _selected => widget.services.firstWhere(
    (s) => s.key == _sel,
    orElse: () => widget.services.first,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _BookingHeader(
                    step: 1,
                    total: 4,
                    title: 'Hizmet Seçin',
                    subtitle: 'Randevu almak istediğiniz hizmeti belirleyin.',
                    onBack: widget.onBack,
                    timerLabel: widget.timerLabel,
                    timerWarning: widget.timerWarning,
                  ),
                ),
                SliverToBoxAdapter(child: _MiniSalonCard(salon: widget.salon)),
                if (widget.showCategoryChips)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: SizedBox(
                        height: 34,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _kCats.length,
                          itemBuilder: (_, i) {
                            final cat = _kCats[i];
                            final isActive = _cat == cat;
                            return GestureDetector(
                              onTap: () => setState(() => _cat = cat),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
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
                                child: Center(
                                  child: Text(
                                    cat,
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
                    ),
                  ),
                // Services
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  sliver: widget.services.isEmpty
                      ? SliverToBoxAdapter(
                          child: Text(
                            'Hizmet bilgisi yakında.',
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 12.5,
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => _ServiceCard(
                              service: widget.services[i],
                              isSelected: _sel == widget.services[i].key,
                              onTap: () =>
                                  setState(() => _sel = widget.services[i].key),
                            ),
                            childCount: widget.services.length,
                          ),
                        ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
            ),
          ),
          _StickyBar(
            label: 'Seçilen Hizmet',
            value: '${_selected.price.toInt()} TL',
            subValue: _selected.durationLabel,
            btnLabel: _selected.isBookable ? 'Devam Et' : 'Yakında',
            onTap: _selected.isBookable ? () => widget.onNext(_sel) : () {},
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.isSelected,
    required this.onTap,
  });
  final BookingServiceOption service;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? WebeyColors.goldLight : WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? WebeyColors.primaryGold
                : WebeyColors.borderSand,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  if (service.description.isNotEmpty)
                    Text(
                      service.description,
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 12,
                      ),
                    ),
                  if (!service.isBookable) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Bu hizmet için randevu oluşturma yakında aktif.',
                      style: TextStyle(
                        color: WebeyColors.warning,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 11,
                        color: WebeyColors.mutedTaupe,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        service.durationLabel,
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 11.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${service.price.toInt()} TL',
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Radio
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? WebeyColors.primaryGold
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? WebeyColors.primaryGold
                      : WebeyColors.borderSand,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 13,
                      color: WebeyColors.darkEspresso,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 2 — Uzman Seçimi
// ─────────────────────────────────────────────────────────────────────────────

String _bookingDateLabel(DateTime? date, {bool compact = false}) {
  final value = date ?? DateTime.now();
  const days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
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
  final month = months[value.month - 1];
  final day = days[value.weekday - 1];
  return compact ? '${value.day} $month $day' : '${value.day} $month $day';
}

class BookingStaffScreen extends StatefulWidget {
  const BookingStaffScreen({
    super.key,
    required this.staff,
    required this.selectedStaffId,
    required this.timerLabel,
    required this.timerWarning,
    required this.onBack,
    required this.onNext,
  });
  final List<BookingStaffOption> staff;
  final String? selectedStaffId;
  final String timerLabel;
  final bool timerWarning;
  final VoidCallback onBack;
  final ValueChanged<String> onNext;

  @override
  State<BookingStaffScreen> createState() => _BookingStaffScreenState();
}

class _BookingStaffScreenState extends State<BookingStaffScreen> {
  late String _sel;

  @override
  void initState() {
    super.initState();
    _sel = widget.selectedStaffId ?? widget.staff.first.key;
  }

  BookingStaffOption get _selected => widget.staff.firstWhere(
    (s) => s.key == _sel,
    orElse: () => widget.staff.first,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _BookingHeader(
                    step: 2,
                    total: 4,
                    title: 'Uzman Seçin',
                    subtitle:
                        'İsterseniz randevunuzu belirli bir uzmanla oluşturabilirsiniz.',
                    onBack: widget.onBack,
                    timerLabel: widget.timerLabel,
                    timerWarning: widget.timerWarning,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _StaffCard(
                        staff: widget.staff[i],
                        isSelected: _sel == widget.staff[i].key,
                        onTap: () => setState(() => _sel = widget.staff[i].key),
                      ),
                      childCount: widget.staff.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
            ),
          ),
          _StickyBar(
            label: 'Seçilen Uzman',
            value: _selected.name,
            subValue: _selected.isAny ? 'Otomatik atama' : _selected.role,
            btnLabel: 'Devam Et',
            onTap: () => widget.onNext(_sel),
          ),
        ],
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.staff,
    required this.isSelected,
    required this.onTap,
  });
  final BookingStaffOption staff;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? WebeyColors.goldLight : WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? WebeyColors.primaryGold
                : WebeyColors.borderSand,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar / Any icon
            if (staff.isAny)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: WebeyColors.warmCream,
                  border: Border.all(color: WebeyColors.borderSand),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  size: 20,
                  color: WebeyColors.mutedTaupe,
                ),
              )
            else
              Stack(
                children: [
                  _BookingStaffAvatar(staff: staff),
                  if (staff.isOnline)
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: WebeyColors.successGreen,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              staff.name,
                              style: const TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              staff.role,
                              style: TextStyle(
                                color: WebeyColors.mutedTaupe,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!staff.isAny && staff.rating != null)
                        Row(
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 11,
                              color: WebeyColors.primaryGold,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${staff.rating}',
                              style: const TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (staff.count != null)
                              Text(
                                ' · ${staff.count} rdv',
                                style: TextStyle(
                                  color: WebeyColors.mutedTaupe,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                  if (!staff.isAny && staff.chips.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: staff.chips
                          .map(
                            (c) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: WebeyColors.warmCream,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: WebeyColors.borderSand,
                                ),
                              ),
                              child: Text(
                                c,
                                style: TextStyle(
                                  color: WebeyColors.mutedTaupe,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (!staff.isAny &&
                      staff.availability != null &&
                      staff.availability!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: WebeyColors.successGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            staff.availability!,
                            style: TextStyle(
                              color: WebeyColors.successGreen,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${staff.name} — profil detayı'),
                              ),
                            );
                          },
                          child: Row(
                            children: [
                              Text(
                                'Profili Gör',
                                style: TextStyle(
                                  color: WebeyColors.primaryGold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Icon(
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
            const SizedBox(width: 8),
            // Radio
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? WebeyColors.primaryGold
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? WebeyColors.primaryGold
                      : WebeyColors.borderSand,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 13,
                      color: WebeyColors.darkEspresso,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 3 — Tarih & Saat
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// AKILLI ÖNERİLER — gerçek availability slotlarından üretilen öneri modeli
// ─────────────────────────────────────────────────────────────────────────────

enum BookingSuggestionKind { earliest, calmer, favoriteStaff, alternativeDay }

class BookingSmartSuggestion {
  const BookingSmartSuggestion({
    required this.kind,
    required this.label,
    required this.titleText,
    required this.date,
    required this.time,
    required this.startsAt,
  });

  final BookingSuggestionKind kind;
  final String label; // EN YAKIN, DAHA SAKİN SAAT, ...
  final String titleText; // Bugün / Yarın / 8 Haz
  final DateTime date; // normalize edilmiş gün (yıl,ay,gün)
  final String time; // HH:MM
  final String startsAt; // "YYYY-MM-DD HH:MM:SS"

  String get dedupeKey => '${date.year}-${date.month}-${date.day} $time';
}

class _BookingStaffAvatar extends StatelessWidget {
  const _BookingStaffAvatar({required this.staff});

  final BookingStaffOption staff;

  @override
  Widget build(BuildContext context) {
    final rawUrl = staff.profilePhotoUrl?.trim() ?? '';
    final version = staff.profilePhotoVersion?.trim() ?? '';
    final url = rawUrl.isEmpty || version.isEmpty
        ? rawUrl
        : '$rawUrl${rawUrl.contains('?') ? '&' : '?'}v=$version';
    return ClipOval(
      child: SizedBox(
        width: 44,
        height: 44,
        child: url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _BookingStaffInitials(staff: staff),
              )
            : _BookingStaffInitials(staff: staff),
      ),
    );
  }
}

class _BookingStaffInitials extends StatelessWidget {
  const _BookingStaffInitials({required this.staff});

  final BookingStaffOption staff;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [staff.colorA, staff.colorB],
        ),
      ),
      child: Center(
        child: Text(
          staff.initials,
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

class BookingDateTimeScreen extends StatefulWidget {
  const BookingDateTimeScreen({
    super.key,
    required this.selectedDate,
    required this.selectedTime,
    required this.staffName,
    required this.durationLabel,
    required this.slots,
    required this.loadingSlots,
    this.slotsError,
    required this.locking,
    required this.suggestions,
    required this.loadingSuggestions,
    required this.timerLabel,
    required this.timerWarning,
    required this.onSuggestionTap,
    required this.onBack,
    required this.onDateChanged,
    required this.onSlotSelected,
    required this.onNext,
  });
  final DateTime? selectedDate;
  final String? selectedTime;
  final String staffName;
  final String durationLabel;
  final List<BookingAvailabilitySlot> slots;
  final bool loadingSlots;
  final String? slotsError;
  final bool locking;
  final List<BookingSmartSuggestion> suggestions;
  final bool loadingSuggestions;
  final String timerLabel;
  final bool timerWarning;
  final ValueChanged<BookingSmartSuggestion> onSuggestionTap;
  final VoidCallback onBack;
  final ValueChanged<DateTime> onDateChanged;
  final Future<bool> Function(BookingAvailabilitySlot slot) onSlotSelected;
  final VoidCallback onNext;

  @override
  State<BookingDateTimeScreen> createState() => _BookingDateTimeScreenState();
}

class _BookingDateTimeScreenState extends State<BookingDateTimeScreen> {
  late int _dayIdx;
  late String? _time;

  static const _monthNames = [
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

  @override
  void initState() {
    super.initState();
    final base = widget.selectedDate ?? DateTime.now();
    final today = DateTime.now();
    _dayIdx = base
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    if (_dayIdx < 0) _dayIdx = 0;
    if (_dayIdx > 6) _dayIdx = 0;
    _time = widget.selectedTime;
  }

  @override
  void didUpdateWidget(BookingDateTimeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTime != widget.selectedTime) {
      _time = widget.selectedTime;
    }
  }

  DateTime get _selectedDate {
    final today = DateTime.now();
    return DateTime(
      today.year,
      today.month,
      today.day,
    ).add(Duration(days: _dayIdx));
  }

  String _dayLabel(int offset) {
    if (offset == 0) return 'BUG';
    if (offset == 1) return 'YAR';
    const days = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return days[DateTime.now().add(Duration(days: offset)).weekday]
        .toUpperCase();
  }

  String _dayNum(int offset) {
    return DateTime.now().add(Duration(days: offset)).day.toString();
  }

  String get _monthTitle {
    final d = _selectedDate;
    return '${_monthNames[d.month - 1]} ${d.year}';
  }

  String get _monthShort {
    return _monthNames[_selectedDate.month - 1].toUpperCase();
  }

  List<BookingAvailabilitySlot> get _morningSlots => widget.slots.where((s) {
    final h = int.tryParse(s.time.split(':').first) ?? 0;
    return h < 12;
  }).toList();

  List<BookingAvailabilitySlot> get _afternoonSlots => widget.slots.where((s) {
    final h = int.tryParse(s.time.split(':').first) ?? 0;
    return h >= 12 && h < 17;
  }).toList();

  List<BookingAvailabilitySlot> get _eveningSlots => widget.slots.where((s) {
    final h = int.tryParse(s.time.split(':').first) ?? 0;
    return h >= 17;
  }).toList();

  Future<void> _selectSlot(BookingAvailabilitySlot slot) async {
    if (!slot.available || widget.locking) return;
    final ok = await widget.onSlotSelected(slot);
    if (ok && mounted) setState(() => _time = slot.time);
  }

  // Akıllı öneri kartları — yalnızca gerçek available slotlardan üretilir.
  Widget _buildSuggestions() {
    if (widget.loadingSuggestions) {
      return const SizedBox(
        height: 74,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: WebeyColors.primaryGold,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }
    if (widget.suggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Yakındaki günlerde uygun saat bulamadık.',
          style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12.5),
        ),
      );
    }
    final selectedDay = _selectedDate;
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final s = widget.suggestions[i];
          final isSelected =
              _time == s.time &&
              s.date.year == selectedDay.year &&
              s.date.month == selectedDay.month &&
              s.date.day == selectedDay.day;
          return _RecoCard(
            label: s.label,
            title: s.titleText,
            time: s.time,
            isDark: isSelected || i == 0,
            onTap: () => widget.onSuggestionTap(s),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateSubtitle = widget.slotsError != null
        ? 'Saatler yüklenemedi'
        : '${_dayIdx == 0 ? 'Bugün' : _dayLabel(_dayIdx)} · ${widget.staffName}';

    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _BookingHeader(
                    step: 3,
                    total: 4,
                    title: 'Tarih ve Saat Seçin',
                    subtitle: 'Size en uygun zamanı belirleyin.',
                    onBack: widget.onBack,
                    timerLabel: widget.timerLabel,
                    timerWarning: widget.timerWarning,
                  ),
                ),
                // Smart reco cards
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SmallSectionLabel(
                          eyebrow: 'AKILLI ÖNERİLER',
                          title: 'Bizden öneriler',
                        ),
                        const SizedBox(height: 10),
                        _buildSuggestions(),
                      ],
                    ),
                  ),
                ),
                // Date selector
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _SmallSectionLabel(
                            eyebrow: 'TARİH',
                            title: _monthTitle,
                          ),
                        ),
                        Text(
                          'Takvim',
                          style: TextStyle(
                            color: WebeyColors.primaryGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SizedBox(
                      height: 72,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: 7,
                        itemBuilder: (_, i) {
                          final isActive = _dayIdx == i;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _dayIdx = i;
                                _time = null;
                              });
                              final today = DateTime.now();
                              widget.onDateChanged(
                                DateTime(
                                  today.year,
                                  today.month,
                                  today.day,
                                ).add(Duration(days: i)),
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 56,
                              height: 72,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? WebeyColors.darkEspresso
                                    : WebeyColors.softWhite,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isActive
                                      ? WebeyColors.darkEspresso
                                      : WebeyColors.borderSand,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _dayLabel(i),
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.white.withAlpha(180)
                                          : WebeyColors.mutedTaupe,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _dayNum(i),
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.white
                                          : WebeyColors.darkEspresso,
                                      fontSize: 18,
                                      fontFamily: 'Georgia',
                                      fontWeight: FontWeight.w600,
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _monthShort,
                                    style: TextStyle(
                                      color: isActive
                                          ? WebeyColors.primaryGold
                                          : WebeyColors.mutedTaupe,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? WebeyColors.primaryGold
                                          : WebeyColors.successGreen.withAlpha(
                                              120,
                                            ),
                                      shape: BoxShape.circle,
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
                // Time slots
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: _SmallSectionLabel(
                      eyebrow: 'UYGUN SAATLER',
                      title: dateSubtitle,
                    ),
                  ),
                ),
                if (widget.loadingSlots)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: WebeyColors.primaryGold,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  )
                else if (widget.slotsError != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Text(
                        widget.slotsError!,
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  )
                else if (widget.slots.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Text(
                        'Bu tarih için müsait saat bulunamadı.',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_morningSlots.isNotEmpty) ...[
                            _TimePeriod(label: 'Sabah'),
                            const SizedBox(height: 8),
                            _ApiTimeGrid(
                              slots: _morningSlots,
                              selectedTime: _time,
                              locking: widget.locking,
                              onSelect: _selectSlot,
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_afternoonSlots.isNotEmpty) ...[
                            _TimePeriod(label: 'Öğleden Sonra'),
                            const SizedBox(height: 8),
                            _ApiTimeGrid(
                              slots: _afternoonSlots,
                              selectedTime: _time,
                              locking: widget.locking,
                              onSelect: _selectSlot,
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_eveningSlots.isNotEmpty) ...[
                            _TimePeriod(label: 'Akşam'),
                            const SizedBox(height: 8),
                            _ApiTimeGrid(
                              slots: _eveningSlots,
                              selectedTime: _time,
                              locking: widget.locking,
                              onSelect: _selectSlot,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                // Waitlist
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: WebeyColors.warmCream,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: WebeyColors.goldLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.hourglass_top_rounded,
                              size: 15,
                              color: WebeyColors.primaryGold,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Uygun saat bulamadınız mı?',
                                  style: TextStyle(
                                    color: WebeyColors.darkEspresso,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Uygunluk açılırsa size haber verelim.',
                                  style: TextStyle(
                                    color: WebeyColors.mutedTaupe,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Bekleme listesine eklendiniz'),
                                ),
                              );
                            },
                            child: Text(
                              'Katıl ›',
                              style: TextStyle(
                                color: WebeyColors.primaryGold,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
            ),
          ),
          _StickyBar(
            label: 'Seçilen Zaman',
            value: _time == null
                ? 'Saat seçin'
                : '${_dayIdx == 0
                      ? 'Bugün'
                      : _dayIdx == 1
                      ? 'Yarın'
                      : '${_dayNum(_dayIdx)} ${_monthNames[_selectedDate.month - 1]}'} · $_time',
            subValue: widget.durationLabel,
            btnLabel: widget.locking ? 'Kilitleniyor...' : 'Devam Et',
            onTap: widget.locking ? () {} : widget.onNext,
          ),
        ],
      ),
    );
  }
}

class _RecoCard extends StatelessWidget {
  const _RecoCard({
    required this.label,
    required this.title,
    required this.time,
    required this.isDark,
    required this.onTap,
  });
  final String label, title, time;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? WebeyColors.darkEspresso : WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isDark ? WebeyColors.darkEspresso : WebeyColors.borderSand,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 9,
                  color: isDark
                      ? WebeyColors.primaryGold
                      : WebeyColors.mutedTaupe,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isDark
                        ? WebeyColors.primaryGold
                        : WebeyColors.mutedTaupe,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                style: TextStyle(
                  color: isDark ? Colors.white : WebeyColors.darkEspresso,
                  fontSize: 14,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w600,
                ),
                children: [
                  TextSpan(text: title),
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: time,
                    style: const TextStyle(fontStyle: FontStyle.italic),
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

class _TimePeriod extends StatelessWidget {
  const _TimePeriod({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: WebeyColors.mutedTaupe,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: WebeyColors.borderSand)),
      ],
    );
  }
}

class _ApiTimeGrid extends StatelessWidget {
  const _ApiTimeGrid({
    required this.slots,
    required this.selectedTime,
    required this.locking,
    required this.onSelect,
  });
  final List<BookingAvailabilitySlot> slots;
  final String? selectedTime;
  final bool locking;
  final Future<void> Function(BookingAvailabilitySlot slot) onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: slots.map((slot) {
        final isDisabled = !slot.available;
        final isSelected = selectedTime == slot.time && !isDisabled;
        return GestureDetector(
          onTap: isDisabled || locking ? null : () => onSelect(slot),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 74,
            height: 38,
            decoration: BoxDecoration(
              color: isSelected
                  ? WebeyColors.primaryGold
                  : isDisabled
                  ? WebeyColors.warmCream.withAlpha(120)
                  : WebeyColors.softWhite,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: isSelected
                    ? WebeyColors.primaryGold
                    : isDisabled
                    ? WebeyColors.borderSand.withAlpha(80)
                    : WebeyColors.borderSand,
              ),
            ),
            child: Center(
              child: Text(
                slot.time,
                style: TextStyle(
                  color: isSelected
                      ? WebeyColors.darkEspresso
                      : isDisabled
                      ? WebeyColors.mutedTaupe.withAlpha(100)
                      : WebeyColors.darkEspresso,
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SmallSectionLabel extends StatelessWidget {
  const _SmallSectionLabel({required this.eyebrow, required this.title});
  final String eyebrow, title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 12, height: 1, color: WebeyColors.primaryGold),
            const SizedBox(width: 5),
            Text(
              eyebrow,
              style: TextStyle(
                color: WebeyColors.primaryGold,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          title,
          style: const TextStyle(
            color: WebeyColors.darkEspresso,
            fontSize: 15,
            fontFamily: 'Georgia',
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 4 — Randevu Onay
// ─────────────────────────────────────────────────────────────────────────────

class BookingConfirmScreen extends StatefulWidget {
  const BookingConfirmScreen({
    super.key,
    required this.salon,
    required this.booking,
    required this.catalog,
    required this.canConfirm,
    required this.onBack,
    required this.onConfirm,
    required this.onNoteChanged,
    this.onAbort,
    this.confirming = false,
    this.confirmError,
    this.depositRatePct,
    this.depositPreview,
    this.depositReferenceCode,
    this.campaign,
    this.campaignReason,
    required this.timerLabel,
    required this.timerWarning,
  });
  final Salon salon;
  final BookingState booking;
  final BookingCatalog catalog;
  final bool canConfirm;
  final VoidCallback onBack;

  /// "Vazgeç" — randevu henüz oluşmadığı için akıştan çıkar.
  final VoidCallback? onAbort;
  final Future<void> Function() onConfirm;
  final ValueChanged<String> onNoteChanged;
  final bool confirming;
  final String? confirmError;

  /// Sunucunun hesapladığı kampanya teklifi (varsa) — özet indirim satırı için.
  final SalonCampaign? campaign;

  /// Slot kampanyaya uymuyorsa açıklama (varsa).
  final String? campaignReason;

  /// Salonun gerçek kapora oranı (%). null/0 ise kapora yok kabul edilir.
  final int? depositRatePct;

  /// Kapora gerekiyorsa salonun GERÇEK IBAN bilgileri (payment-settings →
  /// salon-detail zincirinden). Placeholder/fake veri yok.
  final DepositInfo? depositPreview;

  /// Banka açıklama kodu (aday) — müşteri havale açıklamasına bunu yazar.
  final String? depositReferenceCode;
  final String timerLabel;
  final bool timerWarning;

  @override
  State<BookingConfirmScreen> createState() => _BookingConfirmScreenState();
}

class _BookingConfirmScreenState extends State<BookingConfirmScreen> {
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _hasDeposit =>
      (widget.depositPreview?.required ?? false) ||
      (widget.depositRatePct ?? 0) > 0;

  bool get _hasIban => widget.depositPreview?.hasIban ?? false;

  void _copyIban(BuildContext context) {
    final iban = widget.depositPreview?.iban ?? '';
    if (iban.isEmpty) return;
    Clipboard.setData(ClipboardData(text: iban));
    WebeyToast.success(context, 'IBAN kopyalandı');
  }

  void _copyReferenceCode(BuildContext context) {
    final code = widget.depositReferenceCode ?? '';
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    WebeyToast.success(context, 'Açıklama kodu kopyalandı');
  }

  @override
  Widget build(BuildContext context) {
    final service =
        widget.catalog.serviceByKey(widget.booking.serviceId) ??
        widget.catalog.defaultService;
    final staffName =
        widget.catalog.staffByKey(widget.booking.staffId)?.name ?? 'Uzman';
    final dateLabel = _bookingDateLabel(widget.booking.selectedDate);
    // Kampanya varsa kapora/kalan indirimli (final) fiyat üzerinden gösterilir;
    // backend book sırasında aynı mantıkla otoriter hesaplar.
    final campaign = widget.campaign;
    final originalPrice = service.price;
    final effectivePrice = campaign?.finalPrice ?? originalPrice;
    // Kapora tutarı salonun GERÇEK oranından hesaplanır (hardcoded değil).
    final depositRate = widget.depositRatePct ?? 0;
    final hasDeposit = _hasDeposit;
    final depositAmount = depositRate > 0
        ? (effectivePrice * depositRate / 100).round()
        : 0;
    final remainingAmount = (effectivePrice.toInt() - depositAmount).clamp(
      0,
      1 << 31,
    );
    final ibanBlocked = hasDeposit && !_hasIban;
    final canConfirm = widget.canConfirm && !widget.confirming && !ibanBlocked;

    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _BookingHeader(
                    step: 4,
                    total: 4,
                    title: hasDeposit
                        ? 'Kapora Ödeme Bilgileri'
                        : 'Randevunuzu Onaylayın',
                    subtitle: hasDeposit
                        ? 'Kapora gönderildikten sonra randevunuz işletmeye iletilir.'
                        : 'Bilgilerinizi kontrol edin ve randevunuzu oluşturun.',
                    onBack: widget.onBack,
                    timerLabel: widget.timerLabel,
                    timerWarning: widget.timerWarning,
                  ),
                ),
                // ── Kampanya indirim özeti / uyumsuzluk uyarısı ───────────
                if (campaign != null)
                  SliverToBoxAdapter(
                    child: _CampaignSummaryCard(
                      originalPrice: originalPrice,
                      finalPrice: effectivePrice,
                      badge: campaign.shortLabel,
                      summary: campaign.summary,
                    ),
                  )
                else if (widget.campaignReason != null)
                  SliverToBoxAdapter(
                    child: _CampaignReasonBanner(
                      reason: widget.campaignReason!,
                    ),
                  ),
                if (hasDeposit && !ibanBlocked)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Text(
                        'Randevunuzun işletmeye iletilmesi için kapora tutarını '
                        'aşağıdaki IBAN’a gönderin. Ödemeyi yaptıktan sonra '
                        '“IBAN’a parayı attım” butonuna basın.',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                // A) Randevu özeti kartı
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: WebeyColors.softWhite,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'RANDEVU ÖZETİ',
                                  style: TextStyle(
                                    color: WebeyColors.primaryGold,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF3a261a),
                                            Color(0xFF1f1108),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.salon.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: WebeyColors.darkEspresso,
                                              fontSize: 14,
                                              fontFamily: 'Georgia',
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.location_on_outlined,
                                                size: 10,
                                                color: WebeyColors.mutedTaupe,
                                              ),
                                              const SizedBox(width: 3),
                                              Expanded(
                                                child: Text(
                                                  '${widget.salon.neighborhood}, ${widget.salon.district}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color:
                                                        WebeyColors.mutedTaupe,
                                                    fontSize: 11.5,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Divider(height: 1, color: WebeyColors.borderSand),
                          _SummaryRow(
                            icon: Icons.spa_outlined,
                            label: 'Hizmet',
                            value: service.name,
                          ),
                          _SummaryRow(
                            icon: Icons.person_outline_rounded,
                            label: 'Uzman',
                            value: staffName,
                          ),
                          _SummaryRow(
                            icon: Icons.calendar_today_outlined,
                            label: 'Tarih ve Saat',
                            value:
                                '$dateLabel · ${widget.booking.selectedTime ?? '—'}',
                            subValue: service.durationLabel.isNotEmpty
                                ? service.durationLabel
                                : '${service.durationMinutes} dk',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!widget.canConfirm)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: WebeyColors.goldLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: WebeyColors.borderSand),
                        ),
                        child: Text(
                          'Bu hizmet için randevu oluşturma yakında aktif.',
                          style: TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                // B) Ödeme özeti kartı (kapora varsa)
                if (hasDeposit)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: WebeyColors.warmCream,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: WebeyColors.borderSand),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Ödeme Özeti',
                              style: TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 14,
                                fontFamily: 'Georgia',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _DepositRow(
                              label: campaign != null
                                  ? 'Kampanyalı toplam'
                                  : 'Hizmet fiyatı',
                              value: '${effectivePrice.toInt()} TL',
                              isTotal: false,
                            ),
                            const SizedBox(height: 6),
                            _DepositRow(
                              label: 'Kapora oranı',
                              value: depositRate > 0 ? '%$depositRate' : '—',
                              isTotal: false,
                            ),
                            const SizedBox(height: 6),
                            _DepositRow(
                              label: 'Kapora tutarı',
                              value: '$depositAmount TL',
                              isGold: true,
                              isTotal: false,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Divider(
                                height: 1,
                                color: WebeyColors.borderSand,
                              ),
                            ),
                            _DepositRow(
                              label: 'Salonda ödenecek',
                              value: '$remainingAmount TL',
                              isTotal: true,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Webey ödeme tahsil etmez.',
                              style: TextStyle(
                                color: WebeyColors.mutedTaupe,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // C) IBAN bilgileri kartı / IBAN eksik kartı
                if (hasDeposit)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: ibanBlocked
                          ? _MissingIbanCard(onBack: widget.onBack)
                          : _IbanPaymentCard(
                              deposit: widget.depositPreview!,
                              amount: depositAmount,
                              referenceCode: widget.depositReferenceCode,
                              onCopy: () => _copyIban(context),
                              onCopyCode: () => _copyReferenceCode(context),
                            ),
                    ),
                  ),
                // D) Bilgi kutusu
                if (hasDeposit && !ibanBlocked)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: WebeyColors.goldLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 13,
                              color: WebeyColors.primaryGold,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                'Kapora ödemesi doğrudan salonun banka hesabına '
                                'yapılır. Webey ödeme tahsil etmez. İşletme '
                                'ödemeyi onayladıktan sonra randevunuz onaylanır.',
                                style: TextStyle(
                                  color: WebeyColors.mutedTaupe,
                                  fontSize: 11.5,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Not alanı
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: WebeyColors.softWhite,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 15,
                            color: WebeyColors.mutedTaupe,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _noteCtrl,
                              onChanged: widget.onNoteChanged,
                              style: const TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Salona not ekle (alerji, hassasiyet, tasarım ricası)',
                                hintStyle: TextStyle(
                                  color: WebeyColors.mutedTaupe,
                                  fontSize: 12.5,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.confirmError != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Text(
                        widget.confirmError!,
                        style: TextStyle(
                          color: WebeyColors.errorRed,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
            ),
          ),
          // E) Aksiyon alanı — sticky bottom, gesture alanı ile çakışmaz.
          Container(
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: canConfirm ? widget.onConfirm : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      color: canConfirm
                          ? WebeyColors.primaryGold
                          : WebeyColors.primaryGold.withAlpha(120),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.confirming)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: WebeyColors.darkEspresso,
                            ),
                          )
                        else
                          Icon(
                            hasDeposit
                                ? Icons.send_rounded
                                : Icons.event_available_rounded,
                            size: 16,
                            color: WebeyColors.darkEspresso,
                          ),
                        const SizedBox(width: 8),
                        Text(
                          widget.confirming
                              ? (hasDeposit
                                    ? 'Randevunuz iletiliyor...'
                                    : 'Randevu oluşturuluyor...')
                              : !widget.canConfirm
                              ? 'Randevu Yakında Aktif'
                              : ibanBlocked
                              ? 'Kapora bilgileri eksik'
                              : hasDeposit
                              ? 'IBAN’a parayı attım'
                              : 'Randevuyu Oluştur',
                          style: TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (hasDeposit) ...[
                  const SizedBox(height: 8),
                  // Randevu henüz oluşmadı → "Vazgeç" (kırmızı outline).
                  GestureDetector(
                    onTap: widget.confirming
                        ? null
                        : (widget.onAbort ?? widget.onBack),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: WebeyColors.errorRed.withAlpha(120),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'Vazgeç',
                          style: TextStyle(
                            color: WebeyColors.errorRed,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    ibanBlocked
                        ? 'Salon kapora bilgilerini ekleyene kadar randevu iletilemez.'
                        : 'Randevunuz ancak “IBAN’a parayı attım” dedikten sonra işletmeye iletilir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 11.5,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 7),
                  Text(
                    'Ödeme salonda yapılır.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// C) IBAN bilgileri kartı — büyük, net, premium.
class _IbanPaymentCard extends StatelessWidget {
  const _IbanPaymentCard({
    required this.deposit,
    required this.amount,
    required this.onCopy,
    this.referenceCode,
    this.onCopyCode,
  });

  final DepositInfo deposit;
  final int amount;
  final VoidCallback onCopy;

  /// Banka açıklama kodu — müşteri havale açıklamasına bunu yazar.
  final String? referenceCode;
  final VoidCallback? onCopyCode;

  @override
  Widget build(BuildContext context) {
    final iban = deposit.ibanFormatted.isNotEmpty
        ? deposit.ibanFormatted
        : deposit.iban;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.primaryGold.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_rounded,
                size: 17,
                color: WebeyColors.primaryGold,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'IBAN Bilgileri',
                  style: TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 14.5,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Gönderilecek tutar: $amount TL',
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          // IBAN — monospace, okunabilir, taşarsa düzgün sarar.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: WebeyColors.warmCream,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: WebeyColors.borderSand),
            ),
            child: Text(
              iban,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 14.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                height: 1.4,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (deposit.accountHolder != null)
            _ibanRow('Hesap sahibi', deposit.accountHolder!),
          if (deposit.bankName != null) _ibanRow('Banka', deposit.bankName!),
          if (deposit.instructions != null)
            _ibanRow('Not', deposit.instructions!),
          // Banka açıklama kodu — havale açıklamasına yazılacak.
          if (referenceCode != null && referenceCode!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: WebeyColors.goldLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: WebeyColors.primaryGold.withAlpha(70),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Açıklama kısmına bunu yazın',
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          referenceCode!,
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 14.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      if (onCopyCode != null)
                        GestureDetector(
                          onTap: onCopyCode,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.copy_rounded,
                              size: 17,
                              color: WebeyColors.primaryGold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: onCopy,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: WebeyColors.darkEspresso,
                      side: const BorderSide(color: WebeyColors.borderSand),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text(
                      'IBAN’ı Kopyala',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              if (referenceCode != null &&
                  referenceCode!.isNotEmpty &&
                  onCopyCode != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: onCopyCode,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: WebeyColors.darkEspresso,
                        side: const BorderSide(color: WebeyColors.borderSand),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.tag_rounded, size: 15),
                      label: const Text(
                        'Kodu Kopyala',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _ibanRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
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
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Salon IBAN bilgisi eksik — booking bloklanır.
class _MissingIbanCard extends StatelessWidget {
  const _MissingIbanCard({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.errorRed.withAlpha(12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.errorRed.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: WebeyColors.errorRed,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Kapora bilgileri eksik',
                  style: TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 14.5,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bu salon kapora ödeme bilgilerini henüz eklememiş. Lütfen daha '
            'sonra tekrar deneyin veya farklı bir saat/salon seçin.',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton(
              onPressed: onBack,
              style: OutlinedButton.styleFrom(
                foregroundColor: WebeyColors.darkEspresso,
                side: const BorderSide(color: WebeyColors.borderSand),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              child: const Text(
                'Geri dön',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    this.subValue,
  });
  final IconData icon;
  final String label, value;
  final String? subValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: WebeyColors.mutedTaupe),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 10.5),
              ),
              const SizedBox(height: 2),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  children: [
                    TextSpan(text: value),
                    if (subValue != null)
                      TextSpan(
                        text: ' · $subValue',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
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
      ),
    );
  }
}

class _DepositRow extends StatelessWidget {
  const _DepositRow({
    required this.label,
    required this.value,
    required this.isTotal,
    this.isGold = false,
  });
  final String label, value;
  final bool isTotal, isGold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: WebeyColors.mutedTaupe,
            fontSize: isTotal ? 13 : 12.5,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: isGold ? WebeyColors.primaryGold : WebeyColors.darkEspresso,
            fontSize: isTotal ? 16 : 13,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 5 — Başarılı
// ─────────────────────────────────────────────────────────────────────────────

class BookingSuccessScreen extends StatelessWidget {
  const BookingSuccessScreen({
    super.key,
    required this.salon,
    required this.booking,
    required this.catalog,
    required this.depositPaid,
    required this.depositAmount,
    this.deposit,
    this.campaign,
    this.finalAmount,
    this.remainingAmount,
    this.onMarkDepositSent,
    this.markingDepositSent = false,
    this.onCancelAppointment,
    this.cancellingAppointment = false,
    this.appointmentCancelRequested = false,
    required this.onViewAppointments,
    required this.onHome,
  });
  final Salon salon;
  final BookingState booking;
  final BookingCatalog catalog;
  final bool depositPaid;
  final double? depositAmount;
  final DepositInfo? deposit;

  /// Uygulanan kampanya (varsa) — indirim satırı için.
  final SalonCampaign? campaign;

  /// Backend'den gelen indirim sonrası final tutar (varsa).
  final double? finalAmount;

  /// Backend'den gelen salonda kalan (varsa) — tercih edilir.
  final double? remainingAmount;
  final VoidCallback? onMarkDepositSent;
  final bool markingDepositSent;
  final VoidCallback? onCancelAppointment;
  final bool cancellingAppointment;
  final bool appointmentCancelRequested;
  final VoidCallback onViewAppointments, onHome;

  void _copyCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    WebeyToast.success(context, 'Açıklama kodu kopyalandı');
  }

  @override
  Widget build(BuildContext context) {
    final service =
        catalog.serviceByKey(booking.serviceId) ?? catalog.defaultService;
    final staffName = catalog.staffByKey(booking.staffId)?.name ?? 'Uzman';
    final dateLabel = _bookingDateLabel(booking.selectedDate, compact: true);
    // Gerçek kapora tutarı backend'den (book.php) gelir; hardcoded oran yok.
    final depositAmountInt =
        depositAmount?.toInt() ?? deposit?.amount?.toInt() ?? 0;
    // Salonda kalan: indirim sonrası FINAL tutar üzerinden. Önce backend'in
    // otoriter remaining_amount'ı; yoksa max(0, final - kapora) fallback.
    final originalPrice = service.price;
    final effectivePrice = finalAmount ?? campaign?.finalPrice ?? originalPrice;
    final remainingAtSalon =
        (remainingAmount ?? (effectivePrice - depositAmountInt))
            .clamp(0, double.infinity)
            .toInt();
    final isMarkedSent = deposit?.isMarkedSent ?? false;
    final hasPendingDeposit =
        deposit?.required == true && deposit?.status != 'paid';
    final refCode = deposit?.referenceCode ?? '';
    final successBadge = isMarkedSent
        ? 'ÖDEME KONTROL BEKLİYOR'
        : hasPendingDeposit
        ? 'KAPORA BEKLENİYOR'
        : 'RANDEVU OLUŞTURULDU';
    final titleEmphasis = (isMarkedSent || hasPendingDeposit)
        ? 'işletmeye iletildi.'
        : 'oluşturuldu.';
    final subtitle = isMarkedSent
        ? 'Kapora ödemenizi gönderdiğinizi bildirdiniz. İşletme hesabını '
              'kontrol edip ödemeyi onayladıktan sonra randevunuz kesinleşecektir.'
        : hasPendingDeposit
        ? 'Kapora talimatlarını takip ederek randevunuzu güvenceye alabilirsiniz.'
        : (depositPaid
              ? 'Kapora ödemeniz alındı. Kalan ödeme salonda yapılacaktır.'
              : 'İşletme onayladığında bilgilendirileceksiniz.');

    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A) Başarı ikonu, rozet, başlık, açıklama
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFD4B574), Color(0xFF8C6F38)],
                    ),
                  ),
                  child: Icon(
                    isMarkedSent
                        ? Icons.schedule_send_rounded
                        : Icons.check_rounded,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: WebeyColors.goldLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: WebeyColors.primaryGold.withAlpha(70),
                    ),
                  ),
                  child: Text(
                    successBadge,
                    style: TextStyle(
                      color: WebeyColors.primaryGold,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 22,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                  children: [
                    const TextSpan(text: 'Randevunuz '),
                    TextSpan(
                      text: titleEmphasis,
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: WebeyColors.mutedTaupe,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              // B) Randevu Özeti Kartı
              Container(
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
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF3a261a), Color(0xFF1f1108)],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                salon.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: WebeyColors.darkEspresso,
                                  fontSize: 14,
                                  fontFamily: 'Georgia',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${service.name} · $staffName',
                                style: TextStyle(
                                  color: WebeyColors.mutedTaupe,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, color: WebeyColors.borderSand),
                    ),
                    _SuccessRow(
                      label: 'Tarih ve Saat',
                      value: '$dateLabel · ${booking.selectedTime ?? '—'}',
                    ),
                    const SizedBox(height: 7),
                    _SuccessRow(
                      label: 'Süre',
                      value: service.durationLabel.isNotEmpty
                          ? service.durationLabel
                          : '${service.durationMinutes} dk',
                    ),
                    if (campaign != null) ...[
                      const SizedBox(height: 7),
                      _SuccessRow(
                        label: 'Hizmet bedeli',
                        value: '${originalPrice.toInt()} TL',
                      ),
                      const SizedBox(height: 7),
                      _SuccessRow(
                        label: 'Kampanya indirimi',
                        value:
                            '−${(originalPrice - effectivePrice).clamp(0, originalPrice).toInt()} TL',
                        isGold: true,
                      ),
                      const SizedBox(height: 7),
                      _SuccessRow(
                        label: 'Yeni toplam',
                        value: '${effectivePrice.toInt()} TL',
                      ),
                    ],
                    if (depositPaid) ...[
                      const SizedBox(height: 7),
                      _SuccessRow(
                        label: 'Kapora ödendi',
                        value: '$depositAmountInt TL',
                        isGold: true,
                      ),
                      const SizedBox(height: 7),
                      _SuccessRow(
                        label: 'Salonda kalan',
                        value: '$remainingAtSalon TL',
                      ),
                    ],
                  ],
                ),
              ),
              // C) Ödeme Durumu Kartı
              if (hasPendingDeposit) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
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
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 16,
                            color: WebeyColors.primaryGold,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Ödeme Durumu',
                              style: TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 14,
                                fontFamily: 'Georgia',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          DepositStatusBadge(
                            status: deposit?.status ?? 'pending',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (depositAmountInt > 0)
                        _SuccessRow(
                          label: 'Kapora tutarı',
                          value: '$depositAmountInt TL',
                          isGold: true,
                        ),
                      if (refCode.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: WebeyColors.goldLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: WebeyColors.primaryGold.withAlpha(70),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Banka açıklama kodu',
                                style: TextStyle(
                                  color: WebeyColors.mutedTaupe,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      refCode,
                                      style: const TextStyle(
                                        color: WebeyColors.darkEspresso,
                                        fontSize: 14.5,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => _copyCode(context, refCode),
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Icon(
                                        Icons.copy_rounded,
                                        size: 17,
                                        color: WebeyColors.primaryGold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              // D) IBAN Bilgileri Kartı (kopyala + iptal aksiyonları kart içinde)
              if (deposit != null && deposit!.required) ...[
                const SizedBox(height: 12),
                DepositInstructionsCard(
                  deposit: deposit!,
                  onMarkSent: onMarkDepositSent,
                  marking: markingDepositSent,
                  onCancel: onCancelAppointment,
                  cancelling: cancellingAppointment,
                  actionsDisabled: appointmentCancelRequested,
                ),
              ],
              // E) Bilgi kutusu
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: WebeyColors.goldLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: WebeyColors.primaryGold.withAlpha(60),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 13,
                      color: WebeyColors.primaryGold,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        isMarkedSent
                            ? 'İşletme hesabını kontrol edip ödemeyi '
                                  'onayladığında randevunuz kesinleşir.'
                            : 'Randevu saatiniz sizin için ayrıldı.',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 12,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // F) Aksiyonlar
              GestureDetector(
                onTap: onViewAppointments,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: WebeyColors.primaryGold,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 15,
                        color: WebeyColors.darkEspresso,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Randevularımı Gör',
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
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onHome,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: const Center(
                    child: Text(
                      'Ana Sayfaya Dön',
                      style: TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SmallActionBtn(
                      icon: Icons.calendar_month_outlined,
                      label: 'Takvime Ekle',
                      onTap: () {
                        WebeyToast.info(
                          context,
                          'Takvime ekleme yakında geliyor.',
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SmallActionBtn(
                      icon: Icons.directions_outlined,
                      label: 'Yol Tarifi Al',
                      onTap: () async {
                        final parts = [
                          salon.address,
                          salon.district,
                          salon.city,
                        ].where((p) => p != null && p.isNotEmpty).join(', ');
                        final query = parts.isNotEmpty ? parts : salon.name;
                        final uri = Uri.parse(
                          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
                        );
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      },
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

class _SuccessRow extends StatelessWidget {
  const _SuccessRow({
    required this.label,
    required this.value,
    this.isGold = false,
  });
  final String label, value;
  final bool isGold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12.5),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: isGold ? WebeyColors.primaryGold : WebeyColors.darkEspresso,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SmallActionBtn extends StatelessWidget {
  const _SmallActionBtn({
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
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: WebeyColors.darkEspresso),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
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
// SCREEN 4 — Kapora Ödemesi
// ─────────────────────────────────────────────────────────────────────────────

class BookingDepositScreen extends StatelessWidget {
  const BookingDepositScreen({
    super.key,
    required this.salon,
    required this.booking,
    required this.catalog,
    required this.depositAmount,
    required this.checkoutUrl,
    required this.starting,
    required this.error,
    required this.onStartPayment,
    required this.onSkip,
  });

  final Salon salon;
  final BookingState booking;
  final BookingCatalog catalog;
  final double? depositAmount;
  final String? checkoutUrl;
  final bool starting;
  final String? error;
  final VoidCallback onStartPayment;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final amountLabel = depositAmount != null
        ? '${depositAmount!.toStringAsFixed(0)} TL'
        : '—';
    final hasUrl = checkoutUrl != null && checkoutUrl!.isNotEmpty;

    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    // Icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: WebeyColors.goldLight,
                        border: Border.all(
                          color: WebeyColors.primaryGold.withAlpha(80),
                        ),
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        size: 34,
                        color: WebeyColors.primaryGold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'KAPORA ÖDEMESİ',
                      style: TextStyle(
                        color: WebeyColors.primaryGold,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Randevunuzu tamamlamak için kapora ödemesi gerekiyor.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 16,
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Güvenli ödeme sayfasına yönlendirileceksiniz.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Amount card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: WebeyColors.softWhite,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Kapora Tutarı',
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            amountLabel,
                            style: const TextStyle(
                              color: WebeyColors.primaryGold,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasUrl) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: WebeyColors.goldLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: WebeyColors.primaryGold.withAlpha(60),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 14,
                              color: WebeyColors.primaryGold,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Ödeme tamamlandıktan sonra bu sayfaya dönün.',
                                style: TextStyle(
                                  color: WebeyColors.mutedTaupe,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: WebeyColors.errorRed.withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: WebeyColors.errorRed.withAlpha(60),
                          ),
                        ),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: WebeyColors.errorRed,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Primary CTA
                    GestureDetector(
                      onTap: starting ? null : onStartPayment,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: starting
                              ? WebeyColors.primaryGold.withAlpha(140)
                              : WebeyColors.primaryGold,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (starting)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: WebeyColors.darkEspresso,
                                ),
                              )
                            else
                              const Icon(
                                Icons.open_in_browser_rounded,
                                size: 16,
                                color: WebeyColors.darkEspresso,
                              ),
                            const SizedBox(width: 8),
                            Text(
                              hasUrl ? 'Ödeme Sayfasını Aç' : 'Ödemeye Geç',
                              style: const TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Skip CTA
                    GestureDetector(
                      onTap: onSkip,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: WebeyColors.borderSand),
                        ),
                        child: const Center(
                          child: Text(
                            'Sonra Öde',
                            style: TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 16 + MediaQuery.of(context).padding.bottom,
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

/// Onay ekranı kampanya indirim özeti: Hizmet bedeli / Kampanya indirimi / Yeni toplam.
class _CampaignSummaryCard extends StatelessWidget {
  const _CampaignSummaryCard({
    required this.originalPrice,
    required this.finalPrice,
    required this.badge,
    required this.summary,
  });

  final double originalPrice;
  final double finalPrice;
  final String badge;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final discount = (originalPrice - finalPrice).clamp(0, originalPrice);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.goldLight,
        borderRadius: BorderRadius.circular(WebeyRadius.medium),
        border: Border.all(
          color: WebeyColors.alpha(WebeyColors.primaryGold, 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_offer,
                size: 18,
                color: WebeyColors.primaryGold,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: WebeyColors.darkEspresso,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            style: const TextStyle(fontSize: 12, color: WebeyColors.mutedTaupe),
          ),
          const Divider(height: 20, color: WebeyColors.borderSand),
          _row('Hizmet bedeli', '${originalPrice.toInt()} TL'),
          const SizedBox(height: 6),
          _row('Kampanya indirimi', '−${discount.toInt()} TL', gold: true),
          const SizedBox(height: 6),
          _row('Yeni toplam', '${finalPrice.toInt()} TL', bold: true),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.verified_outlined,
                size: 13,
                color: WebeyColors.primaryGold,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Size en avantajlı kampanya uygulandı.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: WebeyColors.alpha(WebeyColors.darkEspresso, 0.7),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(
    String label,
    String value, {
    bool gold = false,
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: bold ? 15 : 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: WebeyColors.darkText,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 15 : 13,
            fontWeight: bold || gold ? FontWeight.w700 : FontWeight.w500,
            color: gold ? WebeyColors.primaryGold : WebeyColors.darkEspresso,
          ),
        ),
      ],
    );
  }
}

/// Slot kampanyaya uymuyorsa açıklayıcı sade uyarı.
class _CampaignReasonBanner extends StatelessWidget {
  const _CampaignReasonBanner({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(WebeyRadius.medium),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: WebeyColors.mutedTaupe,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reason,
              style: const TextStyle(
                fontSize: 12.5,
                color: WebeyColors.mutedTaupe,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
