import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'models/app_connectivity.dart';
import 'models/client.dart';
import 'models/queue_state.dart';
import 'models/sync_status.dart';
import 'repositories/clients_repository.dart';
import 'services/connectivity_service.dart';
import 'services/geolocation_service.dart';
import 'services/local_queue_service.dart';
import 'services/sync_service.dart';

class QueueProvider extends ChangeNotifier {
  final ClientsRepository _repository;
  final LocalQueueService _local;
  final GeolocationService _geolocation;
  final ConnectivityService _connectivity;
  late final SyncService _syncService;
  final String Function() _uuid;
  final int pageSize;

  StreamSubscription<List<Client>>? _remoteSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  Future<void>? _initFuture;
  Future<void>? _syncFuture;
  Future<void>? _remoteMergeFuture;
  bool _syncInProgress = false;

  List<Client> _clients = [];
  QueueState _state = QueueState.loading;
  AppConnectivity _connectivityStatus = AppConnectivity.checking;
  bool _isLoading = true;
  bool _isOnline = true;
  String? _errorMessage;
  bool _streamSubscribed = false;
  bool _disposed = false;

  int _page = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  QueueProvider({
    ClientsRepository? repository,
    LocalQueueService? localQueueService,
    GeolocationService? geolocationService,
    ConnectivityService? connectivityService,
    SyncService? syncService,
    String Function()? uuidGenerator,
    Uuid? uuid,
    this.pageSize = 20,
    bool autoInitialize = true,
  })  : _repository = repository ?? SupabaseClientsRepository(),
        _local = localQueueService ?? LocalQueueService(),
        _geolocation = geolocationService ?? GeolocatorService(),
        _connectivity = connectivityService ?? DeviceConnectivityService(),
        _uuid = uuidGenerator ?? (() => (uuid ?? const Uuid()).v4()) {
    _syncService = syncService ?? SyncService(_local, _repository);
    if (autoInitialize) {
      _initFuture = initialize();
    }
  }

  /// Convenience constructor used when sharing an explicitly provided storage/sync service.
  factory QueueProvider.withServices({
    required ClientsRepository repository,
    required LocalQueueService localQueueService,
    required GeolocationService geolocationService,
    required ConnectivityService connectivityService,
    String Function()? uuidGenerator,
    int pageSize = 20,
    bool autoInitialize = true,
  }) {
    return QueueProvider(
      repository: repository,
      localQueueService: localQueueService,
      geolocationService: geolocationService,
      connectivityService: connectivityService,
      syncService: SyncService(localQueueService, repository),
      uuidGenerator: uuidGenerator,
      pageSize: pageSize,
      autoInitialize: autoInitialize,
    );
  }

  Future<void> get initialized => _initFuture ?? Future.value();
  List<Client> get clients => List.unmodifiable(_clients);
  QueueState get state => _state;
  AppConnectivity get connectivityStatus => _connectivityStatus;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
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

    await _updateConnectivityStatus();
    if (_disposed) return;
    _notify();

    if (_isOnline) {
      await sync();
      if (_disposed) return;
      _subscribeRemote();
    }

