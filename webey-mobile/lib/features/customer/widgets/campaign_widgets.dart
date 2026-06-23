import 'package:flutter/material.dart';

import '../../../core/theme/webey_colors.dart';
import '../discovery/data/models/salon_campaign.dart';

/// Küçük altın kampanya rozeti (kapak üstü / kart içi).
class CampaignBadge extends StatelessWidget {
  const CampaignBadge({super.key, required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: WebeyColors.primaryGold,
        borderRadius: BorderRadius.circular(WebeyRadius.pill),
        boxShadow: WebeyShadow.subtle,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_offer, size: compact ? 11 : 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ana Sayfa "Kampanyalı Salonlar" yatay kartı (SalonSummary tabanlı).
class CampaignSalonCard extends StatelessWidget {
  const CampaignSalonCard({
    super.key,
    required this.name,
    required this.coverImageUrl,
    required this.campaign,
    this.district,
    this.distanceKm,
    this.rating,
    this.reviewCount = 0,
    this.minPrice,
    required this.onTap,
  });

  final String name;
  final String coverImageUrl;
  final SalonCampaign campaign;
  final String? district;
  final double? distanceKm;
  final double? rating;
  final int reviewCount;
  final double? minPrice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locParts = <String>[
      if (district != null && district!.isNotEmpty) district!,
      if (distanceKm != null) '${distanceKm!.toStringAsFixed(1)} km',
    ];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 230,
        margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(WebeyRadius.large),
          border: Border.all(color: WebeyColors.borderSand),
          boxShadow: WebeyShadow.subtle,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(WebeyRadius.large),
                  ),
                  child: SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: coverImageUrl.isNotEmpty
                        ? Image.network(
                            coverImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _imageFallback(),
                          )
                        : _imageFallback(),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: CampaignBadge(label: campaign.shortLabel, compact: true),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WebeyColors.darkEspresso,
                    ),
                  ),
                  if (locParts.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      locParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: WebeyColors.mutedTaupe,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (rating != null) ...[
                        const Icon(Icons.star_rounded,
                            size: 15, color: WebeyColors.primaryGold),
                        const SizedBox(width: 2),
                        Text(
                          rating!.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: WebeyColors.darkText,
                          ),
                        ),
                        if (reviewCount > 0)
                          Text(
                            ' ($reviewCount)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: WebeyColors.mutedTaupe,
                            ),
                          ),
                      ],
                      const Spacer(),
                      if (minPrice != null)
                        Text(
                          '${minPrice!.round()} TL+',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: WebeyColors.darkText,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    campaign.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
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

  Widget _imageFallback() => Container(
        color: WebeyColors.warmCream,
        child: const Center(
          child: Icon(Icons.spa_outlined,
              color: WebeyColors.deepChampagne, size: 32),
        ),
      );
}

/// Salon Detay kampanya bandı + "Detaylar" bottom sheet.
class CampaignDetailBand extends StatelessWidget {
  const CampaignDetailBand({super.key, required this.campaign});

  final SalonCampaign campaign;

  void _openDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => CampaignDetailSheet(campaign: campaign),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: GestureDetector(
        onTap: () => _openDetails(context),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                WebeyColors.goldLight,
                WebeyColors.alpha(WebeyColors.deepChampagne, 0.25),
              ],
            ),
            borderRadius: BorderRadius.circular(WebeyRadius.medium),
            border: Border.all(
              color: WebeyColors.alpha(WebeyColors.primaryGold, 0.4),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: WebeyColors.primaryGold,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_offer,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bu salonda aktif fırsat var',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: WebeyColors.darkEspresso,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      campaign.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: WebeyColors.mutedTaupe,
                      ),
                    ),
                    if (campaign.validitySummary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        campaign.validitySummary,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: WebeyColors.primaryGold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Koşulları Gör',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: WebeyColors.primaryGold,
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: WebeyColors.primaryGold, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class CampaignDetailSheet extends StatelessWidget {
  const CampaignDetailSheet({super.key, required this.campaign});

  final SalonCampaign campaign;

  static const _dayNames = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  String _fmtDate(String? d) {
    if (d == null || d.isEmpty) return '';
    final p = d.split('-');
    if (p.length == 3) return '${p[2]}.${p[1]}.${p[0]}';
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String, String)>[];
    rows.add((
      Icons.percent,
      'İndirim',
      campaign.shortLabel,
    ));
    rows.add((
      Icons.spa_outlined,
      'Geçerli hizmetler',
      campaign.appliesToAllServices ? 'Tüm hizmetler' : 'Seçili hizmetler',
    ));
    if (campaign.daysOfWeek.isNotEmpty) {
      rows.add((
        Icons.calendar_today_outlined,
        'Günler',
        campaign.daysOfWeek.map((d) => _dayNames[d]).join(', '),
      ));
    }
    if (campaign.startTime != null && campaign.endTime != null) {
      rows.add((
        Icons.schedule,
        'Saatler',
        '${campaign.startTime} – ${campaign.endTime}',
      ));
    }
    final dr = [
      _fmtDate(campaign.startDate),
      _fmtDate(campaign.endDate),
    ].where((e) => e.isNotEmpty).join(' – ');
    if (dr.isNotEmpty) {
      rows.add((Icons.event_outlined, 'Tarih aralığı', dr));
    }

    return Container(
      decoration: const BoxDecoration(
        color: WebeyColors.ivory,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: WebeyColors.borderSand,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.local_offer, color: WebeyColors.primaryGold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      campaign.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: WebeyColors.darkEspresso,
                      ),
                    ),
                  ),
                ],
              ),
              if (campaign.description != null) ...[
                const SizedBox(height: 8),
                Text(
                  campaign.description!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: WebeyColors.mutedTaupe,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ...rows.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(r.$1, size: 18, color: WebeyColors.primaryGold),
                      const SizedBox(width: 12),
                      Text(
                        '${r.$2}: ',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: WebeyColors.darkText,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          r.$3,
                          style: const TextStyle(
                            fontSize: 13,
                            color: WebeyColors.darkText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Şu an geçerli mi bilgisi
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: campaign.eligibilityNow
                      ? WebeyColors.alpha(WebeyColors.successGreen, 0.1)
                      : WebeyColors.warmCream,
                  borderRadius: BorderRadius.circular(WebeyRadius.small),
                ),
                child: Row(
                  children: [
                    Icon(
                      campaign.eligibilityNow
                          ? Icons.check_circle_outline
                          : Icons.schedule,
                      size: 16,
                      color: campaign.eligibilityNow
                          ? WebeyColors.successGreen
                          : WebeyColors.mutedTaupe,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        campaign.eligibilityNow
                            ? 'Şu an bu kampanya geçerli.'
                            : 'Bu kampanya şu anda aktif değil; uygun gün ve saatte otomatik uygulanır.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: WebeyColors.darkText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'İndirim, randevu tarihine göre otomatik uygulanır. Kesin indirimli '
                'fiyat hizmet ve tarih/saat seçiminden sonra randevu özetinde gösterilir.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: WebeyColors.mutedTaupe,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
