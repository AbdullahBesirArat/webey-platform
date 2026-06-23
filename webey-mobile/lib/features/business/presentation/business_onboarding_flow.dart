import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/webey_colors.dart';
import '../../../shared/widgets/webey_back_handler.dart';
import '../../../shared/widgets/webey_toast.dart';
import '../../../shared/data/turkey_locations.dart';
import '../../../shared/services/api_client.dart';
import '../data/models/business_service_category.dart';
import '../data/models/business_service_item.dart';
import '../data/models/business_staff_item.dart';
import '../data/repositories/business_repository.dart';
import 'business_location_picker.dart';
import 'widgets/service_category_picker.dart';

class BusinessOnboardingFlow extends StatefulWidget {
  const BusinessOnboardingFlow({
    super.key,
    required this.onComplete,
    required this.onLogin,
    required this.onRegister,
    this.repository,
    this.hasAuthenticatedSession = true,
  });

  final VoidCallback onComplete;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final BusinessRepository? repository;
  final bool hasAuthenticatedSession;

  @override
  State<BusinessOnboardingFlow> createState() => _BusinessOnboardingFlowState();
}

enum _OnbStep { profile, services, staff, hours, deposit, done }

const _serviceDurationOptions = [15, 30, 45, 60];
const _depositRateOptions = [25, 50, 75, 100];

int _nearestServiceDuration(int value) {
  var best = _serviceDurationOptions.first;
  var bestDistance = (value - best).abs();
  for (final option in _serviceDurationOptions.skip(1)) {
    final distance = (value - option).abs();
    if (distance < bestDistance) {
      best = option;
      bestDistance = distance;
    }
  }
  return best;
}

int _normalizedDepositRate(int value) {
  return _depositRateOptions.contains(value) ? value : 25;
}

class _BusinessOnboardingFlowState extends State<BusinessOnboardingFlow> {
  late final BusinessRepository _repository =
      widget.repository ?? BusinessRepository.instance;

  _OnbStep _step = _OnbStep.profile;
  bool _completeSaving = false;

  // Profile
  final _profileFormKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _neighborhoodCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _buildingNoCtrl = TextEditingController();
  final _aboutCtrl = TextEditingController();
  final _atelierNoteCtrl = TextEditingController();
  String _city = '';
  String _district = '';
  String _neighborhood = '';
  // Haritada seçilen salon konumu (onboarding state).
  double? _pickedLat;
  double? _pickedLng;
  Map<String, dynamic> _profileSnapshot = {};
  bool _profileLoading = true;
  bool _profileSaving = false;
  String? _profileError;
  bool _profileNeedsAuth = false;

  // Ana hizmet kategorileri (onboarding çoklu seçim).
  List<BusinessServiceCategory> _systemCategories = [];
  final Set<String> _selectedCategorySlugs = {};

  // Hizmet ekleme modalındaki kategori seçici listesi (sistem + özel).
  List<BusinessServiceCategory> _allServiceCategories = [];

  // Services (artık modal/bottom-sheet ile eklenir — inline form yok)
  List<BusinessServiceItem> _services = [];
  bool _servicesLoading = true;
  bool _servicesLoaded = false;
  bool _serviceSaving = false;
  int? _serviceBusyDeleteId;
  String? _servicesError;
  String _serviceSuggGroup = 'Tırnak';

  // Staff (artık modal/bottom-sheet ile eklenir — inline form yok)
  List<BusinessStaffItem> _staffMembers = [];
  bool _staffLoading = true;
  bool _staffLoaded = false;
  bool _staffSaving = false;
  int? _staffBusyDeleteId;
  String? _staffError;

  // Hours
  static const _allDays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  static const _dayNames = {
    'mon': 'Pazartesi',
    'tue': 'Salı',
    'wed': 'Çarşamba',
    'thu': 'Perşembe',
    'fri': 'Cuma',
    'sat': 'Cumartesi',
    'sun': 'Pazar',
  };
  List<Map<String, dynamic>> _hours = [];
  bool _hoursLoading = true;
  bool _hoursSaving = false;
  String? _hoursError;
  bool _hoursLoaded = false;

  // Deposit
  bool _depositActive = true;
  String _depositMode = 'percent';
  int _depositRate = 25;
  final _fixedDepositCtrl = TextEditingController(text: '250');
  bool _depositPerService = false;
  String _cancelPolicy = 'esnek';
  bool _depositLoading = true;
  bool _depositSaving = false;
  String? _depositError;
  bool _depositLoaded = false;

  static const _cancelOptions = [
    (id: 'esnek', name: 'Esnek', sub: '24 saat öncesine kadar ücretsiz iptal.'),
    (id: 'orta', name: 'Orta', sub: '48 saat öncesine kadar ücretsiz iptal.'),
    (id: 'kati', name: 'Katı', sub: 'İptal halinde kapora iade edilmez.'),
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  WebeyBackRegistration? _backRegistration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sistem geri tuşu: ilk adım değilse bir önceki onboarding adımına dön.
    _backRegistration ??= WebeyBackScope.register(context, () {
      if (_step.index > 0) {
        _back();
        return true;
      }
      return false;
    });
  }

  @override
  void dispose() {
    _backRegistration?.dispose();
    _nameCtrl.dispose();
    _ownerCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _districtCtrl.dispose();
    _neighborhoodCtrl.dispose();
    _addressCtrl.dispose();
    _streetCtrl.dispose();
    _buildingNoCtrl.dispose();
    _aboutCtrl.dispose();
    _atelierNoteCtrl.dispose();
    _fixedDepositCtrl.dispose();
    super.dispose();
  }

