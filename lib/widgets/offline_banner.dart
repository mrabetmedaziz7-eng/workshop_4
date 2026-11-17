import 'package:flutter/material.dart';
import '../models/app_connectivity.dart';
import '../theme/app_theme.dart';

class OfflineBanner extends StatelessWidget {
  final AppConnectivity status;

  const OfflineBanner({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    if (status == AppConnectivity.online) {
      return const SizedBox.shrink();
    }

    final (message, color, icon) = switch (status) {
      AppConnectivity.offline => (
          'No network connection',
          AppColors.error,
          Icons.wifi_off_rounded,
        ),
      AppConnectivity.backendUnavailable => (
          'Waiting-room server unavailable',
          AppColors.warning,
          Icons.cloud_off_rounded,
        ),
      AppConnectivity.checking => (
          'Checking connection...',
          AppColors.secondary,
          Icons.sync_rounded,
        ),
      AppConnectivity.online => (
          'Connected',
          AppColors.accent,
          Icons.check_circle_outline_rounded,
        ),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: AppRadius.pillRadius,
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

