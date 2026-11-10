import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'models/client.dart';
import 'repositories/clients_repository.dart';
import 'services/connectivity_service.dart';
import 'services/geolocation_service.dart';
import 'services/local_queue_service.dart';

class QueueProvider extends ChangeNotifier {
  final ClientsRepository _repository;
  final LocalQueueService _local;
  final GeolocationService _geolocation;
  final ConnectivityService _connectivity;
  final String Function() _uuid;

  StreamSubscription<List<Client>>? _remoteSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  Future<void>? _initFuture;
  Future<void>? _syncFuture;
  List<Client> _clients = [];
  bool _isLoading = true;
  bool _isOnline = true;
  String? _errorMessage;
  bool _syncInProgress = false;
  bool _streamSubscribed = false;
  bool _disposed = false;

  QueueProvider({
    ClientsRepository? repository,
    LocalQueueService? localQueueService,
    GeolocationService? geolocationService,
    ConnectivityService? connectivityService,
    String Function()? uuidGenerator,
    Uuid? uuid,
  })  : _repository = repository ?? SupabaseClientsRepository(),
        _local = localQueueService ?? LocalQueueService(),
        _geolocation = geolocationService ?? GeolocatorService(),
        _connectivity = connectivityService ?? DeviceConnectivityService(),
        _uuid = uuidGenerator ?? (() => (uuid ?? const Uuid()).v4()) {
    _initFuture = initialize();
  }

  Future<void> get initialized => _initFuture ?? Future.value();
  List<Client> get clients => List.unmodifiable(_clients);
  bool get isLoading => _isLoading;
  bool get isOnline => _isOnline;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => _clients.isEmpty;
  int get queueLength => _clients.length;
  int get pendingSyncCount => _clients.where((client) => !client.isSynced).length;
  int get unsyncedCount => pendingSyncCount;
  Client? get currentClient => _clients.isNotEmpty ? _clients.first : null;

  Future<void> initialize() async {
    await _refreshLocal();
    if (_disposed) return;

    _isOnline = await _connectivity.isOnline;
    if (_disposed) return;
    _notify();

    if (_isOnline) {
      await sync();
      if (_disposed) return;
      _subscribeRemote();
    }

    _connectivitySubscription ??= _connectivity.onlineChanges.listen((online) async {
      if (_disposed) return;
      _isOnline = online;
      if (online) {
        _errorMessage = null;
      }
      _notify();

      if (online) {
        await sync();
        if (!_disposed) _subscribeRemote();
      } else {
        await _remoteSubscription?.cancel();
        _remoteSubscription = null;
        _streamSubscribed = false;
      }
    });
  }

  Future<void> _refreshLocal() async {
    if (_disposed) return;
    _clients = await _local.getClients();
    _isLoading = false;
    _notify();
  }

  void _subscribeRemote() {
    if (_streamSubscribed || _disposed) return;
    _streamSubscribed = true;
    _remoteSubscription = _repository.watchClients().listen(
      (remote) async {
        if (_disposed) return;
        _errorMessage = null;
        await _local.upsertSyncedFromRemote(remote);
        if (_disposed) return;
        await _local.removeSyncedNotIn(remote.map((client) => client.id).toSet());
        if (!_disposed) await _refreshLocal();
      },
      onError: (Object error) {
        if (_disposed) return;
        _errorMessage = error.toString();
        _isLoading = false;
        _streamSubscribed = false;
        unawaited(_remoteSubscription?.cancel());
        _remoteSubscription = null;
        _notify();
      },
    );
  }

  Future<bool> addClient(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;

    double? lat;
    double? lng;
    try {
      final position = await _geolocation.getCurrentLocation();
      if (position != null && !(position.latitude == 0 && position.longitude == 0)) {
        lat = position.latitude;
        lng = position.longitude;
      }
    } catch (_) {
      // Geolocation failure must never block adding a client.
    }

    if (_disposed) return false;

    final client = Client(
      id: _uuid(),
      name: trimmed,
      createdAt: DateTime.now().toUtc(),
      lat: lat,
      lng: lng,
      isSynced: false,
    );
    await _local.insertClientLocally(client);
    await _refreshLocal();

    if (_isOnline && !_disposed) {
      unawaited(sync());
    }
    return true;
  }

  Future<void> sync() {
    if (_syncInProgress || _disposed) return _syncFuture ?? Future.value();
    _syncFuture = _runSync();
    return _syncFuture!;
  }

  Future<void> _runSync() async {
    _syncInProgress = true;
    try {
      final online = await _connectivity.isOnline;
      if (_disposed) return;
      _isOnline = online;
      if (!online) {
        await _refreshLocal();
        return;
      }

      for (final client in await _local.getUnsyncedClients()) {
        if (_disposed) return;
        try {
          await _repository.upsert(client.copyWith(isSynced: true));
          if (_disposed) return;
          await _local.markClientAsSynced(client.id);
        } catch (error, stackTrace) {
          developer.log(
            'Failed to sync client ${client.id}',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      for (final client in await _local.getPendingDeletes()) {
        if (_disposed) return;
        try {
          await _repository.delete(client.id);
          if (_disposed) return;
          await _local.deleteLocally(client.id);
        } catch (error, stackTrace) {
          developer.log(
            'Failed to sync delete ${client.id}',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      if (!_disposed) await _refreshLocal();
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> removeClient(String id) async {
    final client = await _local.getClientById(id);
    if (client == null || _disposed) return;

    if (!client.isSynced) {
      await _local.deleteLocally(id);
      await _refreshLocal();
      return;
    }

    await _local.markPendingDelete(id);
    await _refreshLocal();

    if (_isOnline && !_disposed) {
      try {
        await _repository.delete(id);
        if (!_disposed) {
          await _local.deleteLocally(id);
        }
      } catch (_) {
        // The deletion remains pending and will be retried by sync().
      }
    }
  }

  Future<void> nextClient() async {
    if (_clients.isEmpty) return;
    await removeClient(_clients.first.id);
  }

  Future<void> retry() async {
    _errorMessage = null;
    _notify();
    if (_isOnline) {
      _subscribeRemote();
    }
    await sync();
  }

  void clearError() {
    _errorMessage = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_remoteSubscription?.cancel());
    unawaited(_connectivitySubscription?.cancel());
    final pending = <Future<void>>[
      if (_initFuture != null) _initFuture!.catchError((_) {}),
      if (_syncFuture != null) _syncFuture!.catchError((_) {}),
    ];
    if (pending.isEmpty) {
      unawaited(_local.close());
    } else {
      unawaited(Future.wait(pending).whenComplete(() => _local.close()));
    }
    super.dispose();
  }
}