  // ── Loaders ─────────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    if (!widget.hasAuthenticatedSession) {
      setState(() {
        _profileLoading = false;
        _profileNeedsAuth = true;
        _profileError = null;
      });
      return;
    }
    setState(() {
      _profileLoading = true;
      _profileNeedsAuth = false;
      _profileError = null;
    });
    try {
      final p = await _repository.getBusinessProfile();
      if (!mounted) return;
      _profileSnapshot = Map<String, dynamic>.from(p);
      _nameCtrl.text = p['name']?.toString() ?? '';
      _ownerCtrl.text = p['owner_name']?.toString() ?? '';
      _phoneCtrl.text = _localPhone(p['phone']?.toString() ?? '');
      _city = p['city']?.toString() ?? '';
      _district = p['district']?.toString() ?? '';
      _neighborhood = p['neighborhood']?.toString() ?? '';
      _cityCtrl.text = _city;
      _districtCtrl.text = _district;
      _neighborhoodCtrl.text = _neighborhood;
      _addressCtrl.text = (p['address_line'] ?? p['address'])?.toString() ?? '';
      _streetCtrl.text = p['street_name']?.toString() ?? '';
      _buildingNoCtrl.text = p['building_no']?.toString() ?? '';
      _aboutCtrl.text = (p['about'] ?? p['description'])?.toString() ?? '';
      _atelierNoteCtrl.text = (p['atelier_note'] ?? '')?.toString() ?? '';
      _pickedLat = _coordOrNull(p['latitude']);
      _pickedLng = _coordOrNull(p['longitude']);
      final savedSlugs = p['category_slugs'];
      if (savedSlugs is List) {
        _selectedCategorySlugs
          ..clear()
          ..addAll(
            savedSlugs.map((e) => e.toString()).where((e) => e.isNotEmpty),
          );
      }
      setState(() {
        _profileLoading = false;
      });
      _loadSystemCategories();
    } catch (error) {
      if (!mounted) return;
      final needsAuth = error is ApiException && error.statusCode == 401;
      setState(() {
        _profileNeedsAuth = needsAuth;
        _profileError = _friendlyError(error, 'Profil yüklenemedi.');
        _profileLoading = false;
      });
    }
  }

  Future<void> _loadSystemCategories() async {
    try {
      final categories = await _repository.getServiceCategories();
      if (!mounted) return;
      setState(() {
        _systemCategories = categories.where((c) => c.isSystem).toList();
      });
    } catch (_) {
      // Kategori listesi yüklenemezse seçim alanı gizli kalır; profil
      // kaydı bloklanmaz (backend migration öncesi geriye uyumluluk).
    }
  }

  Future<void> _loadHours() async {
    setState(() {
      _hoursLoading = true;
      _hoursError = null;
    });
    try {
      final hours = await _repository.getBusinessHours();
      if (!mounted) return;
      final byDay = {for (final h in hours) (h['day'] ?? '').toString(): h};
      _hours = _allDays.map((d) {
        final existing = byDay[d];
        if (existing != null) {
          final m = Map<String, dynamic>.from(existing);
          // Backend HH:mm:ss döndürebilir → UI/validation için HH:mm'e normalize et.
          m['open_time'] = _normalizeHHmm(m['open_time']?.toString());
          m['close_time'] = _normalizeHHmm(m['close_time']?.toString());
          return m;
        }
        final isOpen = d != 'sun';
        return <String, dynamic>{
          'day': d,
          'is_open': isOpen,
          'open_time': isOpen ? '09:00' : null,
          'close_time': isOpen ? '18:00' : null,
        };
      }).toList();
      setState(() {
        _hoursLoading = false;
        _hoursLoaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _hoursError = _friendlyError(error, 'Çalışma saatleri yüklenemedi.');
        _hoursLoading = false;
      });
    }
  }

  Future<void> _loadDeposit() async {
    setState(() {
      _depositLoading = true;
      _depositError = null;
    });
    try {
      final policy = await _repository.getDepositPolicy();
      if (!mounted) return;
      final rate = (policy['rate_pct'] as num?)?.toInt() ?? 25;
      final fixedAmount = (policy['fixed_deposit_amount'] as num?)?.round();
      setState(() {
        _depositActive = rate > 0;
        _depositMode = policy['deposit_mode']?.toString() == 'fixed'
            ? 'fixed'
            : 'percent';
        if (_depositMode == 'fixed') _depositActive = true;
        _depositRate = rate <= 0 ? 25 : _normalizedDepositRate(rate);
        if (fixedAmount != null && fixedAmount > 0) {
          _fixedDepositCtrl.text = '$fixedAmount';
        }
        _depositPerService = (policy['per_service'] as bool?) ?? false;
        _cancelPolicy = (policy['cancel_policy'] as String?) ?? 'esnek';
        _depositLoading = false;
        _depositLoaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _depositError = _friendlyError(error, 'Kapora politikası yüklenemedi.');
        _depositLoading = false;
      });
    }
  }

  // 0,0 ("Null Island") veya parse edilemeyen değerler konum sayılmaz.
  static double? _coordOrNull(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (parsed == null) return null;
    if (parsed.abs() < 0.0001) return null;
    return parsed;
  }

  bool get _hasPickedLocation => _pickedLat != null && _pickedLng != null;

  Future<void> _openLocationPicker() async {
    final picked = await Navigator.of(context).push<BusinessLocationPickResult>(
      MaterialPageRoute(
        builder: (_) => BusinessLocationPickerScreen(
          initialLatitude: _pickedLat,
          initialLongitude: _pickedLng,
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _pickedLat = picked.latitude;
        _pickedLng = picked.longitude;
      });
    }
  }

  /// Konum seçilmeden devam edilmek istenirse net uyarı verir.
  /// true dönerse kullanıcı bilerek atladı, kayda devam edilir.
  Future<bool> _confirmSkipLocation() async {
    final skip = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WebeyColors.softWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Salon konumu seçilmedi',
          style: TextStyle(
            color: WebeyColors.darkEspresso,
            fontSize: 16,
            fontFamily: 'Georgia',
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Salonunuzun müşteri haritasında görünebilmesi için konum '
          'seçmelisiniz. Konumu daha sonra "Salon Konumu" ayarlarından da '
          'ekleyebilirsiniz.',
          style: TextStyle(
            color: WebeyColors.darkEspresso,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Şimdilik atla',
              style: TextStyle(color: WebeyColors.mutedTaupe),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: WebeyColors.darkEspresso,
              foregroundColor: WebeyColors.primaryGold,
            ),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Konum Seç'),
          ),
        ],
      ),
    );
    if (skip == false && mounted) {
      await _openLocationPicker();
      // Picker'dan konum seçildiyse kayda devam; yine seçilmediyse durdur.
      return _hasPickedLocation;
    }
    return skip == true;
  }

  // ── Savers ──────────────────────────────────────────────────────────────

  Future<void> _saveProfile() async {
    if (_profileSaving) return;
    if (_profileNeedsAuth) {
      _snack('Devam etmek için işletme hesabıyla giriş yapın.');
      return;
    }
    if (!(_profileFormKey.currentState?.validate() ?? false)) return;
    // Kategori listesi yüklendiyse en az bir ana kategori zorunlu.
    if (_systemCategories.isNotEmpty && _selectedCategorySlugs.isEmpty) {
      _snack('En az bir hizmet kategorisi seçin.');
      return;
    }
    if (!_hasPickedLocation) {
      final proceed = await _confirmSkipLocation();
      if (!proceed || !mounted) return;
    }

    setState(() => _profileSaving = true);
    try {
      String? cleaned(TextEditingController c) {
        final v = c.text.trim();
        return v.isEmpty ? null : v;
      }

      final street = _streetCtrl.text.trim();
      final building = _buildingNoCtrl.text.trim();
      final freeAddr = _addressCtrl.text.trim();
      final composedParts = <String>[
        if (street.isNotEmpty) street,
        if (building.isNotEmpty) 'No: $building',
        if (freeAddr.isNotEmpty) freeAddr,
      ];
      final composedAddress = composedParts.join(', ');
      final updated = await _repository.saveBusinessProfile({
        ..._profileSnapshot,
        'name': _nameCtrl.text.trim(),
        'owner_name': cleaned(_ownerCtrl),
        'phone': _normalizedPhone(),
        'city': _city.isEmpty ? null : _city,
        'district': _district.isEmpty ? null : _district,
        'neighborhood': _neighborhood.isEmpty ? null : _neighborhood,
        'address_line': composedAddress.isEmpty ? null : composedAddress,
        'street_name': street.isEmpty ? null : street,
        'building_no': building.isEmpty ? null : building,
        'about': cleaned(_aboutCtrl),
        'atelier_note': cleaned(_atelierNoteCtrl),
        'latitude': _pickedLat,
        'longitude': _pickedLng,
        if (_selectedCategorySlugs.isNotEmpty)
          'category_slugs': _selectedCategorySlugs.toList(),
      });
      if (!mounted) return;
      _profileSnapshot = Map<String, dynamic>.from(updated);
      setState(() => _profileSaving = false);
      _goToStep(_OnbStep.services);
    } catch (error) {
      if (!mounted) return;
      final needsAuth = error is ApiException && error.statusCode == 401;
      setState(() {
        _profileSaving = false;
        _profileNeedsAuth = needsAuth;
      });
      _snack(_friendlyError(error, 'Profil kaydedilemedi.'));
    }
  }

  Future<void> _saveHours() async {
    if (_hoursSaving) return;
    for (final h in _hours) {
      if (h['is_open'] == true) {
        final open = h['open_time']?.toString();
        final close = h['close_time']?.toString();
        if (open == null || close == null) {
          _snack('Açık günler için saat aralığı boş olamaz.');
          return;
        }
        if (!_isTimeBefore(open, close)) {
          _snack(
            '${_dayNames[h['day']]}: kapanış saati açılıştan sonra olmalı.',
          );
          return;
        }
      }
    }
    setState(() => _hoursSaving = true);
    try {
      await _repository.saveBusinessHours(_hours);
      if (!mounted) return;
      setState(() => _hoursSaving = false);
      _goToStep(_OnbStep.deposit);
    } catch (error) {
      if (!mounted) return;
      setState(() => _hoursSaving = false);
      _snack(_friendlyError(error, 'Çalışma saatleri kaydedilemedi.'));
    }
  }

  Future<void> _loadServices() async {
    setState(() {
      _servicesLoading = true;
      _servicesError = null;
    });
    try {
      final items = await _repository.getServices(includeInactive: true);
      if (!mounted) return;
      setState(() {
        _services = List<BusinessServiceItem>.from(items);
        _servicesLoading = false;
        _servicesLoaded = true;
      });
      if (_allServiceCategories.isEmpty) {
        try {
          final categories = await _repository.getServiceCategories();
          if (mounted) setState(() => _allServiceCategories = categories);
        } catch (_) {
          // Kategori listesi alınamazsa hizmet ekleme kategorisiz devam eder.
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _servicesError = _friendlyError(error, 'Hizmetler yüklenemedi.');
        _servicesLoading = false;
      });
    }
  }

  // Hizmet ekleme/düzenleme modal'ını açar (popüler öneri ön-dolu açılabilir).
  Future<void> _openServiceSheet({
    BusinessServiceItem? edit,
    _SvcSuggestion? preset,
  }) async {
    final result = await showModalBottomSheet<_ServiceFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ServiceFormSheet(
        initialName: edit?.name ?? preset?.name ?? '',
        initialDuration: edit?.durationMinutes ?? preset?.duration ?? 60,
        initialPrice: edit != null ? edit.price : (preset?.price ?? 0),
        hasPresetPrice: edit != null || preset != null,
        initialDesc: edit?.description ?? '',
        isEdit: edit != null,
        repository: _repository,
        categories: _allServiceCategories,
        initialCategoryId: edit?.categoryId,
        initialCategoryName: edit?.category,
        onCategoryCreated: (category) {
          if (!_allServiceCategories.any((c) => c.id == category.id)) {
            setState(
              () =>
                  _allServiceCategories = [..._allServiceCategories, category],
            );
          }
        },
      ),
    );
    if (result == null || !mounted) return;

    // Duplicate isim kontrolü (düzenleme hariç).
    final lower = result.name.toLowerCase();
    final dup = _services.any(
      (s) => s.id != edit?.id && s.name.trim().toLowerCase() == lower,
    );
    if (dup) {
      _snack('Bu hizmet zaten eklendi.');
      return;
    }

    setState(() => _serviceSaving = true);
    try {
      final payload = BusinessServiceItem(
        id: edit?.id,
        name: result.name,
        description: result.description,
        price: result.price,
        durationMinutes: result.duration,
        category: result.categoryName,
        categoryId: result.categoryId,
        isActive: true,
        sortOrder: edit?.sortOrder ?? _services.length,
      );
      final saved = await _repository.saveService(payload);
      if (!mounted) return;
      setState(() {
        if (edit != null) {
          _services = _services
              .map((s) => s.id == saved.id ? saved : s)
              .toList();
        } else {
          _services = [..._services, saved];
        }
        _serviceSaving = false;
      });
      _snack(edit != null ? 'Hizmet güncellendi.' : 'Hizmet eklendi.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _serviceSaving = false);
      _snack(_friendlyError(error, 'Hizmet kaydedilemedi.'));
    }
  }

  Future<void> _removeService(BusinessServiceItem item) async {
    final id = item.id;
    if (id == null) {
      setState(() {
        _services = _services.where((s) => s != item).toList();
      });
      return;
    }
    if (_serviceBusyDeleteId != null) return;
    setState(() => _serviceBusyDeleteId = id);
    try {
      await _repository.deleteService(id);
      if (!mounted) return;
      setState(() {
        _services = _services.where((s) => s.id != id).toList();
        _serviceBusyDeleteId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _serviceBusyDeleteId = null);
      _snack(_friendlyError(error, 'Hizmet silinemedi.'));
    }
  }

  Future<void> _loadStaff() async {
    setState(() {
      _staffLoading = true;
      _staffError = null;
    });
    try {
      final items = await _repository.getStaff();
      if (!mounted) return;
      setState(() {
        _staffMembers = List<BusinessStaffItem>.from(items);
        _staffLoading = false;
        _staffLoaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _staffError = _friendlyError(error, 'Personel yüklenemedi.');
        _staffLoading = false;
      });
    }
  }

  // Uzman ekleme/düzenleme modal'ını açar (e-posta yok, rol chip'li, +90 telefon).
  Future<void> _openStaffSheet({BusinessStaffItem? edit}) async {
    final result = await showModalBottomSheet<_StaffFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StaffFormSheet(
        initialName: edit?.name ?? '',
        initialRole: edit?.role ?? '',
        initialPhone10: _localPhone(edit?.phone ?? ''),
        isEdit: edit != null,
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _staffSaving = true);
    try {
      final payload = BusinessStaffItem(
        id: edit?.id,
        name: result.name,
        role: result.role,
        // E-posta onboarding'de sorulmaz; düzenlemede mevcut değer korunur.
        email: edit?.email,
        phone: result.phone10 ?? edit?.phone,
        avatarUrl: edit?.avatarUrl,
        isActive: edit?.isActive ?? true,
        serviceIds: edit?.serviceIds ?? const [],
        hours: edit?.hours ?? const [],
      );
      final saved = await _repository.saveStaff(payload);
      if (!mounted) return;
      setState(() {
        if (edit != null) {
          _staffMembers = _staffMembers
              .map((s) => s.id == saved.id ? saved : s)
              .toList();
        } else {
          _staffMembers = [..._staffMembers, saved];
        }
        _staffSaving = false;
      });
      _snack(edit != null ? 'Uzman güncellendi.' : 'Uzman eklendi.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _staffSaving = false);
      _snack(_friendlyError(error, 'Personel kaydedilemedi.'));
    }
  }

  Future<void> _removeStaff(BusinessStaffItem item) async {
    final id = item.id;
    if (id == null) {
      setState(() {
        _staffMembers = _staffMembers.where((s) => s != item).toList();
      });
      return;
    }
    if (_staffBusyDeleteId != null) return;
    setState(() => _staffBusyDeleteId = id);
    try {
      await _repository.deleteStaff(id);
      if (!mounted) return;
      setState(() {
        _staffMembers = _staffMembers.where((s) => s.id != id).toList();
        _staffBusyDeleteId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _staffBusyDeleteId = null);
      _snack(_friendlyError(error, 'Personel silinemedi.'));
    }
  }

  Future<void> _saveDeposit() async {
    if (_depositSaving) return;
    if (_depositActive && !_depositRateOptions.contains(_depositRate)) {
      _snack('Kapora oranı seçin.');
      return;
    }
    final fixedAmount = int.tryParse(_fixedDepositCtrl.text.trim()) ?? 0;
    if (_depositActive && _depositMode == 'fixed' && fixedAmount <= 0) {
      _snack('Sabit kapora tutari girin.');
      return;
    }
    setState(() => _depositSaving = true);
    try {
      await _repository.saveDepositPolicy({
        'deposit_mode': _depositActive ? _depositMode : 'percent',
        'rate_pct': !_depositActive || _depositMode == 'fixed'
            ? 0
            : _depositRate,
        'fixed_deposit_amount': _depositActive && _depositMode == 'fixed'
            ? fixedAmount
            : null,
        'per_service': _depositActive && _depositMode == 'percent'
            ? _depositPerService
            : false,
        'cancel_policy': _cancelPolicy,
      });
      if (!mounted) return;
      setState(() => _depositSaving = false);
      _goToStep(_OnbStep.done);
    } catch (error) {
      if (!mounted) return;
      setState(() => _depositSaving = false);
      _snack(_friendlyError(error, 'Kapora politikası kaydedilemedi.'));
    }
  }

  // ── Navigation ──────────────────────────────────────────────────────────

  Future<void> _completeOnboarding() async {
    if (_completeSaving) return;
    setState(() => _completeSaving = true);
    try {
      await _repository.markOnboardingComplete(step: 7);
      if (!mounted) return;
      setState(() => _completeSaving = false);
      widget.onComplete();
    } catch (error) {
      if (!mounted) return;
      setState(() => _completeSaving = false);
      _snack(
        _friendlyError(error, 'Onboarding tamamlandı olarak işaretlenemedi.'),
      );
    }
  }

  void _goToStep(_OnbStep next) {
    setState(() => _step = next);
    if (next == _OnbStep.services && !_servicesLoaded) _loadServices();
    if (next == _OnbStep.staff && !_staffLoaded) _loadStaff();
    if (next == _OnbStep.hours && !_hoursLoaded) _loadHours();
    if (next == _OnbStep.deposit && !_depositLoaded) _loadDeposit();
  }

  void _back() {
    final idx = _step.index;
    if (idx == 0) return;
    _goToStep(_OnbStep.values[idx - 1]);
  }

  Future<void> _pickCity() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _LocationPickerSheet(
        title: 'Şehir seçin',
        items: TurkeyLocations.cities,
      ),
    );
    if (picked == null || picked == _city) return;
    setState(() {
      _city = picked;
      _district = '';
      _neighborhood = '';
      _cityCtrl.text = picked;
      _districtCtrl.clear();
      _neighborhoodCtrl.clear();
    });
  }

  Future<void> _pickDistrict() async {
    if (_city.isEmpty) {
      _snack('Önce şehir seçin.');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LocationPickerSheet(
        title: 'İlçe seçin',
        items: TurkeyLocations.districtsFor(_city),
      ),
    );
    if (picked == null || picked == _district) return;
    setState(() {
      _district = picked;
      _neighborhood = '';
      _districtCtrl.text = picked;
      _neighborhoodCtrl.clear();
    });
  }

  Future<void> _pickNeighborhood() async {
    final items = TurkeyLocations.neighborhoodsFor(_city, _district);
    if (items.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _LocationPickerSheet(title: 'Mahalle seçin', items: items),
    );
    if (picked == null) return;
    setState(() {
      _neighborhood = picked;
      _neighborhoodCtrl.text = picked;
    });
  }

  bool get _hasNeighborhoodDataset =>
      _district.isNotEmpty &&
      TurkeyLocations.neighborhoodsFor(_city, _district).isNotEmpty;

  void _snack(String msg) {
    final lower = msg.toLowerCase();
    if ([
      'eklendi',
      'güncellendi',
      'kaydedildi',
      'silindi',
    ].any(lower.contains)) {
      WebeyToast.success(context, msg);
    } else if ([
      'hata',
      'olamaz',
      'kaydedilemedi',
      'silinemedi',
      'giriş yap',
      'zaten',
    ].any(lower.contains)) {
      WebeyToast.error(context, msg);
    } else {
      WebeyToast.info(context, msg);
    }
  }

  // 'HH:mm', 'HH:mm:ss', 'H:mm' → dakika; geçersizse null.
  static int? _timeToMinutes(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  static String _formatMinutes(int mins) {
    final h = (mins ~/ 60) % 24;
    final m = mins % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  // Backend HH:mm:ss döndürse bile UI her zaman HH:mm gösterir.
  static String? _normalizeHHmm(String? raw) {
    final mins = _timeToMinutes(raw);
    return mins == null ? null : _formatMinutes(mins);
  }

  bool _isTimeBefore(String a, String b) {
    final aMin = _timeToMinutes(a);
    final bMin = _timeToMinutes(b);
    if (aMin == null || bMin == null) return false;
    return aMin < bMin;
  }

  String? _validateBusinessPhone(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (digits.length != 10) return 'Telefon 10 haneli olmalı.';
    if (!digits.startsWith('5')) return 'Telefon 5 ile başlamalı.';
    return null;
  }

  String _localPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('90')) {
      return digits.substring(2);
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return digits.substring(1);
    }
    if (digits.length > 10) return digits.substring(digits.length - 10);
    return digits;
  }

  String? _normalizedPhone() {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? null : digits;
  }

  String _friendlyError(Object error, String fallback) {
    if (error is ApiException) {
      if (error.statusCode == 401) {
        return 'Oturumun süresi doldu. Lütfen tekrar giriş yap.';
      }
      if (error.message.trim().isNotEmpty) return error.message;
      if (error.statusCode == 401) {
        return 'Oturum süresi doldu. Lütfen tekrar giriş yapın.';
      }
      if (error.statusCode == 403 || error.code == 'business_required') {
        return 'Bu hesaba bağlı işletme bulunamadı.';
      }
    }
    return fallback;
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final stepIndex = _step.index;
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(stepIndex > 0),
              const SizedBox(height: 18),
              _buildProgress(stepIndex),
              const SizedBox(height: 18),
              Expanded(child: _buildStepContent()),
              const SizedBox(height: 12),
              _buildPrimaryAction(),
              _buildSecondaryAction(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool canGoBack) {
    return Row(
      children: [
        if (canGoBack)
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: WebeyColors.darkEspresso,
            ),
            onPressed: _back,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          )
        else
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: WebeyColors.darkEspresso,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text(
                'W',
                style: TextStyle(
                  color: WebeyColors.primaryGold,
                  fontSize: 18,
                  fontFamily: 'Georgia',
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        const Spacer(),
        TextButton(onPressed: widget.onLogin, child: const Text('Giriş yap')),
      ],
    );
  }

  Widget _buildProgress(int stepIndex) {
    return Row(
      children: List.generate(_OnbStep.values.length, (i) {
        final active = i <= stepIndex;
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(
              right: i == _OnbStep.values.length - 1 ? 0 : 6,
            ),
            decoration: BoxDecoration(
              color: active ? WebeyColors.primaryGold : WebeyColors.borderSand,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStepContent() {
    return switch (_step) {
      _OnbStep.profile => _buildProfileStep(),
      _OnbStep.services => _buildServicesStep(),
      _OnbStep.staff => _buildStaffStep(),
      _OnbStep.hours => _buildHoursStep(),
      _OnbStep.deposit => _buildDepositStep(),
      _OnbStep.done => _buildDoneStep(),
    };
  }

  // ── Step: Profile ───────────────────────────────────────────────────────

  /// "Hangi hizmet kategorilerinde çalışıyorsunuz?" çoklu seçim alanı.
  Widget _buildCategorySelection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hangi hizmet kategorilerinde çalışıyorsunuz? *',
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Müşterilerin sizi doğru kategorilerde bulabilmesi için sunduğunuz '
            'hizmet alanlarını seçin.',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in _systemCategories) _categoryChip(category),
            ],
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(BusinessServiceCategory category) {
    final selected = _selectedCategorySlugs.contains(category.slug);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (selected) {
            _selectedCategorySlugs.remove(category.slug);
          } else {
            _selectedCategorySlugs.add(category.slug);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? WebeyColors.darkEspresso : WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? WebeyColors.darkEspresso : WebeyColors.borderSand,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(
                Icons.check_rounded,
                size: 13,
                color: WebeyColors.primaryGold,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              category.name,
              style: TextStyle(
                color: selected ? Colors.white : WebeyColors.darkEspresso,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileStep() {
    if (_profileLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepTitle('Salon profilini hazırla'),
          _stepSubtitle(
            'Müşterilerin seni tanıyabilmesi için temel bilgilerini doldur.',
          ),
          const SizedBox(height: 16),
          if (_profileError != null) ...[
            _errorBanner(_profileError!, _loadProfile),
            const SizedBox(height: 12),
          ],
          if (_profileNeedsAuth) ...[
            _authRequiredCard(),
            const SizedBox(height: 12),
          ],
          if (_systemCategories.isNotEmpty) ...[
            _buildCategorySelection(),
            const SizedBox(height: 18),
          ],
          Form(
            key: _profileFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field(
                  controller: _nameCtrl,
                  label: 'İşletme adı *',
                  hint: 'Örn. Luna Beauty Studio',
                  maxLength: 40,
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) {
                      return 'İşletme adı zorunlu.';
                    }
                    return null;
                  },
                ),
                _field(
                  controller: _ownerCtrl,
                  label: 'Yetkili adı',
                  hint: 'Ad Soyad',
                ),
                _field(
                  controller: _phoneCtrl,
                  label: 'Telefon',
                  hint: '5XX XXX XX XX',
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator: _validateBusinessPhone,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        controller: _cityCtrl,
                        readOnly: true,
                        onTap: _pickCity,
                        label: 'Şehir',
                        hint: 'İstanbul',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        controller: _districtCtrl,
                        readOnly: true,
                        onTap: _city.isEmpty ? null : _pickDistrict,
                        label: 'İlçe',
                        hint: 'Kadıköy',
                      ),
                    ),
                  ],
                ),
                // Mahalle her zaman elle yazılabilir (dataset eksik olsa da
                // kullanıcı kilitlenmez). Dataset varsa "listeden seç" yardımı.
                _field(
                  controller: _neighborhoodCtrl,
                  label: 'Mahalle',
                  hint: _district.isEmpty
                      ? 'Önce ilçe seçin'
                      : 'Mahalle (listede yoksa elle yazın)',
                  onChanged: (v) => _neighborhood = v.trim(),
                ),
                if (_hasNeighborhoodDataset)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10, top: 2),
                    child: GestureDetector(
                      onTap: _pickNeighborhood,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.list_alt_rounded,
                            size: 15,
                            color: WebeyColors.primaryGold,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Mahalle listesinden seç',
                            style: TextStyle(
                              color: WebeyColors.primaryGold,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _field(
                        controller: _streetCtrl,
                        label: 'Sokak / Cadde adı',
                        hint: 'Örn. Bağdat Caddesi',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _field(
                        controller: _buildingNoCtrl,
                        label: 'Bina no',
                        hint: '12/A',
                      ),
                    ),
                  ],
                ),
                _field(
                  controller: _addressCtrl,
                  label: 'Açık adres (kat, daire, tarif)',
                  hint: 'Örn. Kat 2 / Daire 5',
                ),
                // ── Salon Konumu ────────────────────────────────────────
                _buildLocationSection(),
                const SizedBox(height: 12),
                _field(
                  controller: _aboutCtrl,
                  label: 'Hakkında',
                  hint: 'Salonun kısa tanıtımı',
                  maxLines: 3,
                  maxLength: 500,
                ),
                _field(
                  controller: _atelierNoteCtrl,
                  label: 'Atölye notu',
                  hint: 'Vitrinde görünecek kısa, kişisel not',
                  maxLines: 2,
                  maxLength: 280,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Onboarding profil adımındaki "Salon Konumu" bölümü:
  /// açıklama + adres özeti + haritada seçim + seçildi durumu.
  Widget _buildLocationSection() {
    final addressSummary = [
      if (_neighborhood.isNotEmpty) _neighborhood,
      if (_district.isNotEmpty) _district,
      if (_city.isNotEmpty) _city,
    ].join(' / ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _hasPickedLocation
              ? WebeyColors.successGreen.withAlpha(120)
              : WebeyColors.borderSand,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _hasPickedLocation
                    ? Icons.where_to_vote_rounded
                    : Icons.place_outlined,
                size: 19,
                color: _hasPickedLocation
                    ? WebeyColors.successGreen
                    : WebeyColors.primaryGold,
              ),
              const SizedBox(width: 8),
              const Text(
                'Salon konumunuzu seçin',
                style: TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 14,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _hasPickedLocation
                ? 'Konum seçildi. Salonunuz müşteri haritasında bu noktada '
                      'görünecek.'
                : 'Müşterilerinizin sizi haritada bulabilmesi için salonunuzun '
                      'gerçek konumunu seçin.',
            style: const TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (addressSummary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.home_work_outlined,
                  size: 13,
                  color: WebeyColors.mutedTaupe,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    addressSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_hasPickedLocation) ...[
            const SizedBox(height: 4),
            Text(
              // Teknik bilgi: küçük ve ikincil; ana gösterim harita.
              'Koordinat: ${_pickedLat!.toStringAsFixed(5)}, '
              '${_pickedLng!.toStringAsFixed(5)}',
              style: const TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 10.5,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: WebeyColors.darkEspresso,
                side: const BorderSide(color: WebeyColors.primaryGold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _openLocationPicker,
              icon: const Icon(Icons.map_outlined, size: 17),
              label: Text(
                _hasPickedLocation
                    ? 'Konumu haritada düzenle'
                    : 'Haritada Konum Seç',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step: Services ──────────────────────────────────────────────────────

  Widget _buildServicesStep() {
    if (_servicesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepTitle('Hizmetlerini ekle'),
          _stepSubtitle(
            'Müşterilerin randevu alabilmesi için en az bir hizmet ekle. '
            'Daha fazlasını panelden sonra ekleyebilirsin.',
          ),
          const SizedBox(height: 16),
          if (_servicesError != null) ...[
            _errorBanner(_servicesError!, _loadServices),
            const SizedBox(height: 12),
          ],

          // ── Eklenen hizmetler ──────────────────────────────────────────
          _sectionLabel('Eklenen hizmetler'),
          const SizedBox(height: 8),
          if (_services.isEmpty)
            _emptyStateCard(
              'Henüz hizmet eklemedin',
              'Başlamak için popüler hizmetlerden seçebilir veya kendi '
                  'hizmetini ekleyebilirsin.',
            )
          else
            for (final item in _services) _buildServiceRow(item),

          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _serviceSaving ? null : () => _openServiceSheet(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Yeni hizmet ekle'),
              style: OutlinedButton.styleFrom(
                foregroundColor: WebeyColors.darkEspresso,
                side: const BorderSide(color: WebeyColors.primaryGold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),

          // ── Popüler hizmetlerden hızlı ekle ────────────────────────────
          const SizedBox(height: 22),
          _sectionLabel('Popüler hizmetlerden hızlı ekle'),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final g in _kServiceSuggestions.keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(g),
                      selected: _serviceSuggGroup == g,
                      onSelected: (_) => setState(() => _serviceSuggGroup = g),
                      selectedColor: WebeyColors.primaryGold,
                      labelStyle: TextStyle(
                        color: _serviceSuggGroup == g
                            ? WebeyColors.darkEspresso
                            : WebeyColors.mutedTaupe,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: WebeyColors.softWhite,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: WebeyColors.borderSand),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _kServiceSuggestions[_serviceSuggGroup]!)
                GestureDetector(
                  onTap: _serviceSaving
                      ? null
                      : () => _openServiceSheet(preset: s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: WebeyColors.softWhite,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: WebeyColors.borderSand),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.name,
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${s.duration} dk · ${s.price.round()} TL',
                          style: const TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildServiceRow(BusinessServiceItem item) {
    final busy =
        _serviceBusyDeleteId != null && _serviceBusyDeleteId == item.id;
    final price = item.price > 0 ? '${item.price.round()} TL' : 'Ücretsiz';
    final duration = '${item.durationMinutes} dk';
    final desc = (item.description ?? '').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$price · $duration',
                  style: const TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12,
                  ),
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Düzenle',
            icon: const Icon(
              Icons.edit_outlined,
              color: WebeyColors.darkEspresso,
              size: 18,
            ),
            onPressed: busy ? null : () => _openServiceSheet(edit: item),
          ),
          IconButton(
            tooltip: 'Kaldır',
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.close,
                    color: WebeyColors.mutedTaupe,
                    size: 20,
                  ),
            onPressed: busy ? null : () => _removeService(item),
          ),
        ],
      ),
    );
  }

  // ── Step: Staff ─────────────────────────────────────────────────────────

  Widget _buildStaffStep() {
    if (_staffLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepTitle('Uzmanlarını ekle'),
          _stepSubtitle(
            'Personellerini ekle. Hizmet atamasını ve müsaitliği panelden '
            'tamamlayabilirsin.',
          ),
          const SizedBox(height: 16),
          if (_staffError != null) ...[
            _errorBanner(_staffError!, _loadStaff),
            const SizedBox(height: 12),
          ],
          _sectionLabel('Eklenen uzmanlar'),
          const SizedBox(height: 8),
          if (_staffMembers.isEmpty)
            _emptyStateCard(
              'Henüz uzman eklemedin',
              'İstersen şimdi personellerini ekleyebilir veya panelden sonra '
                  'tamamlayabilirsin.',
            )
          else
            for (final item in _staffMembers) _buildStaffRow(item),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _staffSaving ? null : () => _openStaffSheet(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Yeni uzman ekle'),
              style: OutlinedButton.styleFrom(
                foregroundColor: WebeyColors.darkEspresso,
                side: const BorderSide(color: WebeyColors.primaryGold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildStaffRow(BusinessStaffItem item) {
    final busy = _staffBusyDeleteId != null && _staffBusyDeleteId == item.id;
    final subtitleParts = <String>[];
    if (item.role != null && item.role!.isNotEmpty) {
      subtitleParts.add(item.role!);
    }
    if (item.phone != null && item.phone!.isNotEmpty) {
      subtitleParts.add(_displayPhone(item.phone!));
    }
    final subtitle = subtitleParts.isEmpty
        ? 'Uzman'
        : subtitleParts.join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Düzenle',
            icon: const Icon(
              Icons.edit_outlined,
              color: WebeyColors.darkEspresso,
              size: 18,
            ),
            onPressed: busy ? null : () => _openStaffSheet(edit: item),
          ),
          IconButton(
            tooltip: 'Kaldır',
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.close,
                    color: WebeyColors.mutedTaupe,
                    size: 20,
                  ),
            onPressed: busy ? null : () => _removeStaff(item),
          ),
        ],
      ),
    );
  }

  // ── Step: Hours ─────────────────────────────────────────────────────────

  Widget _buildHoursStep() {
    if (_hoursLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepTitle('Takvimini aç'),
          _stepSubtitle(
            'Haftalık çalışma saatlerini ayarla. Daha sonra panelden değiştirebilirsin.',
          ),
          const SizedBox(height: 16),
          if (_hoursError != null) ...[
            _errorBanner(_hoursError!, _loadHours),
            const SizedBox(height: 12),
          ],
          for (var i = 0; i < _hours.length; i++) _buildHourRow(i),
        ],
      ),
    );
  }

  Future<void> _showCopyHoursSheet(int sourceIndex) async {
    final source = _hours[sourceIndex];
    final open = _normalizeHHmm(source['open_time']?.toString()) ?? '09:00';
    final close = _normalizeHHmm(source['close_time']?.toString()) ?? '18:00';
    final sourceDay = source['day']?.toString() ?? '';
    final selected = <String>{
      for (final h in _hours)
        if ((h['day']?.toString() ?? '') != sourceDay &&
            ((h['is_open'] as bool?) ?? false))
          h['day'].toString(),
    };
    final applied = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return _onbSheetFrame(
              context,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Saatleri kopyala',
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 17,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$open - $close saatlerini secilen gunlere uygula.',
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final h in _hours)
                        if ((h['day']?.toString() ?? '') != sourceDay)
                          FilterChip(
                            label: Text(
                              _dayNames[h['day']?.toString() ?? ''] ??
                                  h['day'].toString(),
                            ),
                            selected: selected.contains(h['day'].toString()),
                            onSelected: (value) => setSheetState(() {
                              final day = h['day'].toString();
                              value ? selected.add(day) : selected.remove(day);
                            }),
                            selectedColor: WebeyColors.primaryGold,
                            backgroundColor: WebeyColors.softWhite,
                            side: BorderSide(
                              color: selected.contains(h['day'].toString())
                                  ? WebeyColors.primaryGold
                                  : WebeyColors.borderSand,
                            ),
                            labelStyle: const TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(sheetContext, selected),
                      child: const Text('Uygula'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (applied == null || applied.isEmpty || !mounted) return;
    setState(() {
      for (var i = 0; i < _hours.length; i++) {
        final day = _hours[i]['day']?.toString() ?? '';
        if (!applied.contains(day)) continue;
        final updated = Map<String, dynamic>.from(_hours[i]);
        updated['open_time'] = open;
        updated['close_time'] = close;
        _hours[i] = updated;
      }
    });
  }

  Widget _buildHourRow(int index) {
    final hour = _hours[index];
    final day = hour['day']?.toString() ?? '';
    final isOpen = (hour['is_open'] as bool?) ?? false;
    final openTime = hour['open_time']?.toString() ?? '';
    final closeTime = hour['close_time']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _dayNames[day] ?? day,
                  style: TextStyle(
                    color: isOpen
                        ? WebeyColors.darkEspresso
                        : WebeyColors.mutedTaupe,
                    fontSize: 13.5,
                    fontWeight: isOpen ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              Switch(
                value: isOpen,
                activeThumbColor: WebeyColors.primaryGold,
                onChanged: (v) => setState(() {
                  final updated = Map<String, dynamic>.from(_hours[index]);
                  updated['is_open'] = v;
                  if (!v) {
                    updated['open_time'] = null;
                    updated['close_time'] = null;
                  } else {
                    updated['open_time'] ??= '09:00';
                    updated['close_time'] ??= '18:00';
                  }
                  _hours[index] = updated;
                }),
              ),
            ],
          ),
          if (isOpen) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _TimePickerField(
                    label: 'Açılış',
                    value: openTime,
                    onChanged: (v) => setState(() {
                      final updated = Map<String, dynamic>.from(_hours[index]);
                      updated['open_time'] = v;
                      _hours[index] = updated;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimePickerField(
                    label: 'Kapanış',
                    value: closeTime,
                    onChanged: (v) => setState(() {
                      final updated = Map<String, dynamic>.from(_hours[index]);
                      updated['close_time'] = v;
                      _hours[index] = updated;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _showCopyHoursSheet(index),
                icon: const Icon(Icons.copy_all_rounded, size: 16),
                label: const Text('Saatleri kopyala'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step: Deposit ───────────────────────────────────────────────────────

  Widget _buildDepositStep() {
    if (_depositLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepTitle('Kapora politikasını belirle'),
          _stepSubtitle(
            'Randevuları güvenceye almak için kapora oranı ve iptal kuralını seç.',
          ),
          const SizedBox(height: 16),
          if (_depositError != null) ...[
            _errorBanner(_depositError!, _loadDeposit),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: WebeyColors.softWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WebeyColors.borderSand),
            ),
            child: SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeThumbColor: WebeyColors.primaryGold,
              title: const Text(
                'Kapora aktif',
                style: TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Kapatırsan müşteriler kapora ödemeden randevu alır.',
                style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12),
              ),
              value: _depositActive,
              onChanged: (v) => setState(() => _depositActive = v),
            ),
          ),
          const SizedBox(height: 12),
          if (_depositActive) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Yuzdelik'),
                  selected: _depositMode == 'percent',
                  selectedColor: WebeyColors.primaryGold,
                  onSelected: (_) => setState(() => _depositMode = 'percent'),
                ),
                ChoiceChip(
                  label: const Text('Sabit TL'),
                  selected: _depositMode == 'fixed',
                  selectedColor: WebeyColors.primaryGold,
                  onSelected: (_) => setState(() => _depositMode = 'fixed'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_depositMode == 'fixed') ...[
              TextField(
                controller: _fixedDepositCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: _onbDec('Sabit kapora tutari', hint: '250 TL'),
              ),
              const SizedBox(height: 16),
            ] else ...[
              const Text(
                'Kapora oranı: ',
                style: TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final rate in _depositRateOptions)
                    ChoiceChip(
                      label: Text('%$rate'),
                      selected: _depositRate == rate,
                      onSelected: (_) => setState(() => _depositRate = rate),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: WebeyColors.softWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: WebeyColors.borderSand),
                ),
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: WebeyColors.primaryGold,
                  title: const Text(
                    'Hizmet bazlı kapora',
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Her hizmet için ayrı kapora oranı tanımlayabilirsin.',
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12,
                    ),
                  ),
                  value: _depositPerService,
                  onChanged: (v) => setState(() => _depositPerService = v),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
          const Text(
            'İptal politikası',
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (final opt in _cancelOptions)
            _cancelOption(opt.id, opt.name, opt.sub),
        ],
      ),
    );
  }

  Widget _cancelOption(String id, String name, String sub) {
    final selected = _cancelPolicy == id;
    return GestureDetector(
      onTap: () => setState(() => _cancelPolicy = id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? WebeyColors.goldLight : WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? WebeyColors.primaryGold : WebeyColors.borderSand,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected
                  ? WebeyColors.primaryGold
                  : WebeyColors.mutedTaupe,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12,
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

  // ── Step: Done ──────────────────────────────────────────────────────────

  Widget _buildDoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: WebeyColors.goldLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: WebeyColors.borderSand),
          ),
          child: const Icon(
            Icons.verified_outlined,
            color: WebeyColors.darkEspresso,
            size: 34,
          ),
        ),
        const SizedBox(height: 24),
        _stepTitle(_completionTitle()),
        _stepSubtitle(
          'Dashboard, takvim, hizmetler ve profil yönetimine başlayabilirsin.',
        ),
        const Spacer(),
      ],
    );
  }

  // İşletme adı / sahip adı varsa kişisel kutlama başlığı; yoksa genel fallback.
  String _completionTitle() {
    final owner = _ownerCtrl.text.trim();
    final biz = _nameCtrl.text.trim();
    if (owner.isNotEmpty) {
      final firstName = owner.split(RegExp(r'\s+')).first;
      return 'Hoş geldin, $firstName!';
    }
    if (biz.isNotEmpty) {
      return '$biz panelin hazır';
    }
    return 'İşletme panelin hazır';
  }

  // ── Primary action ──────────────────────────────────────────────────────

  Widget _buildPrimaryAction() {
    String label;
    bool busy;
    VoidCallback? onPressed;

    switch (_step) {
      case _OnbStep.profile:
        label = 'Kaydet ve devam';
        busy = _profileSaving;
        onPressed = _profileLoading || _profileNeedsAuth ? null : _saveProfile;
        break;
      case _OnbStep.services:
        // Bu adımda en az 1 hizmet zorunlu — "Sonra ekle" yok.
        label = 'Devam et';
        busy = _serviceSaving;
        onPressed = _servicesLoading
            ? null
            : () {
                if (_services.isEmpty) {
                  _snack('Devam etmek için en az bir hizmet ekleyin.');
                  return;
                }
                _goToStep(_OnbStep.staff);
              };
        break;
      case _OnbStep.staff:
        // Uzman opsiyonel — boşken "Sonra ekle, devam et".
        label = _staffMembers.isEmpty ? 'Sonra ekle, devam et' : 'Devam et';
        busy = _staffSaving;
        onPressed = _staffLoading ? null : () => _goToStep(_OnbStep.hours);
        break;
      case _OnbStep.hours:
        label = 'Kaydet ve devam';
        busy = _hoursSaving;
        onPressed = _hoursLoading ? null : _saveHours;
        break;
      case _OnbStep.deposit:
        label = 'Kaydet ve devam';
        busy = _depositSaving;
        onPressed = _depositLoading ? null : _saveDeposit;
        break;
      case _OnbStep.done:
        label = 'Panele geç';
        busy = _completeSaving;
        onPressed = _completeOnboarding;
        break;
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: WebeyColors.darkEspresso,
                ),
              )
            : Text(label),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Widget _buildSecondaryAction() {
    return const SizedBox.shrink();
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: WebeyColors.darkEspresso,
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _emptyStateCard(String title, String subtitle) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: WebeyColors.warmCream,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: WebeyColors.borderSand),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: WebeyColors.darkEspresso,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: WebeyColors.mutedTaupe,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    ),
  );

  // 10 haneli numarayı "+90 5XX XXX XX XX" gösterir.
  String _displayPhone(String raw) {
    final d = _localPhone(raw);
    if (d.length != 10) return raw;
    return '+90 ${d.substring(0, 3)} ${d.substring(3, 6)} '
        '${d.substring(6, 8)} ${d.substring(8)}';
  }

  Widget _stepTitle(String text) => Text(
    text,
    style: const TextStyle(
      color: WebeyColors.darkEspresso,
      fontSize: 26,
      height: 1.15,
      fontFamily: 'Georgia',
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _stepSubtitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: WebeyColors.mutedTaupe,
        fontSize: 14,
        height: 1.45,
      ),
    ),
  );

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
    FormFieldValidator<String>? validator,
    List<TextInputFormatter>? inputFormatters,
    bool readOnly = false,
    VoidCallback? onTap,
    ValueChanged<String>? onChanged,
  }) {
    final formatters = <TextInputFormatter>[
      ...?inputFormatters,
      if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        validator: validator,
        inputFormatters: formatters.isEmpty ? null : formatters,
        readOnly: readOnly,
        onTap: onTap,
        onChanged: onChanged,
        style: const TextStyle(color: WebeyColors.darkEspresso, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(
            color: WebeyColors.mutedTaupe,
            fontSize: 12,
          ),
          filled: true,
          fillColor: WebeyColors.warmCream,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
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
      ),
    );
  }

  Widget _errorBanner(String message, VoidCallback onRetry) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Yeniden dene')),
        ],
      ),
    );
  }

  Widget _authRequiredCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Devam etmek için işletme hesabıyla giriş yap',
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Profil bilgilerini kaydetmek için önce işletme oturumu gerekiyor.',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onLogin,
                  child: const Text('Giriş yap'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.onRegister,
                  child: const Text('Hesap oluştur'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimePickerField extends StatelessWidget {
  const _TimePickerField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  Future<void> _pick(BuildContext context) async {
    final initial = _parse(value) ?? const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    // Sadece 00/15/30/45 dakikalara izin ver: en yakın 15 dk'ya yuvarla.
    var hour = picked.hour;
    var minute = ((picked.minute + 7) ~/ 15) * 15;
    if (minute >= 60) {
      minute = 0;
      hour = (hour + 1) % 24;
    }
    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');
    onChanged('$hh:$mm');
  }

  // 'HH:mm', 'HH:mm:ss', 'H:mm' kabul eder (saniyeli backend değeri de olur).
  TimeOfDay? _parse(String s) {
    final parts = s.trim().split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _displayValue() {
    final t = _parse(value);
    if (t == null) return value.isEmpty ? '--:--' : value;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(9),
      child: InputDecorator(
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
            vertical: 10,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: WebeyColors.borderSand),
          ),
        ),
        child: Text(
          _displayValue(),
          style: const TextStyle(color: WebeyColors.darkEspresso, fontSize: 13),
        ),
      ),
    );
  }
}

