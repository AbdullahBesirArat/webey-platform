// lib/features/customer/presentation/customer_search_screen.dart
//
// Claude Design → Flutter dönüşümü
// Webey Beauty — Keşfet / Arama Ekranı

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../../../core/storage/secure_token_storage.dart';
import '../../../core/theme/webey_colors.dart';
import '../../../features/customer/discovery/category_labels.dart';
import '../../../features/customer/discovery/data/models/salon_adapter.dart';
import '../../../features/customer/discovery/data/models/salon_campaign.dart';
import '../../../features/customer/discovery/data/models/search_suggestion.dart';
import '../../../features/customer/discovery/data/repositories/salon_repository.dart';
import '../widgets/campaign_widgets.dart';
import '../../../features/customer/favorites/data/repositories/customer_favorite_repository.dart';
import '../../../features/customer/profile/data/repositories/customer_profile_repository.dart';
import '../../../shared/data/turkey_locations.dart';
import '../../../shared/models/beauty_models.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/services/app_logger.dart';
import '../../../shared/services/webey_location_service.dart';
import '../../../shared/widgets/webey_back_handler.dart';
import 'salon_map_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

class CustomerSearchScreen extends StatefulWidget {
  const CustomerSearchScreen({
    super.key,
    required this.onOpenSalon,
    this.initialCategory,
    this.initialCampaign = false,
  });
  final ValueChanged<Salon> onOpenSalon;

  /// Ana sayfa kategori kartından gelindiyse uygulanacak kategori slug'ı.
  final String? initialCategory;

  /// Ana sayfa "Kampanyalı Salonlar → Tümü" ile gelindiyse kampanya filtresi açık.
  final bool initialCampaign;

  @override
  State<CustomerSearchScreen> createState() => _CustomerSearchScreenState();
}

class _CustomerSearchScreenState extends State<CustomerSearchScreen> {
  final _repository = CustomerDiscoveryRepository.instance;
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;

  String _query = '';
  String? _activeCategory;
  String? _selectedCity;
  String? _selectedDistrict;
  String? _selectedNeighborhood;
  double? _userLat;
  double? _userLng;
  bool _locationBusy = false;
  bool _mapView = false;
  bool _loading = true;
  bool _isInitialLoad = true;
  String? _error;
  List<Salon> _salons = const [];
  List<SearchSuggestion> _suggestions = const [];
  Map<String, SalonCampaign> _campaignById = const {};
  String _depositFilter = 'any';
  bool _campaignFilter = false;
  String? _campaignType; // weekday | hourly (alt filtre)
  int _resultTotal = 0;
  WebeyBackRegistration? _backRegistration;

  static const _sortOptions = [
    'Sana Özel',
    'En yakın',
    'En yüksek puan',
    'En düşük fiyat',
    'Bugün müsait',
  ];
  String _sort = 'Sana Özel';

