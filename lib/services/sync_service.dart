import 'dart:developer' as developer;

import '../models/sync_status.dart';
import '../repositories/clients_repository.dart';
import 'local_queue_service.dart';

class SyncService {
  final LocalQueueService _local;
  final ClientsRepository _repository;
  bool _isSyncing = false;

  SyncService(this._local, this._repository);

  bool get isSyncing => _isSyncing;

  Future<void> synchronize({bool Function()? isDisposed}) async {
    if (_isSyncing || (isDisposed?.call() ?? false)) return;
    _isSyncing = true;
    try {
      final pendingRecords = await _local.getPendingClients();
      for (final client in pendingRecords) {
        if (isDisposed?.call() ?? false) return;
        try {
          await _local.updateSyncStatus(client.id, SyncStatus.syncing);
          await _repository.registerOnServer(client.copyWith(syncStatus: SyncStatus.synced));
          if (isDisposed?.call() ?? false) return;
          await _local.updateSyncStatus(client.id, SyncStatus.synced);
        } catch (error, stackTrace) {
          developer.log(
            'Failed to sync client ${client.id}',
            error: error,
            stackTrace: stackTrace,
          );
          if (!(isDisposed?.call() ?? false)) {
            await _local.updateSyncStatus(client.id, SyncStatus.failed);
          }
        }
      }

      for (final client in await _local.getPendingDeletes()) {
        if (isDisposed?.call() ?? false) return;
        try {
          await _repository.delete(client.id);
          if (isDisposed?.call() ?? false) return;
          await _local.deleteLocally(client.id);
        } catch (error, stackTrace) {
          developer.log(
            'Failed to sync delete ${client.id}',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    } finally {
      _isSyncing = false;
    }
  }
}