class _LocationPickerSheet extends StatefulWidget {
  const _LocationPickerSheet({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  final _searchCtrl = TextEditingController();
  late List<String> _filtered = widget.items;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? widget.items
          : widget.items
                .where((item) => item.toLowerCase().contains(query))
                .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: WebeyColors.ivory,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: WebeyColors.borderSand,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.title,
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 16,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w700,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    hintText: 'Ara...',
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) {
                    final item = _filtered[index];
                    return ListTile(
                      title: Text(item),
                      onTap: () => Navigator.of(context).pop(item),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ONBOARDING — Popüler hizmet önerileri + uzman rol chip'leri + form modal'ları
// ─────────────────────────────────────────────────────────────────────────────

class _SvcSuggestion {
  const _SvcSuggestion(this.name, this.duration, this.price);
  final String name;
  final int duration;
  final double price;
}

const Map<String, List<_SvcSuggestion>> _kServiceSuggestions = {
  'Tırnak': [
    _SvcSuggestion('Manikür', 45, 400),
    _SvcSuggestion('Pedikür', 60, 500),
    _SvcSuggestion('Kalıcı Oje', 60, 650),
    _SvcSuggestion('Protez Tırnak', 90, 900),
    _SvcSuggestion('Nail Art', 30, 300),
    _SvcSuggestion('Jel Güçlendirme', 75, 750),
  ],
  'Saç': [
    _SvcSuggestion('Saç Kesimi', 45, 500),
    _SvcSuggestion('Fön', 30, 350),
    _SvcSuggestion('Boya', 120, 1500),
    _SvcSuggestion('Dip Boya', 90, 900),
    _SvcSuggestion('Saç Bakımı', 60, 800),
    _SvcSuggestion('Keratin Bakım', 120, 1800),
  ],
  'Cilt Bakımı': [
    _SvcSuggestion('Cilt Bakımı', 60, 900),
    _SvcSuggestion('Medikal Cilt Bakımı', 75, 1200),
    _SvcSuggestion('Lazer Epilasyon', 30, 700),
  ],
  'Kaş/Kirpik': [
    _SvcSuggestion('Kaş Tasarımı', 30, 350),
    _SvcSuggestion('Kirpik Lifting', 60, 700),
    _SvcSuggestion('İpek Kirpik', 90, 1200),
    _SvcSuggestion('Makyaj', 60, 1000),
  ],
};

const List<String> _kStaffRoles = [
  'Uzman',
  'Kuaför',
  'Manikürist',
  'Pedikürist',
  'Nail Artist',
  'Güzellik Uzmanı',
  'Cilt Bakım Uzmanı',
  'Kaş/Kirpik Uzmanı',
  'Makyaj Uzmanı',
  'Masaj Terapisti',
];

Widget _onbSheetFrame(BuildContext context, {required Widget child}) {
  return SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Material(
        color: WebeyColors.ivory,
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: child,
          ),
        ),
      ),
    ),
  );
}

