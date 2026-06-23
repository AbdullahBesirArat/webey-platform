import 'package:flutter/material.dart';

import '../../core/theme/webey_colors.dart';
import '../models/beauty_models.dart';
import '../utils/formatters.dart';

class ScreenPadding extends StatelessWidget {
  const ScreenPadding({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: child,
          ),
        ),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    required this.title,
    required this.subtitle,
    this.compact = false,
    this.dark = false,
  });

  final String title;
  final String subtitle;
  final bool compact;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final textColor = dark ? WebeyColors.softWhite : WebeyColors.darkEspresso;
    final subColor = dark ? WebeyColors.goldLight : WebeyColors.mutedTaupe;

    return Row(
      children: [
        Container(
          width: compact ? 42 : 56,
          height: compact ? 42 : 56,
          decoration: BoxDecoration(
            color: dark ? WebeyColors.primaryGold : WebeyColors.darkEspresso,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.spa_outlined,
            color: dark ? WebeyColors.darkEspresso : WebeyColors.primaryGold,
            size: compact ? 20 : 26,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    (compact ? textTheme.titleLarge : textTheme.headlineMedium)
                        ?.copyWith(
                          color: textColor,
                          fontFamily: 'Georgia',
                          fontWeight: FontWeight.w600,
                        ),
              ),
              const SizedBox(height: 3),
              Container(width: 28, height: 1.5, color: WebeyColors.primaryGold),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: textTheme.bodyMedium?.copyWith(color: subColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Georgia',
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        if (action != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}

class WebeyCard extends StatelessWidget {
  const WebeyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.goldBorder = false,
    this.radius = WebeyRadius.medium,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final bool goldBorder;
  final double radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: goldBorder
              ? WebeyColors.alpha(WebeyColors.primaryGold, 0.45)
              : WebeyColors.borderSand,
        ),
        boxShadow: shadow ? WebeyShadow.subtle : null,
      ),
      padding: padding,
      child: child,
    );
  }
}

enum WebeyButtonVariant { primary, secondary, ghost }

class WebeyButton extends StatelessWidget {
  const WebeyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = WebeyButtonVariant.primary,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final WebeyButtonVariant variant;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isPrimary = variant == WebeyButtonVariant.primary;
    final isGhost = variant == WebeyButtonVariant.ghost;
    final foreground = isPrimary
        ? WebeyColors.darkEspresso
        : variant == WebeyButtonVariant.secondary
        ? WebeyColors.darkEspresso
        : WebeyColors.primaryGold;

