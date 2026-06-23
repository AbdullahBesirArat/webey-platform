// lib/features/business/presentation/business_location_picker.dart
//
// Salon sahibinin haritada konum seçmesi: pin haritanın merkezinde sabittir,
// kullanıcı haritayı kaydırarak konumu ayarlar ve "Bu konumu kaydet" der.
// Navigator.pop ile (lat, lng) döner.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/theme/webey_colors.dart';
import '../../../shared/widgets/webey_toast.dart';

class BusinessLocationPickResult {
  const BusinessLocationPickResult({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class BusinessLocationPickerScreen extends StatefulWidget {
  const BusinessLocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<BusinessLocationPickerScreen> createState() =>
      _BusinessLocationPickerScreenState();
}

class _BusinessLocationPickerScreenState
    extends State<BusinessLocationPickerScreen> {
  static const _istanbulCenter = LatLng(41.0151, 29.0245);

  final _mapController = MapController();
  LatLng _center = _istanbulCenter;
  double _zoom = 12;
  bool _locating = false;

  bool get _hasInitial =>
      widget.initialLatitude != null &&
      widget.initialLongitude != null &&
      !(widget.initialLatitude!.abs() < 0.0001 &&
          widget.initialLongitude!.abs() < 0.0001);

  @override
  void initState() {
    super.initState();
    if (_hasInitial) {
      _center = LatLng(widget.initialLatitude!, widget.initialLongitude!);
      _zoom = 15.5;
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          WebeyToast.info(context, 'Konum servisleri kapalı.');
        }
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          WebeyToast.info(
            context,
            'Konum izni verilmedi. Haritadan manuel seçim yapabilirsiniz.',
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      _mapController.move(
        LatLng(pos.latitude, pos.longitude),
        math.max(_zoom, 16),
      );
    } catch (_) {
      if (mounted) {
        WebeyToast.info(context, 'Konum alınamadı.');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
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
          'Haritada Konum Seç',
          style: TextStyle(
            color: WebeyColors.darkEspresso,
            fontSize: 16,
            fontFamily: 'Georgia',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: _zoom,
                    minZoom: 5,
                    maxZoom: 18,
                    backgroundColor: const Color(0xFFF4F1EA),
                    onPositionChanged: (camera, _) {
                      _center = camera.center;
                      _zoom = camera.zoom;
                    },
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
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
                  ],
                ),

                // Sabit merkez pini: kullanıcı haritayı pinin altına kaydırır.
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      // Pinin ucu tam harita merkezine gelsin.
                      offset: const Offset(0, -22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: WebeyColors.primaryGold,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(70),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.storefront_rounded,
                              size: 17,
                              color: Colors.white,
                            ),
                          ),
                          CustomPaint(
                            size: const Size(10, 8),
                            painter: _PickerPinTail(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                Positioned(
                  left: 8,
                  bottom: 6,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
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

                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(240),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: const Text(
                        'Haritayı kaydırarak pini salonunuzun bulunduğu '
                        'noktaya getirin.',
                        style: TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),

                Positioned(
                  right: 14,
                  bottom: 18,
                  child: GestureDetector(
                    onTap: _goToMyLocation,
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
                      child: _locating
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
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WebeyColors.darkEspresso,
                    foregroundColor: WebeyColors.primaryGold,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(
                      context,
                      BusinessLocationPickResult(
                        latitude: _center.latitude,
                        longitude: _center.longitude,
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: const Text(
                    'Bu konumu kaydet',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerPinTail extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = WebeyColors.primaryGold);
  }

  @override
  bool shouldRepaint(_PickerPinTail oldDelegate) => false;
}
