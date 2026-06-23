// lib/features/customer/presentation/salon_map_view.dart
//
// Webey Beauty — Keşfet harita görünümü (Booksy benzeri).
// flutter_map + OpenStreetMap/CARTO açık tema tile'ları.
// Grid tabanlı clustering: düşük zoom'da gri sayı balonları,
// yüksek zoom'da tek tek salon pinleri. Pin tıklayınca alt önizleme kartı.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/theme/webey_colors.dart';
import '../../../shared/models/beauty_models.dart';
import '../../../shared/services/app_logger.dart';
import '../discovery/data/models/salon_adapter.dart';
import '../discovery/data/models/salon_summary.dart';
import '../discovery/data/repositories/salon_repository.dart';

/// Harita görünümünün üst ekrandan aldığı aktif filtre seti.
class SalonMapFilters {
  const SalonMapFilters({
    this.q,
    this.city,
    this.district,
    this.category,
    this.deposit,
  });

  final String? q;
  final String? city;
  final String? district;
  final String? category;
  final String? deposit;

  @override
  bool operator ==(Object other) {
    return other is SalonMapFilters &&
        other.q == q &&
        other.city == city &&
        other.district == district &&
        other.category == category &&
        other.deposit == deposit;
  }

  @override
  int get hashCode => Object.hash(q, city, district, category, deposit);
}

class SalonMapView extends StatefulWidget {
  const SalonMapView({
    super.key,
    required this.filters,
    required this.onOpenSalon,
    required this.userLat,
    required this.userLng,
    required this.locationBusy,
    required this.onRecenter,
  });

  final SalonMapFilters filters;
  final ValueChanged<Salon> onOpenSalon;
  final double? userLat;
  final double? userLng;
  final bool locationBusy;
  final Future<void> Function() onRecenter;

  @override
  State<SalonMapView> createState() => _SalonMapViewState();
}

class _SalonMapViewState extends State<SalonMapView> {
  static const _istanbulCenter = LatLng(41.0151, 29.0245); // Üsküdar civarı
  static const _initialZoom = 11.5;
  static const _clusterCellPx = 90.0;
  static const _noClusterZoom = 16.0;

  final _repository = CustomerDiscoveryRepository.instance;
  final _mapController = MapController();

  List<SalonSummary> _mapSalons = const [];
  bool _loading = true;
  bool _loadFailed = false;
  String? _selectedId;
  double _zoom = _initialZoom;
  Timer? _boundsDebounce;
  bool _didInitialFit = false;

  @override
  void initState() {
    super.initState();
    _fetch(initial: true);
  }

