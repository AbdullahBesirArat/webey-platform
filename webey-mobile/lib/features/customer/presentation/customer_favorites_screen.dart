// lib/features/customer/presentation/customer_favorites_screen.dart
//
// Webey Beauty — Favorilerim Ekranı

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/webey_colors.dart';
import '../../../shared/models/beauty_models.dart';
import '../discovery/data/models/salon_adapter.dart';
import '../discovery/data/models/salon_summary.dart';
import '../favorites/data/repositories/customer_favorite_repository.dart';
import '../profile/data/repositories/customer_profile_repository.dart';

class CustomerFavoritesScreen extends StatefulWidget {
  const CustomerFavoritesScreen({
    super.key,
    required this.onOpenSalon,
    this.repository = CustomerFavoriteRepository.instance,
  });

  final Future<void> Function(Salon) onOpenSalon;
  final CustomerFavoriteRepository repository;

  @override
  State<CustomerFavoritesScreen> createState() =>
      _CustomerFavoritesScreenState();
}

class _CustomerFavoritesScreenState extends State<CustomerFavoritesScreen> {
  var _favorites = <SalonSummary>[];
  var _loading = true;
  final Map<String, bool> _toggling = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final favs = await widget.repository.getFavorites();
    if (!mounted) return;
    setState(() {
      _favorites = favs;
      _loading = false;
    });
    final profile = await CustomerProfileRepository.instance.getProfile();
    if (!mounted || profile?.latitude == null || profile?.longitude == null) {
      return;
    }
    final withDistance = await widget.repository.getFavorites(
      lat: profile!.latitude,
      lng: profile.longitude,
    );
    if (!mounted || withDistance.isEmpty) return;
    setState(() => _favorites = withDistance);
  }

  Future<void> _onSalonTap(SalonSummary salon) async {
    await widget.onOpenSalon(salon.toBeautySalon());
    if (mounted) _load();
  }

  Future<void> _removeFavorite(SalonSummary salon) async {
    if (_toggling[salon.id] == true) return;
    setState(() => _toggling[salon.id] = true);
    await widget.repository.toggleFavorite(
      businessId: salon.id,
      favorite: false,
    );
    if (!mounted) return;
    setState(() {
      _favorites = _favorites.where((s) => s.id != salon.id).toList();
      _toggling.remove(salon.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: WebeyColors.ivory,
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _FavHeader()),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: WebeyColors.primaryGold,
                      strokeWidth: 2,
                    ),
                  ),
                )
              else if (_favorites.isEmpty)
                SliverFillRemaining(child: _EmptyState())
              else ...[
                // Section label
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Row(
                      children: [
                        Container(
                          width: 14,
                          height: 1,
                          color: WebeyColors.primaryGold,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'FAVORİ SALONLAR',
                          style: TextStyle(
                            color: WebeyColors.primaryGold,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_favorites.length} salon',
                          style: TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Grid
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.72,
                        ),
                    delegate: SliverChildBuilderDelegate((context, i) {
                      if (i >= _favorites.length) return null;
                      final s = _favorites[i];
                      return _FavGridCard(
                        salon: s,
                        removing: _toggling[s.id] == true,
                        onRemove: () => _removeFavorite(s),
                        onTap: () => _onSalonTap(s),
                      );
                    }, childCount: _favorites.length),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _FavHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
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
                TextSpan(text: 'Favori'),
                TextSpan(
                  text: 'lerim',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Beğendiğin salonları kaydet, kolayca randevu al.',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Grid Card ────────────────────────────────────────────────────────────────

class _FavGridCard extends StatelessWidget {
  const _FavGridCard({
    required this.salon,
    required this.removing,
    required this.onRemove,
    required this.onTap,
  });
  final SalonSummary salon;
  final bool removing;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final price = salon.minPrice;
    final hasDistance = (salon.distanceKm ?? 0) > 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                // Cover image or gradient placeholder
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(11),
                    ),
                    image: salon.coverImageUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(salon.coverImageUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                    gradient: salon.coverImageUrl.isEmpty
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF3a261a), Color(0xFF1f1108)],
                          )
                        : null,
                  ),
                  child: salon.coverImageUrl.isEmpty
                      ? Center(
                          child: Text(
                            salon.name.isNotEmpty
                                ? salon.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Color(0x55D4B574),
                              fontSize: 28,
                              fontFamily: 'Georgia',
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )
                      : null,
                ),
                // Heart button
                Positioned(
                  top: 5,
                  right: 6,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: removing
                          ? const Center(
                              child: SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: WebeyColors.blushRose,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.favorite,
                              size: 13,
                              color: WebeyColors.blushRose,
                            ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 9, 9, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    salon.name,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      salon.district,
                      salon.city,
                      if (hasDistance)
                        '${salon.distanceKm!.toStringAsFixed(1)} km',
                    ].where((s) => s != null && s.isNotEmpty).join(' · '),
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 10,
                    ),
                  ),
                  if (price != null && price > 0) ...[
                    const SizedBox(height: 5),
                    Text(
                      '${price.toInt()} TL’den başlayan',
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  if (salon.rating != null && salon.rating! > 0)
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 11,
                          color: WebeyColors.primaryGold,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          salon.rating!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (salon.reviewCount > 0) ...[
                          const SizedBox(width: 2),
                          Text(
                            '(${salon.reviewCount})',
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ],
                    )
                  else
                    Text(
                      'Henüz yorum yok',
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 10,
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

// ── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: WebeyColors.warmCream,
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: const Icon(
                Icons.favorite_border_rounded,
                size: 32,
                color: WebeyColors.primaryGold,
              ),
            ),
            const SizedBox(height: 20),
            RichText(
              textAlign: TextAlign.center,
              text: const TextSpan(
                style: TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 22,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
                children: [
                  TextSpan(text: 'Henüz '),
                  TextSpan(
                    text: 'favori',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: WebeyColors.primaryGold,
                    ),
                  ),
                  TextSpan(text: '\neklemediniz.'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Salon detay sayfasında kalp ikonuna dokunarak favorilerinize ekleyebilirsiniz.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
