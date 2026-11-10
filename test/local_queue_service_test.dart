import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/models/sync_status.dart';
import 'package:waiting_room_app/services/local_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late LocalQueueService local;

  setUp(() async {
    local = LocalQueueService(inMemory: true);
    await local.database;
  });

  tearDown(() async {
    await local.close();
  });

  Client client(
    String id,
    DateTime created, {
    bool synced = false,
    SyncStatus? syncStatus,
  }) =>
      Client(
        id: id,
        name: id,
        createdAt: created,
        syncStatus: syncStatus ?? (synced ? SyncStatus.synced : SyncStatus.pending),
      );

  test('insert and order visible clients by created_at, excluding pending deletes', () async {
    await local.insertClientLocally(client('b', DateTime.utc(2026, 1, 2)));
    await local.insertClientLocally(client('a', DateTime.utc(2026, 1, 1)));
    await local.insertClientLocally(
      client('deleted', DateTime.utc(2026, 1, 3)).copyWith(pendingDelete: true),
    );
    final clients = await local.getClients();
    expect(clients.map((c) => c.id), ['a', 'b']);
  });

  test('gets pending and failed clients for retry and marks synced', () async {
    await local.insertClientLocally(client('one', DateTime.utc(2026, 1, 1)));
    await local.insertClientLocally(
      client('two', DateTime.utc(2026, 1, 2), syncStatus: SyncStatus.failed),
    );
    await local.insertClientLocally(
      client('three', DateTime.utc(2026, 1, 3), syncStatus: SyncStatus.syncing),
    );

    expect((await local.getPendingClients()).map((c) => c.id), ['one', 'two']);

    await local.markClientAsSynced('one');
    await local.updateSyncStatus('two', SyncStatus.synced);
    expect(await local.getPendingClients(), isEmpty);
  });

  test('marks pending delete and lists it', () async {
    await local.insertClientLocally(client('gone', DateTime.utc(2026), synced: true));
    await local.markPendingDelete('gone');
    expect((await local.getPendingDeletes()).single.id, 'gone');
    expect(await local.getClients(), isEmpty);
  });

  test('removeSyncedNotIn preserves unsynced rows', () async {
    await local.insertClientLocally(client('synced', DateTime.utc(2026), synced: true));
    await local.insertClientLocally(client('local', DateTime.utc(2026)));
    await local.removeSyncedNotIn(<String>{});
    expect((await local.getClients()).map((c) => c.id), ['local']);
  });

  test('upsertSyncedFromRemote preserves unsynced and pendingDelete rows', () async {
    await local.insertClientLocally(client('unsynced', DateTime.utc(2026, 1, 1), synced: false));
    await local.insertClientLocally(
      client('pending', DateTime.utc(2026, 1, 2), synced: true).copyWith(pendingDelete: true),
    );

    await local.upsertSyncedFromRemote([
      client('unsynced', DateTime.utc(2026, 1, 1), synced: true).copyWith(name: 'RemoteOverwrite'),
      client('pending', DateTime.utc(2026, 1, 2), synced: true),
      client('remote', DateTime.utc(2026, 1, 3), synced: true),
    ]);

    final visible = await local.getClients();
    expect(visible.map((c) => c.id), ['unsynced', 'remote']);
    expect(visible.first.isSynced, isFalse);
    expect((await local.getClientById('pending'))?.pendingDelete, isTrue);
  });

  test('memory fallback (web mode) mirrors SQLite ordering, sync flags, and merge rules', () async {
    final webLocal = LocalQueueService(useMemoryFallback: true);
    await webLocal.insertClientLocally(client('b', DateTime.utc(2026, 1, 2)));
    await webLocal.insertClientLocally(client('a', DateTime.utc(2026, 1, 1)));
    await webLocal.insertClientLocally(client('pending', DateTime.utc(2026, 1, 3), synced: true));
    await webLocal.markPendingDelete('pending');
    await webLocal.markClientAsSynced('a');

    expect((await webLocal.getClients()).map((c) => c.id), ['a', 'b']);
    expect((await webLocal.getUnsyncedClients()).map((c) => c.id), ['b']);
    expect((await webLocal.getPendingDeletes()).map((c) => c.id), ['pending']);

    await webLocal.upsertSyncedFromRemote([
      client('b', DateTime.utc(2026, 1, 2), synced: true),
      client('pending', DateTime.utc(2026, 1, 3), synced: true),
      client('remote', DateTime.utc(2026, 1, 4), synced: true),
    ]);
    await webLocal.removeSyncedNotIn({'remote'});

    expect((await webLocal.getClients()).map((c) => c.id), ['b', 'remote']);
    await webLocal.close();
  });
}