  @override
  void didUpdateWidget(SalonMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filters != widget.filters) {
      _fetch();
    }
    final lat = widget.userLat;
    final lng = widget.userLng;
    if (lat != null && lng != null && oldWidget.userLat != lat) {
      try {
        _mapController.move(LatLng(lat, lng), math.max(_zoom, 13.5));
      } catch (error) {
        AppLogger.debug('[map] move skipped: $error');
      }
    }
  }

  @override
  void dispose() {
    _boundsDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool initial = false, LatLngBounds? bounds}) async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final items = await _repository.getSalonsForMap(
        q: widget.filters.q,
        city: widget.filters.city,
        district: widget.filters.district,
        category: widget.filters.category,
        deposit: widget.filters.deposit,
        lat: widget.userLat,
        lng: widget.userLng,
        north: bounds?.north,
        south: bounds?.south,
        east: bounds?.east,
        west: bounds?.west,
      );
      if (!mounted) return;
      AppLogger.debug('[map] view=map fetch ok markers=${items.length}');
      setState(() {
        _mapSalons = items;
        _loading = false;
      });
      if (initial && !_didInitialFit) {
        _didInitialFit = true;
        _fitToContent(items);
      }
    } catch (error) {
      AppLogger.debug('[map] view=map fetch failed: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = _mapSalons.isEmpty;
      });
    }
  }

  void _fitToContent(List<SalonSummary> items) {
    // Harita henüz render edilmeden controller kullanılırsa exception atar;
    // ilk frame'den önce dönen hızlı yanıtlar için sessizce yut.
    try {
      final lat = widget.userLat;
      final lng = widget.userLng;
      if (lat != null && lng != null) {
        _mapController.move(LatLng(lat, lng), 13.5);
        return;
      }
      if (items.isEmpty) return;
      if (items.length == 1) {
        _mapController.move(
          LatLng(items.first.latitude!, items.first.longitude!),
          14,
        );
        return;
      }
      final bounds = LatLngBounds.fromPoints([
        for (final s in items) LatLng(s.latitude!, s.longitude!),
      ]);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(56)),
      );
    } catch (error) {
      AppLogger.debug('[map] fitToContent skipped: $error');
    }
  }

  void _onMapEvent(MapEvent event) {
    final newZoom = event.camera.zoom;
    if ((newZoom - _zoom).abs() > 0.01) {
      setState(() => _zoom = newZoom);
    }
    if (event is MapEventMoveEnd ||
        event is MapEventFlingAnimationEnd ||
        event is MapEventDoubleTapZoomEnd) {
      _boundsDebounce?.cancel();
      _boundsDebounce = Timer(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        // Görünür alanın biraz genişletilmişini iste; küçük kaydırmalarda
        // pinler aniden kaybolmasın.
        final visible = _mapController.camera.visibleBounds;
        final latPad = (visible.north - visible.south).abs() * 0.5;
        final lngPad = (visible.east - visible.west).abs() * 0.5;
        final expanded = LatLngBounds(
          LatLng(visible.south - latPad, visible.west - lngPad),
          LatLng(visible.north + latPad, visible.east + lngPad),
        );
        _fetch(bounds: expanded);
      });
    }
  }

  // ── Clustering ──────────────────────────────────────────────────────────
  List<_MapEntity> _buildEntities() {
    final salons = _mapSalons;
    if (salons.isEmpty) return const [];
    if (_zoom >= _noClusterZoom) {
      return [for (final s in salons) _MapEntity.single(s)];
    }

    // Web Mercator piksel uzayında grid hücrelerine grupla.
    final worldPx = 256.0 * math.pow(2, _zoom).toDouble();
    final cells = <String, List<SalonSummary>>{};
    for (final s in salons) {
      final x = (s.longitude! + 180.0) / 360.0 * worldPx;
      final sinLat = math
          .sin(s.latitude! * math.pi / 180.0)
          .clamp(-0.9999, 0.9999);
      final y =
          (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) *
          worldPx;
      final key =
          '${(x / _clusterCellPx).floor()}:${(y / _clusterCellPx).floor()}';
      (cells[key] ??= []).add(s);
    }

    final entities = <_MapEntity>[];
    for (final group in cells.values) {
      if (group.length == 1) {
        entities.add(_MapEntity.single(group.first));
      } else {
        var lat = 0.0, lng = 0.0;
        for (final s in group) {
          lat += s.latitude!;
          lng += s.longitude!;
        }
        entities.add(
          _MapEntity.cluster(
            LatLng(lat / group.length, lng / group.length),
            group,
          ),
        );
      }
    }
    return entities;
  }

  SalonSummary? get _selectedSalon {
    final id = _selectedId;
    if (id == null) return null;
    for (final s in _mapSalons) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final entities = _buildEntities();
    final selected = _selectedSalon;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.userLat != null && widget.userLng != null
                ? LatLng(widget.userLat!, widget.userLng!)
                : _istanbulCenter,
            initialZoom: _initialZoom,
            minZoom: 5,
            maxZoom: 18,
            backgroundColor: const Color(0xFFF4F1EA),
            onTap: (_, _) => setState(() => _selectedId = null),
            onMapEvent: _onMapEvent,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              // Açık/sade premium tema: CARTO Positron (OSM tabanlı).
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'tr.com.webey.beauty',
              maxZoom: 19,
            ),
            MarkerLayer(
              markers: [
                if (widget.userLat != null && widget.userLng != null)
                  Marker(
                    point: LatLng(widget.userLat!, widget.userLng!),
                    width: 22,
                    height: 22,
                    child: const _UserLocationDot(),
                  ),
                for (final entity in entities)
                  if (entity.isCluster)
                    Marker(
                      point: entity.center,
                      width: 46,
                      height: 46,
                      child: _ClusterBubble(
                        count: entity.salons.length,
                        onTap: () => _mapController.move(
                          entity.center,
                          math.min(18, _zoom + 2.2),
                        ),
                      ),
                    )
                  else
                    Marker(
                      point: entity.center,
                      width: 40,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: _SalonPin(
                        salon: entity.salons.first,
                        selected: entity.salons.first.id == _selectedId,
                        onTap: () => setState(
                          () => _selectedId = entity.salons.first.id,
                        ),
                      ),
                    ),
              ],
            ),
          ],
        ),

        // ── Atıf (tile sağlayıcı lisans gereği) ──────────────────────────
        Positioned(
          left: 8,
          bottom: 6,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(170),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '© OpenStreetMap katkıcıları © CARTO',
                style: TextStyle(fontSize: 9, color: Color(0xFF6B6B6B)),
              ),
            ),
          ),
        ),

        // ── Üst bilgi şeridi ─────────────────────────────────────────────
        Positioned(
          top: 10,
          left: 16,
          right: 16,
          child: Row(
            children: [
              _CountChip(loading: _loading, count: _mapSalons.length),
              const Spacer(),
              if (widget.userLat == null)
                _MapHintChip(
                  text: 'Konum kapalı',
                  icon: Icons.location_off_outlined,
                  onTap: widget.locationBusy ? null : widget.onRecenter,
                ),
            ],
          ),
        ),

        if (_loadFailed)
          Positioned(
            top: 54,
            left: 16,
            right: 16,
            child: _MapBanner(
              text: 'Harita verisi alınamadı. Tekrar denemek için dokunun.',
              onTap: () => _fetch(initial: true),
            ),
          )
        else if (!_loading && _mapSalons.isEmpty)
          const Positioned(
            top: 54,
            left: 16,
            right: 16,
            child: _MapBanner(
              text:
                  'Bu bölgede konum bilgisi olan salon bulunamadı. '
                  'Haritayı kaydırarak başka bölgelere bakabilirsiniz.',
            ),
          ),

        // ── Konumuma dön ─────────────────────────────────────────────────
        Positioned(
          right: 14,
          bottom: selected != null ? 178 : 26,
          child: _LocateFab(
            busy: widget.locationBusy,
            onTap: () async {
              await widget.onRecenter();
              final lat = widget.userLat;
              final lng = widget.userLng;
              if (lat != null && lng != null && mounted) {
                _mapController.move(LatLng(lat, lng), math.max(_zoom, 13.5));
              }
            },
          ),
        ),

        // ── Salon önizleme kartı ─────────────────────────────────────────
        Positioned(
          left: 12,
          right: 12,
          bottom: 14,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: selected == null
                ? const SizedBox.shrink()
                : _SalonPreviewCard(
                    key: ValueKey(selected.id),
                    salon: selected,
                    onClose: () => setState(() => _selectedId = null),
                    onOpen: () => widget.onOpenSalon(selected.toBeautySalon()),
                  ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cluster / pin veri modeli
// ─────────────────────────────────────────────────────────────────────────────

class _MapEntity {
  _MapEntity.single(SalonSummary salon)
    : salons = [salon],
      center = LatLng(salon.latitude!, salon.longitude!),
      isCluster = false;

  _MapEntity.cluster(this.center, this.salons) : isCluster = true;

  final List<SalonSummary> salons;
  final LatLng center;
  final bool isCluster;
}

// ─────────────────────────────────────────────────────────────────────────────
// Marker widget'ları
// ─────────────────────────────────────────────────────────────────────────────

/// Gri yuvarlak cluster balonu — içinde salon sayısı.
class _ClusterBubble extends StatelessWidget {
  const _ClusterBubble({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF5A5A5A),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(55),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Tek salon pini — boostlu salonlarda Webey altın yıldız.
class _SalonPin extends StatelessWidget {
  const _SalonPin({
    required this.salon,
    required this.selected,
    required this.onTap,
  });

  final SalonSummary salon;
  final bool selected;
  final VoidCallback onTap;

  bool get _isBoosted => salon.isBoosted;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? WebeyColors.darkEspresso
        : (_isBoosted ? WebeyColors.primaryGold : const Color(0xFF0EA5B3));
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: selected ? 36 : 30,
            height: selected ? 36 : 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(60),
                  blurRadius: 7,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              _isBoosted ? Icons.star_rounded : Icons.spa_rounded,
              size: selected ? 18 : 15,
              color: Colors.white,
            ),
          ),
          // Pin kuyruğu
          CustomPaint(
            size: const Size(10, 7),
            painter: _PinTailPainter(color: color),
          ),
        ],
      ),
    );
  }
}

