import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/client.dart';
import '../models/sync_status.dart';
import '../theme/app_theme.dart';

class ClientTile extends StatelessWidget {
  final Client client;
  final int position;
  final bool isNowServing;
  final VoidCallback onRemove;

  const ClientTile({
    super.key,
    required this.client,
    required this.position,
    required this.isNowServing,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final timeString = DateFormat('HH:mm').format(client.createdAt.toLocal());

    final borderColor = isNowServing
        ? (isDark ? AppColors.accent : AppColors.accent)
        : (isDark ? AppColors.darkBorder : AppColors.lightBorder);

    final cardBg = isNowServing
        ? (isDark
            ? AppColors.darkCard.withAlpha(240)
            : const Color(0xFFF0FDF4)) // light emerald background
        : (isDark ? AppColors.darkCard : AppColors.lightCard);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(
          color: borderColor,
          width: isNowServing ? 1.8 : 1.0,
        ),
        boxShadow: isNowServing
            ? [
                BoxShadow(
                  color: AppColors.accent.withAlpha(isDark ? 40 : 30),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 20 : 6),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.lgRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              // Queue position badge
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isNowServing
                      ? AppColors.accent
                      : (isDark
                          ? AppColors.darkSurface
                          : AppColors.primary.withAlpha(20)),
                  borderRadius: AppRadius.mdRadius,
                ),
                alignment: Alignment.center,
                child: Text(
                  '#$position',
                  style: TextStyle(
                    color: isNowServing
                        ? Colors.white
                        : (isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.primary),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // Name and status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            client.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isNowServing) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.accent.withAlpha(45)
                                  : AppColors.accentContainer,
                              borderRadius: AppRadius.pillRadius,
                              border: Border.all(
                                color: AppColors.accent,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: AppColors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Now Serving',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? AppColors.accent
                                        : AppColors.onAccentContainer,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeString,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            client.hasLocation && client.locationAccuracy != null
                                ? '📍 ${client.locationText} (±${client.locationAccuracy!.round()}m)'
                                : '📍 ${client.locationText}',
                            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (client.syncStatus != SyncStatus.synced) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _SyncStatusBadge(status: client.syncStatus, isDark: isDark),
                    ],
                  ],
                ),
              ),

              // Remove button
              IconButton(
                onPressed: onRemove,
                tooltip: 'Remove ${client.name}',
                icon: const Icon(Icons.delete_outline_rounded),
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
                hoverColor: AppColors.error.withAlpha(25),
                highlightColor: AppColors.error.withAlpha(40),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncStatusBadge extends StatelessWidget {
  final SyncStatus status;
  final bool isDark;

  const _SyncStatusBadge({
    required this.status,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      SyncStatus.pending => (
          'Waiting to sync',
          AppColors.warning,
          Icons.cloud_off_rounded,
        ),
      SyncStatus.syncing => (
          'Syncing...',
          AppColors.secondary,
          Icons.sync_rounded,
        ),
      SyncStatus.failed => (
          'Sync failed · will retry',
          AppColors.error,
          Icons.error_outline_rounded,
        ),
      SyncStatus.synced => (
          'Synced',
          AppColors.accent,
          Icons.cloud_done_rounded,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 35 : 25),
        borderRadius: AppRadius.pillRadius,
        border: Border.all(
          color: color.withAlpha(90),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
