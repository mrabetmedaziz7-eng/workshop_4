import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:waiting_room_app/models/app_connectivity.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/models/sync_status.dart';
import 'package:waiting_room_app/queue_provider.dart';
import 'package:waiting_room_app/repositories/clients_repository.dart';
import 'package:waiting_room_app/services/connectivity_service.dart';
import 'package:waiting_room_app/services/geolocation_service.dart';
import 'package:waiting_room_app/services/local_queue_service.dart';

class ControllableConnectivity implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();
  bool online;
  bool supabaseReachable;

  ControllableConnectivity({this.online = false, this.supabaseReachable = true});

  void setOnline(bool value) {
    online = value;
    _controller.add(value);
  }

  @override
  Stream<bool> get onlineChanges => _controller.stream;

  @override
  Stream<bool> get networkChanges => _controller.stream;

  @override
  Future<bool> get isOnline async => online;

  @override
  Future<bool> hasNetwork() async => online;

  @override
  Future<bool> isSupabaseAvailable() async => supabaseReachable;

  void dispose() => _controller.close();
}

class NullGeolocation implements GeolocationService {
  @override
  Future<Position?> getCurrentLocation() async => null;
}

class TrackingClientsRepository implements ClientsRepository {
  final StreamController<List<Client>> _controller =
      StreamController<List<Client>>.broadcast();
  final List<Client> remoteClients = [];
  final List<String> upsertedIds = [];
  final List<String> deletedIds = [];
  final Set<String> failUpsertIds = {};
  final Set<String> failDeleteIds = {};
  Completer<void>? upsertBlocker;

  void emit(List<Client> clients) {
    remoteClients
      ..clear()
      ..addAll(clients);
    _controller.add(List.unmodifiable(remoteClients));
  }

  @override
  Stream<List<Client>> watchClients() async* {
    yield List.unmodifiable(remoteClients);
    yield* _controller.stream;
  }

  @override
  Future<List<Client>> fetchPage({required int offset, required int limit}) async {
    if (offset >= remoteClients.length) return [];
    final end = (offset + limit).clamp(0, remoteClients.length);
    return List.unmodifiable(remoteClients.sublist(offset, end));
  }

  @override
  Future<void> insert(String name) async {}

  @override
  Future<void> upsert(Client client) async {
    if (upsertBlocker != null) {
      await upsertBlocker!.future;
    }
    if (failUpsertIds.contains(client.id)) {
      throw Exception('Upsert failed for ${client.id}');
    }
    upsertedIds.add(client.id);
    remoteClients.removeWhere((c) => c.id == client.id);
    remoteClients.add(client.copyWith(isSynced: true));
    _controller.add(List.unmodifiable(remoteClients));
  }

  @override
  Future<Client> registerOnServer(Client client) async {
    await upsert(client);
    return client.copyWith(isSynced: true);
  }

  @override
  Future<void> delete(String id) async {
    if (failDeleteIds.contains(id)) {
      throw Exception('Delete failed for $id');
    }
    deletedIds.add(id);
    remoteClients.removeWhere((c) => c.id == id);
    _controller.add(List.unmodifiable(remoteClients));
  }

  void dispose() => _controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LocalQueueService local;
  late ControllableConnectivity connectivity;
  late TrackingClientsRepository repository;
  late QueueProvider provider;
  int idCounter = 0;

  Future<QueueProvider> createProvider({
    bool online = false,
    bool supabaseReachable = true,
    LocalQueueService? existingLocal,
  }) async {
    local = existingLocal ?? LocalQueueService(inMemory: true);
    connectivity = ControllableConnectivity(
      online: online,
      supabaseReachable: supabaseReachable,
    );
    repository = TrackingClientsRepository();
    idCounter = 0;
    final p = QueueProvider.withServices(
      repository: repository,
      localQueueService: local,
      connectivityService: connectivity,
      geolocationService: NullGeolocation(),
      uuidGenerator: () => 'uuid-${++idCounter}',
    );
    await p.initialized;
    return p;
  }

  tearDown(() async {
    provider.dispose();
    connectivity.dispose();
    repository.dispose();
    await local.close();
  });

  test('loads pre-existing local SQLite rows on startup even when offline', () async {
    final preLocal = LocalQueueService(inMemory: true);
    await preLocal.insertClientLocally(
      Client(
        id: 'local-1',
        name: 'Cached Client',
        createdAt: DateTime.utc(2026, 1, 1),
        isSynced: false,
      ),
    );

    provider = await createProvider(online: false, existingLocal: preLocal);

    expect(provider.isLoading, isFalse);
    expect(provider.isOnline, isFalse);
    expect(provider.connectivityStatus, AppConnectivity.offline);
    expect(provider.clients.map((c) => c.name), ['Cached Client']);
    expect(provider.clients.first.isSynced, isFalse);
  });

  test('distinguishes backendUnavailable when device has network but Supabase fails', () async {
    provider = await createProvider(online: true, supabaseReachable: false);

    expect(provider.isOnline, isFalse);
    expect(provider.connectivityStatus, AppConnectivity.backendUnavailable);

    await provider.addClient('Queued Offline');
    expect(provider.clients.single.syncStatus, SyncStatus.pending);
    expect(repository.upsertedIds, isEmpty);
  });

