// lib/features/business/presentation/business_location_settings_screen.dart
//
// "Salon Konumu" ayar sayfası: salon sahibi mevcut harita konumunu görür,
// haritada düzenler ve kaydeder. Customer haritası bu koordinatı kullanır.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/theme/webey_colors.dart';
import '../../../shared/widgets/webey_toast.dart';
import '../data/repositories/business_repository.dart';
import 'business_location_picker.dart';

class BusinessLocationSettingsScreen extends StatefulWidget {
  const BusinessLocationSettingsScreen({super.key});

  @override
  State<BusinessLocationSettingsScreen> createState() =>
      _BusinessLocationSettingsScreenState();
}

class _BusinessLocationSettingsScreenState
    extends State<BusinessLocationSettingsScreen> {
  final _repository = BusinessRepository.instance;

  Map<String, dynamic> _profile = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  double? _lat;
  double? _lng;
  bool _dirty = false;

  bool get _hasLocation => _lat != null && _lng != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static double? _coordOrNull(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (parsed == null) return null;
    if (parsed.abs() < 0.0001) return null;
    return parsed;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _repository.getBusinessProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _lat = _coordOrNull(profile['latitude']);
        _lng = _coordOrNull(profile['longitude']);
        _dirty = false;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Konum bilgisi yüklenemedi. Lütfen tekrar deneyin.';
        _loading = false;
      });
    }
  }

  Future<void> _openPicker() async {
    final picked = await Navigator.of(context).push<BusinessLocationPickResult>(
      MaterialPageRoute(
        builder: (_) => BusinessLocationPickerScreen(
          initialLatitude: _lat,
          initialLongitude: _lng,
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _lat = picked.latitude;
        _lng = picked.longitude;
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !_hasLocation) return;
    setState(() => _saving = true);
    try {
      final updated = await _repository.saveBusinessProfile({
        ..._profile,
        'latitude': _lat,
        'longitude': _lng,
      });
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _lat = _coordOrNull(updated['latitude']) ?? _lat;
        _lng = _coordOrNull(updated['longitude']) ?? _lng;
        _dirty = false;
        _saving = false;
      });
      WebeyToast.success(context, 'Salon konumu kaydedildi.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      WebeyToast.error(context, 'Salon konumu kaydedilemedi.');
    }
  }

  String get _addressSummary {
    final parts = <String>[
      for (final key in ['neighborhood', 'district', 'city'])
        if ((_profile[key]?.toString() ?? '').isNotEmpty)
          _profile[key].toString(),
    ];
    return parts.join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      appBar: AppBar(
        backgroundColor: WebeyColors.ivory,
        elevation: 0,
        foregroundColor: WebeyColors.darkEspresso,
        title: const Text(
          'Salon Konumu',
          style: TextStyle(
            color: WebeyColors.darkEspresso,
            fontSize: 16,
            fontFamily: 'Georgia',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: WebeyColors.primaryGold),
            )
          : _error != null
          ? _ErrorBody(message: _error!, onRetry: _load)
          : _body(),
    );
  }

  Widget _body() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Açıklama kartı ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: WebeyColors.warmCream,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: WebeyColors.borderSand),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.travel_explore_rounded,
                  size: 20,
                  color: WebeyColors.primaryGold,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Müşterileriniz sizi haritada bu konuma göre bulur. '
                    'Konumunuzu doğru seçmeniz randevu alımlarını artırır.',
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Mevcut konum kartı ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: WebeyColors.softWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hasLocation
                    ? WebeyColors.successGreen.withAlpha(120)
                    : WebeyColors.errorRed.withAlpha(90),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _hasLocation
                          ? Icons.where_to_vote_rounded
                          : Icons.location_off_outlined,
                      size: 19,
                      color: _hasLocation
                          ? WebeyColors.successGreen
                          : WebeyColors.errorRed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _hasLocation
                            ? (_dirty
                                  ? 'Yeni konum seçildi (kaydedilmedi)'
                                  : 'Konum kayıtlı')
                            : 'Konum bilgisi eksik',
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_hasLocation) ...[
                  if (_addressSummary.isNotEmpty)
                    Text(
                      _addressSummary,
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 12.5,
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    'Koordinat: ${_lat!.toStringAsFixed(6)}, '
                    '${_lng!.toStringAsFixed(6)}',
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 10.5,
                    ),
                  ),
                ] else
                  const Text(
                    'Salonunuz müşteri haritasında görünmeyebilir. '
                    'Haritada konum seçerek müşterilerinizin sizi bulmasını '
                    'sağlayın.',
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Harita önizleme ──────────────────────────────────────────
          if (_hasLocation)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 190,
                child: Stack(
                  children: [
                    FlutterMap(
                      // Önizleme: etkileşimsiz; düzenleme picker'da yapılır.
                      options: MapOptions(
                        initialCenter: LatLng(_lat!, _lng!),
                        initialZoom: 15.5,
                        backgroundColor: const Color(0xFFF4F1EA),
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                          subdomains: const ['a', 'b', 'c', 'd'],
                          userAgentPackageName: 'tr.com.webey.business',
                          maxZoom: 19,
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(_lat!, _lng!),
                              width: 34,
                              height: 34,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: WebeyColors.primaryGold,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(60),
                                      blurRadius: 7,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.storefront_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      left: 6,
                      bottom: 4,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(170),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '© OpenStreetMap katkıcıları © CARTO',
                            style: TextStyle(
                              fontSize: 8.5,
                              color: Color(0xFF6B6B6B),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Önizlemeye dokununca da picker açılsın.
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(onTap: _openPicker),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.map_outlined,
                      size: 34,
                      color: WebeyColors.borderSand,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Henüz konum seçilmedi',
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // ── Butonlar ─────────────────────────────────────────────────
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: WebeyColors.darkEspresso,
                side: const BorderSide(color: WebeyColors.primaryGold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _saving ? null : _openPicker,
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(
                _hasLocation ? 'Haritada düzenle' : 'Haritada konum seç',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: WebeyColors.darkEspresso,
                foregroundColor: WebeyColors.primaryGold,
                elevation: 0,
                disabledBackgroundColor: WebeyColors.darkEspresso.withAlpha(80),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: (_hasLocation && _dirty && !_saving) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: WebeyColors.primaryGold,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(
                _saving ? 'Kaydediliyor…' : 'Konumu kaydet',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (_hasLocation && !_dirty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Konumu değiştirmek için haritada düzenleyin; '
                'değişiklik sonrası kaydetmeyi unutmayın.',
                textAlign: TextAlign.center,
                style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

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
            const Icon(
              Icons.wifi_off_rounded,
              size: 36,
              color: WebeyColors.borderSand,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: WebeyColors.darkEspresso,
                foregroundColor: WebeyColors.primaryGold,
              ),
              onPressed: onRetry,
              child: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
    );
  }
}
