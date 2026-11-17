import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/app_connectivity.dart';
import '../models/client.dart';
import '../models/queue_state.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../queue_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/add_client_bar.dart';
import '../widgets/client_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_widget.dart';
import '../widgets/offline_banner.dart';

class WaitingRoomScreen extends StatelessWidget {
  const WaitingRoomScreen({super.key});

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

  Future<void> _handleNextClient(BuildContext context) async {
    final provider = context.read<QueueProvider>();
    final current = provider.currentClient;
    if (current == null) return;

    try {
      await provider.nextClient();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    color: Colors.white),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('Served & removed: ${current.name}'),
                ),
              ],
            ),
            backgroundColor: AppColors.accent,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to call next client: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleRemoveClient(
      BuildContext context, String id, String name) async {
    final provider = context.read<QueueProvider>();
    try {
      await provider.removeClient(id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed $name from queue'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove $name: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleAcceptClient(
      BuildContext context, Client client) async {
    final provider = context.read<QueueProvider>();
    try {
      await provider.acceptClient(client.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${client.name} accepté(e) dans la file'),
            backgroundColor: AppColors.accent,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleRejectClient(
      BuildContext context, Client client) async {
    final provider = context.read<QueueProvider>();
    try {
      await provider.rejectClient(client.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${client.name} refusé(e)'),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    String adminName = 'Admin';
    try {
      final auth = context.watch<AuthProvider>();
      adminName = auth.profile?.name ?? 'Admin';
    } catch (_) {}

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
                Icons.admin_panel_settings_rounded,
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
                  'Admin: $adminName',
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
          // Realtime / Offline status indicator
          Consumer<QueueProvider>(
            builder: (context, queue, _) {
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
                AppConnectivity.online =>
                  isRealtimeReady ? 'Realtime' : 'Syncing...',
              };

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(isDark ? 35 : 25),
                  borderRadius: AppRadius.pillRadius,
                  border: Border.all(
                    color: statusColor.withAlpha(80),
                  ),
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
              );
            },
          ),
          const SizedBox(width: AppSpacing.xs),
          // Logout button
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Se déconnecter',
            onPressed: () async {
              try {
                await context.read<AuthProvider>().signOut();
              } catch (_) {}
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
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Offline / Backend availability banner
                  Consumer<QueueProvider>(
                    builder: (context, queue, _) {
                      final connectivity =
                          _effectiveConnectivity(context, queue);
                      return OfflineBanner(status: connectivity);
                    },
                  ),
                  // Add Client Input Bar (Admin manual add)
                  const AddClientBar(),
                  const SizedBox(height: AppSpacing.md),

                  // Section "Demandes en attente" (pending requests)
                  Consumer<QueueProvider>(
                    builder: (context, queue, _) {
                      final pending = queue.pendingClients;
                      if (pending.isEmpty) return const SizedBox.shrink();

                      return Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withAlpha(15),
                          borderRadius: AppRadius.lgRadius,
                          border: Border.all(
                            color: AppColors.warning.withAlpha(90),
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.pending_actions_rounded,
                                  color: AppColors.warning,
                                  size: 20,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  'Demandes en attente (${pending.length})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: AppColors.warning,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            ...pending.map((client) {
                              final timeStr = DateFormat('HH:mm')
                                  .format(client.createdAt.toLocal());
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.sm,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkCard
                                      : Colors.white,
                                  borderRadius: AppRadius.mdRadius,
                                  border: Border.all(
                                    color: isDark
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            client.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '$timeStr · ${client.locationText}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? AppColors.darkTextSecondary
                                                  : AppColors
                                                      .lightTextSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Accept button
                                    IconButton.filled(
                                      onPressed: () =>
                                          _handleAcceptClient(context, client),
                                      icon: const Icon(Icons.check, size: 18),
                                      style: IconButton.styleFrom(
                                        backgroundColor: AppColors.accent,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(36, 36),
                                      ),
                                      tooltip: 'Accepter',
                                    ),
                                    const SizedBox(width: 8),
                                    // Reject button
                                    IconButton.filled(
                                      onPressed: () =>
                                          _handleRejectClient(context, client),
                                      icon: const Icon(Icons.close, size: 18),
                                      style: IconButton.styleFrom(
                                        backgroundColor: AppColors.error,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(36, 36),
                                      ),
                                      tooltip: 'Refuser',
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  ),

                  // Action Header: Next Client button & Queue Count
                  Consumer<QueueProvider>(
                    builder: (context, queue, _) {
                      final hasClients = queue.clients.isNotEmpty;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkCard
                              : AppColors.primary.withAlpha(12),
                          borderRadius: AppRadius.lgRadius,
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkBorder
                                : AppColors.primary.withAlpha(30),
                          ),
                        ),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Queue Status',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${queue.queueLength} ${queue.queueLength == 1 ? 'client' : 'clients'} waiting',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            // Next Client Action Button
                            FilledButton.icon(
                              onPressed: hasClients
                                  ? () => _handleNextClient(context)
                                  : null,
                              icon:
                                  const Icon(Icons.skip_next_rounded, size: 20),
                              label: const Text('Next Client'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                disabledBackgroundColor:
                                    isDark ? Colors.white10 : Colors.black12,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppRadius.mdRadius,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Queue content list / loading / error / empty state
                  Expanded(
                    child: Consumer<QueueProvider>(
                      builder: (context, queue, _) {
                        // 1. Loading state
                        if ((queue.isLoading ||
                                queue.state == QueueState.loading) &&
                            queue.clients.isEmpty) {
                          return const LoadingWidget(
                            message: 'Connecting to waiting room...',
                          );
                        }

                        // 2. Error state
                        if (queue.errorMessage != null &&
                            queue.clients.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding:
                                        const EdgeInsets.all(AppSpacing.md),
                                    decoration: BoxDecoration(
                                      color: AppColors.errorContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.cloud_off_rounded,
                                      color: AppColors.error,
                                      size: 36,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Text(
                                    'Connection error',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    queue.errorMessage!,
                                    style: theme.textTheme.bodyMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  OutlinedButton.icon(
                                    onPressed: () => queue.retry(),
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Try Again'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        // 3. Empty state
                        if (queue.isEmpty) {
                          return const EmptyStateWidget();
                        }

                        // 4. Clients list (with optional pagination footer)
                        final showLoadMore = queue.clients.length >= 20 &&
                            (queue.hasMore || queue.isLoadingMore);
                        return RefreshIndicator(
                          onRefresh: queue.retry,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            itemCount:
                                queue.clients.length + (showLoadMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == queue.clients.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.md,
                                  ),
                                  child: Center(
                                    child: queue.isLoadingMore
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : TextButton(
                                            onPressed: queue.loadMore,
                                            child: const Text('Load More'),
                                          ),
                                  ),
                                );
                              }

                              final client = queue.clients[index];
                              final isFirst = index == 0;
                              return ClientTile(
                                client: client,
                                position: index + 1,
                                isNowServing: isFirst,
                                onRemove: () => _handleRemoveClient(
                                  context,
                                  client.id,
                                  client.name,
                                ),
                              );
                            },
                          ),
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