  test('addClient while offline saves locally with uuid, updates UI, skips remote', () async {
    provider = await createProvider(online: false);

    final added = await provider.addClient('Offline Alice');

    expect(added, isTrue);
    expect(provider.clients.length, 1);
    expect(provider.clients.first.id, 'uuid-1');
    expect(provider.clients.first.name, 'Offline Alice');
    expect(provider.clients.first.syncStatus, SyncStatus.pending);
    expect(provider.pendingSyncCount, 1);
    expect(repository.upsertedIds, isEmpty);
  });

  test('offline removeClient deletes unsynced locally and marks synced as pendingDelete', () async {
    final preLocal = LocalQueueService(inMemory: true);
    await preLocal.insertClientLocally(
      Client(
        id: 'synced-1',
        name: 'Synced Bob',
        createdAt: DateTime.utc(2026, 1, 1),
        isSynced: true,
      ),
    );
    await preLocal.insertClientLocally(
      Client(
        id: 'unsynced-2',
        name: 'Unsynced Carol',
        createdAt: DateTime.utc(2026, 1, 2),
        isSynced: false,
      ),
    );

    provider = await createProvider(online: false, existingLocal: preLocal);
    expect(provider.clients.length, 2);

    await provider.removeClient('unsynced-2');
    expect(provider.clients.map((c) => c.id), ['synced-1']);
    expect(await local.getPendingDeletes(), isEmpty);

    await provider.nextClient();
    expect(provider.clients, isEmpty);
    expect((await local.getPendingDeletes()).map((c) => c.id), ['synced-1']);
    expect(repository.deletedIds, isEmpty);
  });

  test('auto-syncs unsynced inserts and pending deletes when connectivity returns', () async {
    final preLocal = LocalQueueService(inMemory: true);
    await preLocal.insertClientLocally(
      Client(
        id: 'synced-to-delete',
        name: 'To Delete',
        createdAt: DateTime.utc(2026, 1, 1),
        isSynced: true,
      ),
    );
    provider = await createProvider(online: false, existingLocal: preLocal);

    await provider.removeClient('synced-to-delete');
    await provider.addClient('New Offline Client');

    expect(provider.clients.length, 1);
    expect(provider.clients.first.isSynced, isFalse);

    connectivity.setOnline(true);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(provider.isOnline, isTrue);
    expect(repository.upsertedIds, ['uuid-1']);
    expect(repository.deletedIds, ['synced-to-delete']);
    expect(provider.clients.length, 1);
    expect(provider.clients.first.isSynced, isTrue);
    expect(await local.getPendingDeletes(), isEmpty);
  });

  test('remote stream merge preserves unsynced local rows and hides pending deletes', () async {
    final preLocal = LocalQueueService(inMemory: true);
    await preLocal.insertClientLocally(
      Client(
        id: 'pending-del',
        name: 'Pending Delete',
        createdAt: DateTime.utc(2026, 1, 1),
        isSynced: true,
        pendingDelete: true,
      ),
    );
    await preLocal.insertClientLocally(
      Client(
        id: 'local-unsynced',
        name: 'Local Unsynced',
        createdAt: DateTime.utc(2026, 1, 2),
        isSynced: false,
      ),
    );

    provider = await createProvider(online: false, existingLocal: preLocal);
    repository.failUpsertIds.add('local-unsynced');
    repository.failDeleteIds.add('pending-del');

    connectivity.setOnline(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    repository.emit([
      Client(
        id: 'pending-del',
        name: 'Pending Delete',
        createdAt: DateTime.utc(2026, 1, 1),
        isSynced: true,
      ),
      Client(
        id: 'remote-1',
        name: 'Remote User',
        createdAt: DateTime.utc(2026, 1, 3),
        isSynced: true,
      ),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      provider.clients.map((c) => c.id),
      ['local-unsynced', 'remote-1'],
    );
  });

  test('sync marks failed records and retries them on subsequent sync without duplicating', () async {
    provider = await createProvider(online: false);
    await provider.addClient('Fail First');
    await provider.addClient('Succeed Second');

    repository.failUpsertIds.add('uuid-1');
    connectivity.online = true;

    repository.upsertBlocker = Completer<void>();
    final s1 = provider.sync();
    final s2 = provider.sync();
    repository.upsertBlocker!.complete();
    await Future.wait([s1, s2]);

    expect(repository.upsertedIds, ['uuid-2']);
    var byId = {for (final c in provider.clients) c.id: c};
    expect(byId['uuid-1']?.syncStatus, SyncStatus.failed);
    expect(byId['uuid-2']?.syncStatus, SyncStatus.synced);

    // Retry once failure clears
    repository.failUpsertIds.remove('uuid-1');
    repository.upsertBlocker = null;
    await provider.sync();

    expect(repository.upsertedIds, ['uuid-2', 'uuid-1']);
    byId = {for (final c in provider.clients) c.id: c};
    expect(byId['uuid-1']?.syncStatus, SyncStatus.synced);
  });
}