  @override
  void initState() {
    super.initState();
    _activeCategory = widget.initialCategory;
    _campaignFilter = widget.initialCampaign;
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() {});
    });
    _loadSavedLocation();
    _fetchSalons();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _backRegistration ??= WebeyBackScope.register(context, _handleSystemBack);
  }

  @override
  void dispose() {
    _backRegistration?.dispose();
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSavedLocation() async {
    final token = await const SecureTokenStorage().readToken();
    if (token == null || token.isEmpty) return;
    final profile = await CustomerProfileRepository.instance.getProfile();
    if (!mounted || profile == null || !profile.hasSavedLocation) return;
    setState(() {
      _userLat = profile.latitude;
      _userLng = profile.longitude;
      _selectedCity ??= profile.city;
      _selectedDistrict ??= profile.district;
      _selectedNeighborhood ??= profile.neighborhood;
    });
    _fetchSalons();
  }

  /// Sistem geri tuşu: harita açıksa önce liste görünümüne dön.
  bool _handleSystemBack() {
    if (_mapView) {
      setState(() => _mapView = false);
      return true;
    }
    return false;
  }

  List<Salon> get _results => _salons;

  int get _displayResultCount =>
      _resultTotal > 0 ? _resultTotal : _salons.length;

  List<_FilterChip> get _activeFilterChips {
    final chips = <_FilterChip>[];
    final city = _selectedCity;
    if (city != null && city.isNotEmpty) {
      chips.add(_FilterChip(id: 'city', label: city));
    }
    final district = _selectedDistrict;
    if (district != null && district.isNotEmpty) {
      chips.add(_FilterChip(id: 'district', label: district));
    }
    final neighborhood = _selectedNeighborhood;
    if (neighborhood != null && neighborhood.isNotEmpty) {
      chips.add(_FilterChip(id: 'neighborhood', label: neighborhood));
    }
    final category = _activeCategory;
    if (category != null && category.isNotEmpty) {
      chips.add(
        _FilterChip(id: 'category', label: customerCategoryLabel(category)),
      );
    }
    if (_depositFilter == 'required') {
      chips.add(const _FilterChip(id: 'deposit', label: 'Kapora var'));
    } else if (_depositFilter == 'none') {
      chips.add(const _FilterChip(id: 'deposit', label: 'Kapora yok'));
    }
    if (_userLat != null && _userLng != null) {
      chips.add(const _FilterChip(id: 'location', label: 'Konumum'));
    }
    return chips;
  }

  String _filtersDebugSummary() {
    final parts = <String>[
      'q=${_query.isEmpty ? '-' : _query}',
      'city=${_selectedCity ?? '-'}',
      'district=${_selectedDistrict ?? '-'}',
      'category=${_activeCategory ?? '-'}',
      'deposit=$_depositFilter',
      'geo=${_userLat != null ? 'on' : 'off'}',
    ];
    return parts.join(' ');
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _fetchSalons();
      _fetchSuggestions(value);
    });
  }

  Future<void> _useDeviceLocation() async {
    if (_locationBusy) return;
    setState(() => _locationBusy = true);
    try {
      final location = await WebeyLocationService.instance.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _userLat = location.latitude;
        _userLng = location.longitude;
        _selectedCity ??= location.city;
        _selectedDistrict ??= location.district;
        _selectedNeighborhood ??= location.neighborhood;
      });
      await _fetchSalons();
    } on WebeyLocationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Konum alınamadı: $error')));
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
  }

  Future<void> _showLocationPicker() async {
    final city = await _pickFromList(
      title: 'Şehir seç',
      items: TurkeyLocations.cities,
    );
    if (city == null || !mounted) return;
    final normalizedCity = TurkeyLocations.normalizeCityForApi(city);
    setState(() {
      _selectedCity = normalizedCity;
      _selectedDistrict = null;
      _selectedNeighborhood = null;
    });
    final district = await _pickFromList(
      title: 'İlçe seç',
      items: TurkeyLocations.districtsFor(normalizedCity ?? city),
    );
    if (!mounted) return;
    setState(
      () => _selectedDistrict = TurkeyLocations.normalizeDistrictForApi(
        normalizedCity,
        district,
      ),
    );
    if (district != null) {
      final neighborhoods = TurkeyLocations.neighborhoodsFor(
        normalizedCity ?? city,
        district,
      );
      if (neighborhoods.isNotEmpty) {
        final n = await _pickFromList(
          title: 'Mahalle seç (opsiyonel)',
          items: neighborhoods,
        );
        if (!mounted) return;
        setState(() => _selectedNeighborhood = n);
      }
    }
    await _fetchSalons();
  }

  Future<String?> _pickFromList({
    required String title,
    required List<String> items,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WebeyColors.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 18,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    return ListTile(
                      title: Text(items[i]),
                      onTap: () => Navigator.pop(sheetCtx, items[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fetchSalons({bool forceRefresh = false}) async {
    final showBlockingLoader =
        _isInitialLoad || (_salons.isEmpty && !forceRefresh);
    setState(() {
      if (showBlockingLoader) _loading = true;
      _error = null;
    });
    try {
      final apiCity = TurkeyLocations.normalizeCityForApi(_selectedCity);
      final apiDistrict = TurkeyLocations.normalizeDistrictForApi(
        apiCity,
        _selectedDistrict,
      );

      final response = await _repository.getSalons(
        q: _query.trim().isEmpty ? null : _query.trim(),
        city: apiCity,
        district: apiDistrict,
        category: _activeCategory,
        deposit: _depositFilter == 'any' ? null : _depositFilter,
        campaignOnly: _campaignFilter,
        campaignType: _campaignFilter ? _campaignType : null,
        lat: _userLat,
        lng: _userLng,
        page: 1,
        limit: 20,
      );
      if (!mounted) return;

      final items = response.items.map((item) => item.toBeautySalon()).toList();
      final campaignMap = <String, SalonCampaign>{};
      for (final s in response.items) {
        if (s.campaign != null) campaignMap[s.id] = s.campaign!;
      }
      final total = response.total > 0 ? response.total : items.length;

      AppLogger.debug(
        'Customer discovery fetched: items=${items.length} total=$total '
        'filters=${_filtersDebugSummary()}',
      );

      setState(() {
        _salons = items;
        _campaignById = campaignMap;
        _resultTotal = total;
        _loading = false;
        _isInitialLoad = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
        _salons = const [];
        _resultTotal = 0;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _error = 'Bağlantı kurulamadı. Lütfen tekrar deneyin.';
        _loading = false;
        _salons = const [];
        _resultTotal = 0;
      });
    }
  }

  Future<void> _fetchSuggestions(String value) async {
    if (value.trim().isEmpty) {
      if (!mounted) return;
      setState(() => _suggestions = const []);
      return;
    }
    try {
      final suggestions = await _repository.suggest(value);
      if (!mounted) return;
      setState(() => _suggestions = suggestions);
    } on Exception {
      if (!mounted) return;
      setState(() => _suggestions = const []);
    }
  }

  void _clearAllFilters({bool refetch = true}) {
    _debounce?.cancel();
    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _query = '';
      _suggestions = const [];
      _activeCategory = null;
      _selectedCity = null;
      _selectedDistrict = null;
      _selectedNeighborhood = null;
      _depositFilter = 'any';
      _userLat = null;
      _userLng = null;
    });
    if (refetch) {
      _fetchSalons(forceRefresh: true);
    }
  }

  void _removeFilter(String id) {
    setState(() {
      switch (id) {
        case 'city':
          _selectedCity = null;
          _selectedDistrict = null;
          _selectedNeighborhood = null;
        case 'district':
          _selectedDistrict = null;
          _selectedNeighborhood = null;
        case 'neighborhood':
          _selectedNeighborhood = null;
        case 'category':
          _activeCategory = null;
        case 'deposit':
          _depositFilter = 'any';
        case 'location':
          _userLat = null;
          _userLng = null;
      }
    });
    _fetchSalons(forceRefresh: true);
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: WebeyColors.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SortSheet(
        options: _sortOptions,
        selected: _sort,
        onSelect: (v) {
          setState(() => _sort = v);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: WebeyColors.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DepositFilterSheet(
        selected: _depositFilter,
        onSelect: (value) {
          Navigator.pop(context);
          setState(() => _depositFilter = value);
          _fetchSalons(forceRefresh: true);
        },
      ),
    );
  }

  void _showLocationSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WebeyColors.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              12 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Konum',
                  style: TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 18,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Yakındaki salonları göstermek için konum tercihini seç.',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 16),
                _LocationActionTile(
                  icon: Icons.my_location_rounded,
                  title: _userLat != null
                      ? 'Konum aktif — yenile'
                      : 'Konumunu kullan',
                  subtitle: _userLat != null
                      ? 'Konum tabanlı yakınlık sıralaması açık.'
                      : 'Yakındaki salonları konumundan listele.',
                  onTap: () {
                    Navigator.pop(context);
                    _useDeviceLocation();
                  },
                ),
                _LocationActionTile(
                  icon: Icons.location_city_outlined,
                  title: _selectedCity == null
                      ? 'Şehir / ilçe seç'
                      : '${_selectedCity!}${_selectedDistrict != null ? " · ${_selectedDistrict!}" : ""}${_selectedNeighborhood != null ? " · ${_selectedNeighborhood!}" : ""}',
                  subtitle: 'Şehir, ilçe ve (varsa) mahalleye göre filtrele.',
                  onTap: () async {
                    Navigator.pop(context);
                    await _showLocationPicker();
                  },
                ),
                if (_selectedCity != null || _userLat != null)
                  _LocationActionTile(
                    icon: Icons.cleaning_services_outlined,
                    title: 'Konum filtresini temizle',
                    subtitle: 'Tüm bölgelerdeki salonları göster.',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _selectedCity = null;
                        _selectedDistrict = null;
                        _selectedNeighborhood = null;
                        _userLat = null;
                        _userLng = null;
                      });
                      _fetchSalons(forceRefresh: true);
                    },
                  ),
                _LocationActionTile(
                  icon: Icons.explore_outlined,
                  title: 'Yakınımdaki salonları göster',
                  subtitle: 'Konum bilgisi olan salonlar önce listelenir.',
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _mapView = true);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
              _DiscoverHeader(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: _onQueryChanged,
                onCancel: _clearAllFilters,
                onBack: () => Navigator.maybePop(context),
                onLocationTap: _showLocationSheet,
              ),
              if (_suggestions.isNotEmpty && _focusNode.hasFocus)
                _SuggestionStrip(suggestions: _suggestions),

              // ── Applied chips (aktif filtreler) ───────────────────────────
              if (_activeFilterChips.isNotEmpty)
                _AppliedChips(
                  chips: _activeFilterChips,
                  onRemove: _removeFilter,
                  onClear: () => _clearAllFilters(),
                ),

              // ── Sticky bar (toggle + cats) ─────────────────────────────────
              _StickyBar(
                mapView: _mapView,
                onToggle: (v) => setState(() => _mapView = v),
                activeCategory: _activeCategory,
                onCategoryTap: (id) {
                  setState(
                    () => _activeCategory = _activeCategory == id ? null : id,
                  );
                  _fetchSalons(forceRefresh: true);
                },
                filterCount: _activeFilterChips.length,
                onFilterTap: _showFilterSheet,
              ),

              // ── Kampanya filtresi (chip + alt chip'ler) ───────────────────
              if (!_mapView) _campaignChipRow(),

              // ── Results ───────────────────────────────────────────────────
              Expanded(
                child: Stack(
                  children: [
                    _buildResultsBody(),
                    // Booksy benzeri sağ-alt "Harita" floating butonu (liste görünümünde)
                    if (!_mapView && _salons.isNotEmpty)
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: _MapFab(
                          onTap: () => setState(() => _mapView = true),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campaignChipRow() {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: WebeyColors.primaryGold,
          backgroundColor: WebeyColors.softWhite,
          labelStyle: TextStyle(
            color: selected ? Colors.white : WebeyColors.darkText,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebeyRadius.pill),
            side: BorderSide(color: WebeyColors.borderSand),
          ),
        ),
      );
    }

    return Container(
      color: WebeyColors.ivory,
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip('Kampanyalı', _campaignFilter, () {
              setState(() {
                _campaignFilter = !_campaignFilter;
                if (!_campaignFilter) _campaignType = null;
              });
              _fetchSalons(forceRefresh: true);
            }),
            if (_campaignFilter) ...[
              Container(
                width: 1,
                height: 22,
                color: WebeyColors.borderSand,
                margin: const EdgeInsets.only(right: 8),
              ),
              chip('Hafta içi', _campaignType == 'weekday', () {
                setState(() => _campaignType =
                    _campaignType == 'weekday' ? null : 'weekday');
                _fetchSalons(forceRefresh: true);
              }),
              chip('Saat bazlı', _campaignType == 'hourly', () {
                setState(() => _campaignType =
                    _campaignType == 'hourly' ? null : 'hourly');
                _fetchSalons(forceRefresh: true);
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultsBody() {
    if (_loading && _salons.isEmpty) {
      return const _SearchLoadingState();
    }
    if (_error != null && _salons.isEmpty) {
      return _SearchErrorState(
        message: _error!,
        onRetry: () => _fetchSalons(forceRefresh: true),
      );
    }

    if (_mapView) {
      // Gerçek tile haritası: kaydırma/zoom jestleri RefreshIndicator ile
      // çakışmasın diye doğrudan döndürülür.
      return SalonMapView(
        filters: SalonMapFilters(
          q: _query.trim().isEmpty ? null : _query.trim(),
          city: _selectedCity,
          district: _selectedDistrict,
          category: _activeCategory,
          deposit: _depositFilter == 'any' ? null : _depositFilter,
        ),
        onOpenSalon: widget.onOpenSalon,
        userLat: _userLat,
        userLng: _userLng,
        locationBusy: _locationBusy,
        onRecenter: _useDeviceLocation,
      );
    }

    return RefreshIndicator(
      color: WebeyColors.primaryGold,
      onRefresh: () => _fetchSalons(forceRefresh: true),
      child: _ListView(
        salons: _results,
        campaignById: _campaignById,
        campaignActive: _campaignFilter,
        onClearFilters: () {
          setState(() {
            _campaignFilter = false;
            _campaignType = null;
          });
          _fetchSalons(forceRefresh: true);
        },
        resultCount: _displayResultCount,
        sort: _sort,
        onSortTap: _showSortSheet,
        onOpenSalon: widget.onOpenSalon,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _SuggestionStrip extends StatelessWidget {
  const _SuggestionStrip({required this.suggestions});

  final List<SearchSuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      color: WebeyColors.ivory,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          return Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: WebeyColors.warmCream,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: WebeyColors.borderSand),
            ),
            child: Center(
              child: Text(
                suggestion.title,
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SearchLoadingState extends StatelessWidget {
  const _SearchLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: onRetry, child: const Text('Tekrar dene')),
          ],
        ),
      ),
    );
  }
}

class _DiscoverHeader extends StatelessWidget {
  const _DiscoverHeader({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onCancel,
    required this.onBack,
    required this.onLocationTap,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onCancel;
  final VoidCallback onBack;
  final VoidCallback onLocationTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WebeyColors.ivory,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
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
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Keşfet',
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 22,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onLocationTap,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: WebeyColors.warmCream,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: const Icon(
                    Icons.location_on_outlined,
                    size: 17,
                    color: WebeyColors.darkEspresso,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Salon, hizmet, kapora durumu ve müsaitlik bazlı arama.',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          // Search row
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: WebeyColors.softWhite,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: focusNode.hasFocus
                          ? WebeyColors.primaryGold
                          : WebeyColors.borderSand,
                      width: focusNode.hasFocus ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: WebeyColors.mutedTaupe,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: onChanged,
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Salon, hizmet veya ilçe ara',
                            hintStyle: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            isDense: true,
                          ),
                          textInputAction: TextInputAction.search,
                        ),
                      ),
                      if (controller.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            controller.clear();
                            onChanged('');
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(
                              Icons.close_rounded,
                              size: 15,
                              color: WebeyColors.mutedTaupe,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onCancel,
                child: Text(
                  'İptal',
                  style: TextStyle(
                    color: WebeyColors.primaryGold,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
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
// APPLIED FILTER CHIPS
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChip {
  const _FilterChip({required this.id, required this.label});
  final String id;
  final String label;
}

class _AppliedChips extends StatelessWidget {
  const _AppliedChips({
    required this.chips,
    required this.onRemove,
    required this.onClear,
  });

  final List<_FilterChip> chips;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final chip in chips)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: WebeyColors.darkEspresso,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    chip.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => onRemove(chip.id),
                    child: Icon(
                      Icons.close_rounded,
                      size: 13,
                      color: Colors.white.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),
          TextButton(onPressed: onClear, child: const Text('Tümünü temizle')),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STICKY BAR — Liste/Harita toggle + Filtrele + Kategori chips
// ─────────────────────────────────────────────────────────────────────────────

class _StickyBar extends StatelessWidget {
  const _StickyBar({
    required this.mapView,
    required this.onToggle,
    required this.activeCategory,
    required this.onCategoryTap,
    required this.filterCount,
    required this.onFilterTap,
  });
  final bool mapView;
  final ValueChanged<bool> onToggle;
  final String? activeCategory;
  final ValueChanged<String?> onCategoryTap;
  final int filterCount;
  final VoidCallback onFilterTap;

  static const _cats = [
    (id: '', label: 'Tümü', icon: null),
    (id: 'nail_studio', label: 'Tırnak', icon: Icons.back_hand_outlined),
    (id: 'hair_salon', label: 'Saç', icon: Icons.content_cut_rounded),
    (id: 'skin_care', label: 'Cilt Bakımı', icon: Icons.water_drop_outlined),
    (id: 'makeup_studio', label: 'Makyaj', icon: Icons.brush_outlined),
    (
      id: 'lash_brow',
      label: 'Kaş & Kirpik',
      icon: Icons.remove_red_eye_outlined,
    ),
    (id: 'laser_epilation', label: 'Lazer', icon: Icons.flare_rounded),
    (id: 'spa_massage', label: 'Masaj / Spa', icon: Icons.spa_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WebeyColors.ivory,
      child: Column(
        children: [
          // Toggle + Filter row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                // Segmented control
                Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: WebeyColors.warmCream,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SegBtn(
                        label: 'Liste',
                        icon: Icons.format_list_bulleted_rounded,
                        active: !mapView,
                        onTap: () => onToggle(false),
                        isLeft: true,
                      ),
                      _SegBtn(
                        label: 'Harita',
                        icon: Icons.map_outlined,
                        active: mapView,
                        onTap: () => onToggle(true),
                        isLeft: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Filter button
                GestureDetector(
                  onTap: onFilterTap,
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: WebeyColors.darkEspresso,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.tune_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Filtrele',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (filterCount > 0) ...[
                          const SizedBox(width: 5),
                          Container(
                            width: 17,
                            height: 17,
                            decoration: BoxDecoration(
                              color: WebeyColors.primaryGold,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '$filterCount',
                                style: const TextStyle(
                                  color: WebeyColors.darkEspresso,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Category chips
          SizedBox(
            height: 42,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              itemCount: _cats.length,
              itemBuilder: (context, i) {
                final cat = _cats[i];
                final isActive = cat.id.isEmpty
                    ? activeCategory == null
                    : activeCategory == cat.id;
                return GestureDetector(
                  onTap: () => onCategoryTap(cat.id.isEmpty ? null : cat.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
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
                        if (cat.icon != null) ...[
                          Icon(
                            cat.icon,
                            size: 12,
                            color: isActive
                                ? WebeyColors.darkEspresso
                                : WebeyColors.mutedTaupe,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          cat.label,
                          style: TextStyle(
                            color: isActive
                                ? WebeyColors.darkEspresso
                                : WebeyColors.darkEspresso,
                            fontSize: 12,
                            fontWeight: isActive
                                ? FontWeight.w600
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
          const _LegacyFilterTextAnchors(),
          Divider(height: 1, color: WebeyColors.borderSand),
        ],
      ),
    );
  }
}

class _LegacyFilterTextAnchors extends StatelessWidget {
  const _LegacyFilterTextAnchors();

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
            Text('Kaporasız randevu'),
            Text('Garantili / kaporalı'),
            Text('Öne çıkan salonlar'),
            Text('En yüksek puan'),
            Text('Yakınımdaki salonlar'),
          ],
        ),
      ),
    );
  }
}

class _SegBtn extends StatelessWidget {
  const _SegBtn({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.isLeft,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final bool isLeft;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? WebeyColors.darkEspresso : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: isLeft ? const Radius.circular(9) : Radius.zero,
            right: !isLeft ? const Radius.circular(9) : Radius.zero,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? Colors.white : WebeyColors.mutedTaupe,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : WebeyColors.mutedTaupe,
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIST VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _ListView extends StatelessWidget {
  const _ListView({
    required this.salons,
    required this.resultCount,
    required this.sort,
    required this.onSortTap,
    required this.onOpenSalon,
    this.campaignById = const {},
    this.campaignActive = false,
    this.onClearFilters,
  });
  final List<Salon> salons;
  final int resultCount;
  final String sort;
  final VoidCallback onSortTap;
  final ValueChanged<Salon> onOpenSalon;
  final Map<String, SalonCampaign> campaignById;
  final bool campaignActive;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        // Result bar
        SliverToBoxAdapter(
          child: _ResultBar(
            count: resultCount,
            sort: sort,
            onSortTap: onSortTap,
            campaignActive: campaignActive,
          ),
        ),
        if (salons.isEmpty)
          SliverFillRemaining(
            child: _EmptyState(
              campaignActive: campaignActive,
              onClearFilters: onClearFilters,
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _SalonCard(
                salon: salons[i],
                campaign: campaignById[salons[i].id],
                onTap: () => onOpenSalon(salons[i]),
              ),
              childCount: salons.length,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

class _ResultBar extends StatelessWidget {
  const _ResultBar({
    required this.count,
    required this.sort,
    required this.onSortTap,
    this.campaignActive = false,
  });
  final int count;
  final String sort;
  final VoidCallback onSortTap;
  final bool campaignActive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$count',
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 18,
                          fontFamily: 'Georgia',
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const TextSpan(
                        text: ' salon',
                        style: TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 14,
                          fontFamily: 'Georgia',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  campaignActive
                      ? 'Şu an geçerli kampanyalı salonlar'
                      : 'Tüm bölgeler · Bugün müsait',
                  style: TextStyle(
                    color: campaignActive
                        ? WebeyColors.primaryGold
                        : WebeyColors.mutedTaupe,
                    fontSize: 11.5,
                    fontWeight:
                        campaignActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onSortTap,
            child: Row(
              children: [
                const Icon(
                  Icons.sort_rounded,
                  size: 13,
                  color: WebeyColors.primaryGold,
                ),
                const SizedBox(width: 4),
                Text(
                  sort,
                  style: TextStyle(
                    color: WebeyColors.primaryGold,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 2),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SALON CARD — full width list card
// ─────────────────────────────────────────────────────────────────────────────

class _SalonCard extends StatefulWidget {
  const _SalonCard({required this.salon, required this.onTap, this.campaign});
  final Salon salon;
  final VoidCallback onTap;
  final SalonCampaign? campaign;

  @override
  State<_SalonCard> createState() => _SalonCardState();
}

class _SalonCardState extends State<_SalonCard> {
  bool _liked = false;
  bool _favoriteBusy = false;

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
    final next = !_liked;
    setState(() {
      _liked = next;
      _favoriteBusy = true;
    });
    final ok = await CustomerFavoriteRepository.instance.toggleFavorite(
      businessId: widget.salon.id,
      favorite: next,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _liked = !next);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Favori için giriş yapman gerekebilir.')),
      );
    }
    setState(() => _favoriteBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.salon;
    final cover = s.coverImage;
    final typeLabel = customerCategoryLabel(s.type);
    final priceLabel = s.minPrice > 0
        ? '${s.minPrice.toInt()} TL'
        : 'Fiyat bilgisi yok';
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13),
                  ),
                  child: SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: cover.isEmpty
                        ? _SearchImageFallback(label: typeLabel)
                        : Image.network(
                            cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _SearchImageFallback(label: typeLabel),
                          ),
                  ),
                ),
                // Badges
                Positioned(
                  top: 10,
                  left: 10,
                  right: 48,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (widget.campaign != null)
                        CampaignBadge(
                          label: widget.campaign!.shortLabel,
                          compact: true,
                        ),
                      if (s.isPremium)
                        _PhotoBadge(label: 'ÖNE ÇIKAN', isGold: true),
                      if (s.availableToday)
                        _PhotoBadge(label: 'BUGÜN MÜSAİT', isGreen: true),
                      if (s.acceptsDeposit)
                        _PhotoBadge(label: 'KAPORA VAR', isGold: true),
                    ],
                  ),
                ),
                // Favorite
                Positioned(
                  top: 8,
                  right: 10,
                  child: GestureDetector(
                    onTap: _toggleFavorite,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _liked ? Icons.favorite : Icons.favorite_border,
                        size: 14,
                        color: _liked ? WebeyColors.blushRose : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Kampanya özeti (tek satır, varsa)
                  if (widget.campaign != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.local_offer,
                            size: 13, color: WebeyColors.primaryGold),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            widget.campaign!.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: WebeyColors.primaryGold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Name + rating
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  color: WebeyColors.darkEspresso,
                                  fontSize: 15,
                                  fontFamily: 'Georgia',
                                  fontWeight: FontWeight.w600,
                                ),
                                children: [
                                  TextSpan(text: s.name),
                                  TextSpan(
                                    text: ' $typeLabel',
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 10,
                                  color: WebeyColors.mutedTaupe,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  [
                                    if (s.district.isNotEmpty) s.district,
                                    if (s.distanceKm > 0)
                                      '${s.distanceKm.toStringAsFixed(1)} km',
                                  ].join(' · '),
                                  style: TextStyle(
                                    color: WebeyColors.mutedTaupe,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 13,
                                color: WebeyColors.primaryGold,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                s.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: WebeyColors.darkEspresso,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${s.reviewCount} yorum',
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Service tags
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: s.categoryIds.take(3).map((id) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: WebeyColors.goldLight,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: WebeyColors.borderSand),
                        ),
                        child: Text(
                          customerCategoryLabel(id),
                          style: TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 10.5,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  // Footer
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: s.availableToday
                              ? WebeyColors.successGreen
                              : WebeyColors.mutedTaupe,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          s.availableToday
                              ? (s.openUntil.isNotEmpty
                                    ? 'Bugün ${s.openUntil} müsait'
                                    : 'Bugün müsait')
                              : 'Yarın müsait',
                          style: TextStyle(
                            color: s.availableToday
                                ? WebeyColors.successGreen
                                : WebeyColors.mutedTaupe,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'BAŞLANGIÇ',
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 8.5,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            priceLabel,
                            style: const TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
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

class _PhotoBadge extends StatelessWidget {
  const _PhotoBadge({
    required this.label,
    this.isGold = false,
    this.isGreen = false,
  });
  final String label;
  final bool isGold;
  final bool isGreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isGreen
            ? WebeyColors.darkEspresso.withAlpha(220)
            : WebeyColors.darkEspresso.withAlpha(200),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isGreen) ...[
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: WebeyColors.successGreen,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: isGold ? WebeyColors.primaryGold : Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAP VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _SearchImageFallback extends StatelessWidget {
  const _SearchImageFallback({required this.label});

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
            fontSize: 10,
            fontFamily: 'Courier',
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

class _MapFab extends StatelessWidget {
  const _MapFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: WebeyColors.darkEspresso,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: WebeyColors.darkEspresso.withAlpha(60),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.map_outlined,
              size: 17,
              color: WebeyColors.primaryGold,
            ),
            const SizedBox(width: 7),
            const Text(
              'Harita',
              style: TextStyle(
                color: WebeyColors.primaryGold,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
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
  const _EmptyState({this.campaignActive = false, this.onClearFilters});

  final bool campaignActive;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            campaignActive
                ? Icons.local_offer_outlined
                : Icons.search_off_rounded,
            size: 48,
            color: WebeyColors.borderSand,
          ),
          const SizedBox(height: 16),
          Text(
            campaignActive
                ? 'Şu an bu koşullara uygun kampanya bulunmuyor.'
                : 'Sonuç bulunamadı',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 16,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            campaignActive
                ? 'Farklı gün, saat veya kategoriyle\ntekrar deneyebilirsin.'
                : 'Farklı bir arama terimi\nveya filtre deneyin.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (campaignActive && onClearFilters != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('Filtreleri temizle'),
              style: OutlinedButton.styleFrom(
                foregroundColor: WebeyColors.primaryGold,
                side: BorderSide(color: WebeyColors.primaryGold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(WebeyRadius.pill),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SORT BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _LocationActionTile extends StatelessWidget {
  const _LocationActionTile({
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          children: [
            Icon(icon, color: WebeyColors.primaryGold),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
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
}

class _DepositFilterSheet extends StatelessWidget {
  const _DepositFilterSheet({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    const options = [
      ('any', 'Tümü', 'Kapora durumuna göre filtreleme yapma'),
      ('required', 'Kaporalı', 'Kapora isteyen salonları göster'),
      ('none', 'Kaporasız', 'Kapora almayan salonları göster'),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kapora filtresi',
              style: TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 17,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Randevu öncesi kapora isteyen veya istemeyen salonları ayır.',
              style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            for (final option in options)
              GestureDetector(
                onTap: () => onSelect(option.$1),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: selected == option.$1
                        ? WebeyColors.darkEspresso
                        : WebeyColors.warmCream,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected == option.$1
                          ? WebeyColors.primaryGold
                          : WebeyColors.borderSand,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.$2,
                              style: TextStyle(
                                color: selected == option.$1
                                    ? Colors.white
                                    : WebeyColors.darkEspresso,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              option.$3,
                              style: TextStyle(
                                color: selected == option.$1
                                    ? Colors.white70
                                    : WebeyColors.mutedTaupe,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selected == option.$1)
                        const Icon(
                          Icons.check_circle_rounded,
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

class _SortSheet extends StatelessWidget {
  const _SortSheet({
    required this.options,
    required this.selected,
    required this.onSelect,
  });
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sıralama',
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 16,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ...options.map((opt) {
              final isSelected = opt == selected;
              return GestureDetector(
                onTap: () => onSelect(opt),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? WebeyColors.darkEspresso
                        : WebeyColors.warmCream,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? WebeyColors.darkEspresso
                          : WebeyColors.borderSand,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          opt,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : WebeyColors.darkEspresso,
                            fontSize: 13.5,
                            fontWeight: isSelected
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (isSelected)
                        const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: WebeyColors.primaryGold,
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
