import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_connectivity.dart';
import '../models/queue_state.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../queue_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/client_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_widget.dart';
import '../widgets/offline_banner.dart';

class ClientWaitingRoomScreen extends StatefulWidget {
  const ClientWaitingRoomScreen({super.key});

  @override
  State<ClientWaitingRoomScreen> createState() =>
      _ClientWaitingRoomScreenState();
}

class _ClientWaitingRoomScreenState extends State<ClientWaitingRoomScreen> {
  String? _lastNotifiedClientId;

  AppConnectivity _effectiveConnectivity(
    BuildContext context,
    QueueProvider queue,
  ) {
    try {
      return context.watch<ConnectivityProvider>().status;
    } on ProviderNotFoundException {
      return queue.connectivityStatus;
    }
  }

  void _checkNotifications(
    BuildContext context,
    QueueProvider queue,
    String? userId,
  ) {
    if (userId == null) return;
    final myClient = queue.getMyClient(userId);
    if (myClient == null) return;

    if (!myClient.notified && _lastNotifiedClientId != myClient.id) {
      if (myClient.isAccepted) {
        _lastNotifiedClientId = myClient.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text(
                      'Vous avez été accepté dans la file d\'attente !',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.accent,
              duration: const Duration(seconds: 4),
            ),
          );
          queue.markNotified(myClient.id);
        });
      } else if (myClient.isRejected) {
        _lastNotifiedClientId = myClient.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.cancel_rounded, color: Colors.white),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text(
                      'Votre demande a été refusée par l\'administrateur.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 4),
            ),
          );
          queue.markNotified(myClient.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();
    final queue = context.watch<QueueProvider>();

    _checkNotifications(context, queue, auth.currentUserId);

    final myClient = queue.getMyClient(auth.currentUserId);
    final connectivity = _effectiveConnectivity(context, queue);
    final isRealtimeReady = connectivity == AppConnectivity.online &&
        queue.errorMessage == null &&
        !queue.isLoading &&
        queue.pendingSyncCount == 0;

    final statusColor = switch (connectivity) {
      AppConnectivity.offline => AppColors.error,
      AppConnectivity.backendUnavailable => AppColors.warning,
      AppConnectivity.checking => AppColors.secondary,
      AppConnectivity.online =>
        isRealtimeReady ? AppColors.accent : AppColors.warning,
    };
    final statusLabel = switch (connectivity) {
      AppConnectivity.offline => 'Offline',
      AppConnectivity.backendUnavailable => 'Server Down',
      AppConnectivity.checking => 'Checking...',
      AppConnectivity.online => isRealtimeReady ? 'Realtime' : 'Syncing...',
    };

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs + 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(25),
                borderRadius: AppRadius.smRadius,
              ),
              child: const Icon(
                Icons.meeting_room_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting Room',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  auth.profile?.name ?? 'Client',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Realtime / Offline indicator badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(isDark ? 35 : 25),
              borderRadius: AppRadius.pillRadius,
              border: Border.all(color: statusColor.withAlpha(80)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // Logout button
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Se déconnecter',
            onPressed: () async {
              await auth.signOut();
            },
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Offline banner
                  if (connectivity != AppConnectivity.online)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: OfflineBanner(status: connectivity),
                    ),

                  // Validation Banner for Pending or Rejected Client
                  if (myClient != null && myClient.isPending) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withAlpha(20),
                        borderRadius: AppRadius.mdRadius,
                        border: Border.all(
                          color: AppColors.warning.withAlpha(100),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.hourglass_top_rounded,
                            color: AppColors.warning,
                            size: 26,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'En attente de validation par l\'administrateur',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppColors.warning,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Votre demande a été enregistrée. Vous intégrerez la file dès son approbation.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (myClient != null && myClient.isRejected) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.error.withAlpha(20),
                        borderRadius: AppRadius.mdRadius,
                        border: Border.all(
                          color: AppColors.error.withAlpha(100),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.cancel_outlined,
                            color: AppColors.error,
                            size: 26,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Demande d\'accès refusée',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppColors.error,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Votre inscription dans la file d\'attente a été refusée par l\'administrateur.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Queue status summary
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm + 4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : AppColors.lightCard,
                      borderRadius: AppRadius.mdRadius,
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.people_alt_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '${queue.queueLength} client(s) dans la file',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(20),
                            borderRadius: AppRadius.pillRadius,
                          ),
                          child: const Text(
                            'Lecture seule',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Queue list (accepted clients only)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        if (queue.isLoading && queue.isEmpty) {
                          return const LoadingWidget();
                        }
                        if (queue.state == QueueState.empty || queue.isEmpty) {
                          return const EmptyStateWidget();
                        }

                        final clients = queue.clients;
                        return ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: clients.length,
                          itemBuilder: (context, index) {
                            final client = clients[index];
                            final isFirst = index == 0;
                            return ClientTile(
                              client: client,
                              position: index + 1,
                              isNowServing: isFirst,
                              onRemove: null, // Read-only for client role!
                            );
                          },
                        );
                      },
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