InputDecoration _onbDec(String label, {String? hint, Widget? prefixIcon}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    prefixIconConstraints: prefixIcon == null
        ? null
        : const BoxConstraints(minWidth: 0, minHeight: 0),
    labelStyle: const TextStyle(color: WebeyColors.darkEspresso, fontSize: 12),
    hintStyle: const TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12.5),
    filled: true,
    fillColor: WebeyColors.softWhite,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: WebeyColors.borderSand, width: 1.15),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: WebeyColors.primaryGold, width: 1.5),
    ),
  );
}

// ── Hizmet form modal ────────────────────────────────────────────────────────

class _ServiceFormResult {
  const _ServiceFormResult({
    required this.name,
    required this.duration,
    required this.price,
    this.description,
    this.categoryId,
    this.categoryName,
  });
  final String name;
  final int duration;
  final double price;
  final String? description;
  final int? categoryId;
  final String? categoryName;
}

class _ServiceFormSheet extends StatefulWidget {
  const _ServiceFormSheet({
    required this.initialName,
    required this.initialDuration,
    required this.initialPrice,
    required this.hasPresetPrice,
    required this.initialDesc,
    required this.isEdit,
    required this.repository,
    required this.categories,
    this.initialCategoryId,
    this.initialCategoryName,
    this.onCategoryCreated,
  });
  final String initialName;
  final int initialDuration;
  final double initialPrice;
  final bool hasPresetPrice;
  final String initialDesc;
  final bool isEdit;
  final BusinessRepository repository;
  final List<BusinessServiceCategory> categories;
  final int? initialCategoryId;
  final String? initialCategoryName;
  final ValueChanged<BusinessServiceCategory>? onCategoryCreated;

