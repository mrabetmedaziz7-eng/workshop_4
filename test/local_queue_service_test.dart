import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/services/local_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late LocalQueueService local;
  late dynamic db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''CREATE TABLE local_clients (id TEXT PRIMARY KEY, name TEXT NOT NULL, lat REAL, lng REAL, created_at TEXT NOT NULL, is_synced INTEGER NOT NULL DEFAULT 0, pending_delete INTEGER NOT NULL DEFAULT 0)''');
    local = LocalQueueService(providedDatabase: db);
  });

  tearDown(() async {
    await db.close();
    await local.close();
  });

  Client client(String id, DateTime created, {bool synced = false}) => Client(id: id, name: id, createdAt: created, isSynced: synced);

  test('insert and order visible clients by created_at, excluding pending deletes', () async {
    await local.insertClientLocally(client('b', DateTime.utc(2026, 1, 2)));
    await local.insertClientLocally(client('a', DateTime.utc(2026, 1, 1)));
    await local.insertClientLocally(client('deleted', DateTime.utc(2026, 1, 3)).copyWith(pendingDelete: true));
    final clients = await local.getClients();
    expect(clients.map((c) => c.id), ['a', 'b']);
  });

  test('gets unsynced and marks synced', () async {
    await local.insertClientLocally(client('one', DateTime.utc(2026)));
    expect((await local.getUnsyncedClients()).map((c) => c.id), ['one']);
    await local.markClientAsSynced('one');
    expect(await local.getUnsyncedClients(), isEmpty);
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