class _PinTailPainter extends CustomPainter {
  const _PinTailPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PinTailPainter oldDelegate) => oldDelegate.color != color;
}

class _UserLocationDot extends StatelessWidget {
  const _UserLocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF3478F6),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3478F6).withAlpha(60),
            blurRadius: 14,
            spreadRadius: 5,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overlay widget'ları
// ─────────────────────────────────────────────────────────────────────────────

class _CountChip extends StatelessWidget {
  const _CountChip({required this.loading, required this.count});

  final bool loading;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WebeyColors.borderSand),
        boxShadow: [
          BoxShadow(
            color: WebeyColors.darkEspresso.withAlpha(25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: WebeyColors.primaryGold,
              ),
            )
          else
            const Icon(
              Icons.place_rounded,
              size: 14,
              color: WebeyColors.primaryGold,
            ),
          const SizedBox(width: 6),
          Text(
            loading ? 'Salonlar yükleniyor…' : '$count salon',
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

class _MapHintChip extends StatelessWidget {
  const _MapHintChip({required this.text, required this.icon, this.onTap});

  final String text;
  final IconData icon;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: WebeyColors.mutedTaupe),
            const SizedBox(width: 5),
            Text(
              text,
              style: const TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapBanner extends StatelessWidget {
  const _MapBanner({required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: WebeyColors.warmCream.withAlpha(245),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: WebeyColors.primaryGold,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocateFab extends StatelessWidget {
  const _LocateFab({required this.busy, required this.onTap});

  final bool busy;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : () => onTap(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WebeyColors.borderSand),
          boxShadow: [
            BoxShadow(
              color: WebeyColors.darkEspresso.withAlpha(35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: WebeyColors.primaryGold,
                ),
              )
            : const Icon(
                Icons.my_location_rounded,
                size: 20,
                color: WebeyColors.primaryGold,
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Salon önizleme kartı
// ─────────────────────────────────────────────────────────────────────────────

class _SalonPreviewCard extends StatelessWidget {
  const _SalonPreviewCard({
    super.key,
    required this.salon,
    required this.onClose,
    required this.onOpen,
  });

  final SalonSummary salon;
  final VoidCallback onClose;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final minPrice = salon.minPrice;
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: WebeyColors.borderSand),
          boxShadow: [
            BoxShadow(
              color: WebeyColors.darkEspresso.withAlpha(45),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kapak görseli
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 76,
                height: 88,
                child: salon.coverImageUrl.isNotEmpty
                    ? Image.network(
                        salon.coverImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _CardImageFallback(),
                      )
                    : const _CardImageFallback(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          salon.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: onClose,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: WebeyColors.mutedTaupe,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (salon.rating != null) ...[
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: WebeyColors.primaryGold,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          salon.rating!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (salon.reviewCount > 0)
                          Text(
                            ' (${salon.reviewCount})',
                            style: const TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 11.5,
                            ),
                          ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          [
                            if ((salon.district ?? '').isNotEmpty)
                              salon.district!,
                            if ((salon.city ?? '').isNotEmpty) salon.city!,
                          ].join(' / '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (minPrice != null && minPrice > 0)
                        _MiniBadge(
                          text: '${minPrice.toInt()} TL\'den',
                          color: WebeyColors.darkEspresso,
                          background: WebeyColors.warmCream,
                        ),
                      if (salon.depositRequired) ...[
                        const SizedBox(width: 6),
                        const _MiniBadge(
                          text: 'Kaporalı',
                          color: Colors.white,
                          background: WebeyColors.primaryGold,
                        ),
                      ],
                      if (salon.isOpenNow) ...[
                        const SizedBox(width: 6),
                        const _MiniBadge(
                          text: 'Açık',
                          color: Colors.white,
                          background: WebeyColors.successGreen,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: ElevatedButton(
                      onPressed: onOpen,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WebeyColors.darkEspresso,
                        foregroundColor: WebeyColors.primaryGold,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Detay & Randevu',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.text,
    required this.color,
    required this.background,
  });

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CardImageFallback extends StatelessWidget {
  const _CardImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WebeyColors.warmCream,
      child: const Icon(
        Icons.spa_outlined,
        color: WebeyColors.primaryGold,
        size: 26,
      ),
    );
  }
}