    _connectivitySubscription ??= _connectivity.networkChanges.listen((hasNet) async {
      if (_disposed) return;
      if (!hasNet) {
        _isOnline = false;
        _connectivityStatus = AppConnectivity.offline;
        _notify();
        await _remoteSubscription?.cancel();
        _remoteSubscription = null;
        _streamSubscribed = false;
        return;
      }

      final backendUp = await _connectivity.isSupabaseAvailable();
      if (_disposed) return;
      _isOnline = backendUp;
      _connectivityStatus =
          backendUp ? AppConnectivity.online : AppConnectivity.backendUnavailable;
      if (backendUp) {
        _errorMessage = null;
      }
      _notify();

      if (backendUp) {
        await sync();
        if (!_disposed) _subscribeRemote();
      }
    });
  }

  Future<void> _updateConnectivityStatus() async {
    final hasNet = await _connectivity.hasNetwork();
    if (_disposed) return;
    if (!hasNet) {
      _isOnline = false;
      _connectivityStatus = AppConnectivity.offline;
      return;
    }
    final backendUp = await _connectivity.isSupabaseAvailable();
    if (_disposed) return;
    _isOnline = backendUp;
    _connectivityStatus =
        backendUp ? AppConnectivity.online : AppConnectivity.backendUnavailable;
  }

  Future<void> _refreshLocal() async {
    if (_disposed) return;
    _clients = await _local.getClients();
    _isLoading = false;
    _state = _clients.isEmpty ? QueueState.empty : QueueState.loaded;
    _notify();
  }

  void _subscribeRemote() {
    if (_streamSubscribed || _disposed) return;
    _streamSubscribed = true;
    _remoteSubscription = _repository.watchClients().listen(
      (remote) {
        if (_disposed) return;
        _remoteMergeFuture = (_remoteMergeFuture ?? Future.value())
            .catchError((_) {})
            .then((_) => _mergeRemote(remote));
      },
      onError: (Object error) {
        if (_disposed) return;
        _errorMessage = error.toString();
        _isLoading = false;
        if (_clients.isEmpty) {
          _state = QueueState.error;
        }
        _streamSubscribed = false;
        unawaited(_remoteSubscription?.cancel());
        _remoteSubscription = null;
        _notify();
      },
    );
  }

  Future<void> _mergeRemote(List<Client> remote) async {
    try {
      if (_disposed) return;
      _errorMessage = null;
      await _local.upsertSyncedFromRemote(remote);
      if (_disposed) return;
      await _local.removeSyncedNotIn(remote.map((client) => client.id).toSet());
      if (!_disposed) await _refreshLocal();
    } catch (_) {
      if (!_disposed) rethrow;
    }
  }

  Future<void> fetchInitialQueue() async {
    _state = QueueState.loading;
    _isLoading = true;
    _page = 0;
    _hasMore = true;
    _errorMessage = null;
    _notify();

    try {
      final data = await _repository.fetchPage(offset: 0, limit: pageSize);
      if (_disposed) return;
      await _local.upsertSyncedFromRemote(data);
      if (_disposed) return;
      _clients = data;
      _isLoading = false;
      _state = _clients.isEmpty ? QueueState.empty : QueueState.loaded;
      if (data.length < pageSize) _hasMore = false;
    } catch (_) {
      if (_disposed) return;
      _isLoading = false;
      _errorMessage = 'Failed to load queue';
      _state = QueueState.error;
    } finally {
      _notify();
    }
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore || _disposed) return;
    _isLoadingMore = true;
    _notify();

    try {
      _page++;
      final newClients = await _repository.fetchPage(
        offset: _page * pageSize,
        limit: pageSize,
      );
      if (_disposed) return;
      final existingIds = _clients.map((c) => c.id).toSet();
      final uniqueNewClients =
          newClients.where((c) => !existingIds.contains(c.id)).toList();

      if (uniqueNewClients.isNotEmpty) {
        await _local.upsertSyncedFromRemote(uniqueNewClients);
        if (_disposed) return;
        _clients = [..._clients, ...uniqueNewClients];
        _state = QueueState.loaded;
      }
      if (newClients.length < pageSize) _hasMore = false;
    } catch (_) {
      _page--;
    } finally {
      _isLoadingMore = false;
      _notify();
    }
  }

  void handleRealtimeInsert(Client client) {
    final exists = _clients.any((c) => c.id == client.id);
    if (!exists) {
      final updated = [..._clients, client]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _clients = updated;
      if (_state == QueueState.empty || _state == QueueState.initial) {
        _state = QueueState.loaded;
      }
      _notify();
    }
  }

  Future<bool> addClient(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;

    double? lat;
    double? lng;
    double? accuracy;
    DateTime? capturedAt;
    try {
      final position = await _geolocation.getCurrentLocation();
      if (position != null && !(position.latitude == 0 && position.longitude == 0)) {
        lat = position.latitude;
        lng = position.longitude;
        accuracy = position.accuracy;
        capturedAt = DateTime.now().toUtc();
      }
    } catch (_) {
      // Geolocation is optional and must never block registration.
    }

    if (_disposed) return false;

    final client = Client(
      id: _uuid(),
      name: trimmed,
      createdAt: DateTime.now().toUtc(),
      lat: lat,
      lng: lng,
      locationAccuracy: accuracy,
      locationCapturedAt: capturedAt,
      syncStatus: SyncStatus.pending,
    );
    await _local.insertClientLocally(client);
    await _refreshLocal();

    if (_isOnline && !_disposed) {
      unawaited(sync());
    }
    return true;
  }

  Future<void> sync() {
    if (_syncInProgress || _syncService.isSyncing || _disposed) {
      return _syncFuture ?? Future.value();
    }
    _syncInProgress = true;
    _syncFuture = _runSync();
    return _syncFuture!;
  }

  Future<void> _runSync() async {
    try {
      await _updateConnectivityStatus();
      if (_disposed) return;
      if (!_isOnline) {
        await _refreshLocal();
        return;
      }

      await _syncService.synchronize(isDisposed: () => _disposed);
      if (!_disposed) await _refreshLocal();
    } finally {
      _syncInProgress = false;
      _notify();
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
        // The deletion remains pending and will be retried by SyncService.
      }
    }
  }

  Future<void> nextClient() async {
    if (_clients.isEmpty) return;
    await removeClient(_clients.first.id);
  }

  Future<void> retry() async {
    _errorMessage = null;
    await _updateConnectivityStatus();
    if (_disposed) return;
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
      if (_remoteMergeFuture != null) _remoteMergeFuture!.catchError((_) {}),
    ];
    if (pending.isEmpty) {
      unawaited(_local.close());
    } else {
      unawaited(Future.wait(pending).whenComplete(() => _local.close()));
    }
    super.dispose();
  }
}