  @override
  State<_ServiceFormSheet> createState() => _ServiceFormSheetState();
}

class _ServiceFormSheetState extends State<_ServiceFormSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late int _duration = _nearestServiceDuration(widget.initialDuration);
  late final TextEditingController _price = TextEditingController(
    text: widget.hasPresetPrice ? widget.initialPrice.round().toString() : '',
  );
  late final TextEditingController _desc = TextEditingController(
    text: widget.initialDesc,
  );
  late int? _categoryId = widget.initialCategoryId;
  late String? _categoryName = widget.initialCategoryName;
  String? _error;

  Future<void> _pickCategory() async {
    final picked = await showServiceCategoryPicker(
      context,
      repository: widget.repository,
      categories: widget.categories,
      selectedId: _categoryId,
    );
    if (picked == null || !mounted) return;
    final category = picked.category;
    if (category != null) widget.onCategoryCreated?.call(category);
    setState(() {
      _categoryId = category?.id;
      _categoryName = category?.name;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (name.isEmpty) {
      setState(() => _error = 'Hizmet adı zorunlu.');
      return;
    }
    if (name.length > 60) {
      setState(() => _error = 'Hizmet adı en fazla 60 karakter olabilir.');
      return;
    }
    if (!_serviceDurationOptions.contains(_duration)) {
      setState(() => _error = 'Lütfen hizmet süresi seçin.');
      return;
    }
    if (price == null || price < 0) {
      setState(() => _error = 'Fiyat 0 veya daha büyük olmalı.');
      return;
    }
    final desc = _desc.text.trim();
    Navigator.of(context).pop(
      _ServiceFormResult(
        name: name,
        duration: _duration,
        price: price,
        description: desc.isEmpty ? null : desc,
        categoryId: _categoryId,
        categoryName: _categoryName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _onbSheetFrame(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: WebeyColors.borderSand,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.isEdit ? 'Hizmeti düzenle' : 'Yeni hizmet',
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 17,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            maxLength: 60,
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
            decoration: _onbDec('Hizmet adı *', hint: 'Örn. Kalıcı Oje'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DurationChoiceField(
                  value: _duration,
                  onChanged: (value) => setState(() => _duration = value),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: _onbDec('Fiyat (TL) *', hint: '0'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.categories.isNotEmpty) ...[
            ServiceCategoryField(
              label: 'Hizmet Kategorisi',
              valueText: _categoryName,
              onTap: _pickCategory,
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _desc,
            maxLines: 2,
            maxLength: 300,
            inputFormatters: [LengthLimitingTextInputFormatter(300)],
            decoration: _onbDec('Açıklama', hint: 'Kısa açıklama (opsiyonel)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              style: const TextStyle(color: WebeyColors.errorRed, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _submit,
              child: Text(widget.isEdit ? 'Kaydet' : 'Hizmeti ekle'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Uzman form modal ─────────────────────────────────────────────────────────

class _DurationChoiceField extends StatelessWidget {
  const _DurationChoiceField({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: _onbDec('Süre *'),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final option in _serviceDurationOptions)
            ChoiceChip(
              label: Text('$option dk'),
              selected: value == option,
              onSelected: (_) => onChanged(option),
              selectedColor: WebeyColors.primaryGold,
              backgroundColor: WebeyColors.softWhite,
              side: BorderSide(
                color: value == option
                    ? WebeyColors.primaryGold
                    : WebeyColors.borderSand,
              ),
              labelStyle: TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 12,
                fontWeight: value == option ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _StaffFormResult {
  const _StaffFormResult({required this.name, this.role, this.phone10});
  final String name;
  final String? role;
  final String? phone10; // 10 hane veya null
}

class _StaffFormSheet extends StatefulWidget {
  const _StaffFormSheet({
    required this.initialName,
    required this.initialRole,
    required this.initialPhone10,
    required this.isEdit,
  });
  final String initialName;
  final String initialRole;
  final String initialPhone10;
  final bool isEdit;

  @override
  State<_StaffFormSheet> createState() => _StaffFormSheetState();
}

class _StaffFormSheetState extends State<_StaffFormSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _role = TextEditingController(
    text: widget.initialRole,
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.initialPhone10,
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Ad Soyad zorunlu.');
      return;
    }
    if (name.length > 60) {
      setState(() => _error = 'Ad Soyad en fazla 60 karakter olabilir.');
      return;
    }
    final role = _role.text.trim();
    if (role.length > 80) {
      setState(() => _error = 'Rol en fazla 80 karakter olabilir.');
      return;
    }
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty && (digits.length != 10 || !digits.startsWith('5'))) {
      setState(() => _error = 'Telefon 5 ile başlayan 10 haneli olmalı.');
      return;
    }
    Navigator.of(context).pop(
      _StaffFormResult(
        name: name,
        role: role.isEmpty ? null : role,
        phone10: digits.isEmpty ? null : digits,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _onbSheetFrame(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: WebeyColors.borderSand,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.isEdit ? 'Uzmanı düzenle' : 'Yeni uzman',
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 17,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            maxLength: 60,
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
            decoration: _onbDec('Ad Soyad *', hint: 'Örn. Ece Yıldız'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _role,
            maxLength: 80,
            inputFormatters: [LengthLimitingTextInputFormatter(80)],
            decoration: _onbDec('Rol / Uzmanlık', hint: 'Örn. Nail Artist'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in _kStaffRoles)
                GestureDetector(
                  onTap: () => setState(() {
                    _role.text = r;
                    _error = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _role.text == r
                          ? WebeyColors.primaryGold
                          : WebeyColors.softWhite,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _role.text == r
                            ? WebeyColors.primaryGold
                            : WebeyColors.borderSand,
                        width: _role.text == r ? 1.25 : 1,
                      ),
                    ),
                    child: Text(
                      r,
                      style: TextStyle(
                        color: _role.text == r
                            ? WebeyColors.darkEspresso
                            : WebeyColors.darkEspresso,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: _onbDec(
              'Telefon (opsiyonel)',
              hint: '5XX XXX XX XX',
              prefixIcon: const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 8, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: Text(
                    '+90',
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              style: const TextStyle(color: WebeyColors.errorRed, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _submit,
              child: Text(widget.isEdit ? 'Kaydet' : 'Uzmanı ekle'),
            ),
          ),
        ],
      ),
    );
  }
}