    return SizedBox(
      height: compact ? 42 : 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isPrimary
              ? WebeyColors.primaryGold
              : isGhost
              ? Colors.transparent
              : WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(WebeyRadius.small),
          border: isPrimary ? null : Border.all(color: WebeyColors.borderSand),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(WebeyRadius.small),
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: compact ? 14 : 16, color: foreground),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: compact ? 12.5 : 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BottomStickyCTA extends StatelessWidget {
  const BottomStickyCTA({
    super.key,
    required this.label,
    required this.onPressed,
    this.helper,
    this.icon = Icons.arrow_forward_rounded,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? helper;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: const BoxDecoration(
          color: WebeyColors.ivory,
          border: Border(top: BorderSide(color: WebeyColors.borderSand)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: WebeyButton(
                label: label,
                icon: icon,
                onPressed: onPressed,
              ),
            ),
            if (helper != null) ...[
              const SizedBox(height: 7),
              Text(
                helper!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PremiumPanel extends StatelessWidget {
  const PremiumPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: WebeyColors.darkEspresso,
        borderRadius: BorderRadius.circular(WebeyRadius.medium),
        border: Border.all(
          color: WebeyColors.alpha(WebeyColors.primaryGold, 0.4),
        ),
      ),
      child: child,
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = WebeyColors.primaryGold,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return WebeyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: WebeyColors.alpha(color, 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: WebeyColors.alpha(color, 0.10),
        borderRadius: BorderRadius.circular(WebeyRadius.pill),
        border: Border.all(color: WebeyColors.alpha(color, 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SalonCover extends StatelessWidget {
  const SalonCover({super.key, required this.salon, this.height = 132});

  final Salon salon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: salon.coverColor,
        borderRadius: BorderRadius.circular(WebeyRadius.medium),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (salon.coverImage.isNotEmpty)
            Image.network(
              salon.coverImage,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _SalonImageFallback(salon: salon),
            )
          else
            _SalonImageFallback(salon: salon),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  WebeyColors.alpha(WebeyColors.darkEspresso, 0.04),
                  WebeyColors.alpha(WebeyColors.darkEspresso, 0.62),
                ],
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 10,
            right: 10,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (salon.isPremium)
                  const StatusChip(
                    label: 'Premium Salon',
                    color: WebeyColors.primaryGold,
                    icon: Icons.workspace_premium_outlined,
                  ),
                if (salon.availableToday)
                  const StatusChip(
                    label: 'Bugün Müsait',
                    color: WebeyColors.successGreen,
                    icon: Icons.event_available_outlined,
                  ),
              ],
            ),
          ),
          Positioned(
            left: 14,
            bottom: 14,
            right: 14,
            child: Text(
              salon.type.replaceAll('_', ' ').toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: WebeyColors.alpha(WebeyColors.softWhite, 0.94),
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SalonCard extends StatelessWidget {
  const SalonCard({
    super.key,
    required this.salon,
    required this.onTap,
    this.compact = false,
  });

  final Salon salon;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(WebeyRadius.medium),
        boxShadow: WebeyShadow.soft,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(WebeyRadius.medium),
        splashColor: WebeyColors.alpha(WebeyColors.primaryGold, 0.1),
        onTap: onTap,
        child: WebeyCard(
          padding: EdgeInsets.zero,
          radius: WebeyRadius.medium,
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              compact
                  ? SalonCover(salon: salon, height: 108)
                  : _SalonCardPhoto(salon: salon),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            salon.name,
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Icon(
                          salon.isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 20,
                          color: WebeyColors.primaryGold,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${salon.district}, ${salon.neighborhood} · ${salon.distanceKm.toStringAsFixed(1)} km',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        if (!compact && salon.isPremium)
                          const StatusChip(
                            label: 'Premium Salon',
                            color: WebeyColors.primaryGold,
                            icon: Icons.workspace_premium_outlined,
                          ),
                        StatusChip(
                          label: '${salon.rating} (${salon.reviewCount})',
                          color: WebeyColors.primaryGold,
                          icon: Icons.star_rounded,
                        ),
                        StatusChip(
                          label: money(salon.startingPrice),
                          color: WebeyColors.mutedTaupe,
                        ),
                        if (!compact)
                          StatusChip(
                            label: depositBadgeLabel(salon.acceptsDeposit),
                            color: salon.acceptsDeposit
                                ? WebeyColors.primaryGold
                                : WebeyColors.successGreen,
                            icon: salon.acceptsDeposit
                                ? Icons.verified_outlined
                                : Icons.payments_outlined,
                          ),
                        if (!compact && salon.availableToday)
                          const StatusChip(
                            label: 'Bugün müsait',
                            color: WebeyColors.successGreen,
                            icon: Icons.event_available_outlined,
                          ),
                      ],
                    ),
                    if (!compact && salon.campaign != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        salon.campaign!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: WebeyColors.darkEspresso,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalonCardPhoto extends StatelessWidget {
  const _SalonCardPhoto({required this.salon});

  final Salon salon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(WebeyRadius.medium),
      ),
      child: SizedBox(
        height: 156,
        width: double.infinity,
        child: SalonCover(salon: salon, height: 156),
      ),
    );
  }
}

class _SalonImageFallback extends StatelessWidget {
  const _SalonImageFallback({required this.salon});

  final Salon salon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: salon.coverColor,
      child: Center(
        child: Icon(
          Icons.spa_outlined,
          size: 68,
          color: WebeyColors.alpha(WebeyColors.softWhite, 0.25),
        ),
      ),
    );
  }
}

class AppointmentTile extends StatelessWidget {
  const AppointmentTile({
    super.key,
    required this.appointment,
    this.onTap,
    this.businessView = false,
  });

  final Appointment appointment;
  final VoidCallback? onTap;
  final bool businessView;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (appointment.status) {
      AppointmentStatus.approved => WebeyColors.successGreen,
      AppointmentStatus.completed => WebeyColors.successGreen,
      AppointmentStatus.pending => WebeyColors.warning,
      AppointmentStatus.cancellationRequested => WebeyColors.errorRed,
      AppointmentStatus.cancelled => WebeyColors.errorRed,
      AppointmentStatus.noShow => WebeyColors.errorRed,
      AppointmentStatus.rejected => WebeyColors.errorRed,
    };
    final hasDeposit = appointment.depositStatus == DepositStatus.paid;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WebeyRadius.medium),
      splashColor: WebeyColors.alpha(WebeyColors.primaryGold, 0.1),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(WebeyRadius.small),
            topRight: Radius.circular(WebeyRadius.medium),
            bottomRight: Radius.circular(WebeyRadius.medium),
            bottomLeft: Radius.circular(WebeyRadius.small),
          ),
          border: Border.all(color: WebeyColors.borderSand),
          boxShadow: WebeyShadow.subtle,
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: statusColor),
              Expanded(
                child: Container(
                  color: WebeyColors.softWhite,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 58,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: WebeyColors.alpha(
                                WebeyColors.primaryGold,
                                0.10,
                              ),
                              borderRadius: BorderRadius.circular(
                                WebeyRadius.small,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  clock(appointment.startAt),
                                  style: const TextStyle(
                                    color: WebeyColors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  shortDate(appointment.startAt),
                                  style: const TextStyle(
                                    color: WebeyColors.mutedTaupe,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  businessView
                                      ? appointment.customerName
                                      : appointment.salonName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${appointment.serviceName} · ${appointment.staffName}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: WebeyColors.mutedTaupe,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          StatusChip(
                            label: appointmentStatusLabel(appointment.status),
                            color: statusColor,
                          ),
                          StatusChip(
                            label: hasDeposit
                                ? 'Kapora ödendi'
                                : 'Ödeme salonda',
                            color: hasDeposit
                                ? WebeyColors.successGreen
                                : WebeyColors.mutedTaupe,
                            icon: hasDeposit
                                ? Icons.verified_outlined
                                : Icons.storefront_outlined,
                          ),
                          if (hasDeposit)
                            StatusChip(
                              label:
                                  'Kalan ödeme salonda: ${money(appointment.remainingAmount)}',
                              color: WebeyColors.espresso,
                            ),
                          if (appointment.cancellationRequested)
                            const StatusChip(
                              label: 'İptal talebi var',
                              color: WebeyColors.errorRed,
                              icon: Icons.report_problem_outlined,
                            ),
                          if (appointment.rescheduleRequested)
                            const StatusChip(
                              label: 'Değişiklik talebi var',
                              color: WebeyColors.warning,
                              icon: Icons.event_repeat_outlined,
                            ),
                        ],
                      ),
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

class WebeyLoadingState extends StatelessWidget {
  const WebeyLoadingState({
    super.key,
    this.title = 'Yükleniyor',
    this.description = 'Bilgiler güvenli şekilde hazırlanıyor.',
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return WebeyCard(
      color: WebeyColors.softWhite,
      goldBorder: true,
      child: Row(
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WebeyEmptyState extends StatelessWidget {
  const WebeyEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.ctaText,
    this.onCta,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? ctaText;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return WebeyCard(
      color: WebeyColors.softWhite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: WebeyColors.goldLight,
            child: Icon(icon, color: WebeyColors.primaryGold),
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(description),
          if (ctaText != null && onCta != null) ...[
            const SizedBox(height: 12),
            WebeyButton(
              label: ctaText!,
              onPressed: onCta,
              compact: true,
              variant: WebeyButtonVariant.secondary,
            ),
          ],
        ],
      ),
    );
  }
}

class WebeyErrorState extends StatelessWidget {
  const WebeyErrorState({
    super.key,
    this.title = 'Bir şeyler ters gitti',
    this.description = 'Lütfen bağlantınızı kontrol edip tekrar deneyin.',
    this.onRetry,
  });

  final String title;
  final String description;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return WebeyCard(
      color: WebeyColors.softWhite,
      goldBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            backgroundColor: WebeyColors.nude,
            child: Icon(Icons.error_outline, color: WebeyColors.errorRed),
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(description),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar dene'),
          ),
        ],
      ),
    );
  }
}
