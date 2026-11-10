import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/client.dart';
import '../models/sync_status.dart';

class LocalQueueService {
  static const int schemaVersion = 2;

  final Database? providedDatabase;
  final String? databasePath;
  final bool inMemory;
  final bool useMemoryFallback;
  final Map<String, Client> _memoryStore = {};
  Database? _database;
  Future<Database>? _openingDatabase;

  LocalQueueService({
    this.providedDatabase,
    this.databasePath,
    this.inMemory = false,
    bool? useMemoryFallback,
  })  : _database = providedDatabase,
        useMemoryFallback = useMemoryFallback ?? (kIsWeb && providedDatabase == null);

  Future<Database> get database {
    if (_database != null) return Future.value(_database!);
    return _openingDatabase ??= _open();
  }

  Future<Database> _open() async {
    try {
      if (inMemory) {
        _database = await openDatabase(
          inMemoryDatabasePath,
          version: schemaVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
          singleInstance: false,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final path = databasePath ?? p.join(directory.path, 'waiting_room.db');
        _database = await openDatabase(
          path,
          version: schemaVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
      }
      return _database!;
    } finally {
      _openingDatabase = null;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE local_clients (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        lat REAL,
        lng REAL,
        location_accuracy_m REAL,
        location_captured_at TEXT,
        created_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        pending_delete INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE local_clients ADD COLUMN location_accuracy_m REAL');
      await db.execute('ALTER TABLE local_clients ADD COLUMN location_captured_at TEXT');
      await db.execute(
        "ALTER TABLE local_clients ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending'",
      );
      await db.execute(
        "UPDATE local_clients SET sync_status = CASE WHEN is_synced = 1 THEN 'synced' ELSE 'pending' END",
      );
    }
  }

  List<Client> _sorted(Iterable<Client> clients) =>
      clients.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Future<void> insertClientLocally(Client client) async {
    if (useMemoryFallback) {
      _memoryStore[client.id] = client;
      return;
    }
    await (await database).insert(
      'local_clients',
      client.toLocalMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Client?> getClientById(String id) async {
    if (useMemoryFallback) {
      return _memoryStore[id];
    }
    final rows = await (await database).query(
      'local_clients',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Client.fromLocalMap(rows.first);
  }

  Future<List<Client>> getClients() async {
    if (useMemoryFallback) {
      return _sorted(_memoryStore.values.where((c) => !c.pendingDelete));
    }
    final rows = await (await database).query(
      'local_clients',
      where: 'pending_delete = ?',
      whereArgs: const [0],
      orderBy: 'created_at ASC',
    );
    return rows.map(Client.fromLocalMap).toList();
  }

  /// Returns both `pending` and `failed` local entries (excluding pending deletes) for retry.
  Future<List<Client>> getPendingClients() async {
    if (useMemoryFallback) {
      return _sorted(
        _memoryStore.values.where(
          (c) =>
              !c.pendingDelete &&
              (c.syncStatus == SyncStatus.pending || c.syncStatus == SyncStatus.failed),
        ),
      );
    }
    return (await (await database).query(
      'local_clients',
      where: '(sync_status = ? OR sync_status = ?) AND pending_delete = ?',
      whereArgs: const ['pending', 'failed', 0],
      orderBy: 'created_at ASC',
    ))
        .map(Client.fromLocalMap)
        .toList();
  }

  Future<List<Client>> getUnsyncedClients() => getPendingClients();

  Future<List<Client>> getPendingDeletes() async {
    if (useMemoryFallback) {
      return _sorted(_memoryStore.values.where((c) => c.pendingDelete));
    }
    return (await (await database).query(
      'local_clients',
      where: 'pending_delete = ?',
      whereArgs: const [1],
      orderBy: 'created_at ASC',
    ))
        .map(Client.fromLocalMap)
        .toList();
  }

  Future<void> updateSyncStatus(String id, SyncStatus status) async {
    if (useMemoryFallback) {
      final existing = _memoryStore[id];
      if (existing != null) {
        _memoryStore[id] = existing.copyWith(syncStatus: status);
      }
      return;
    }
    await (await database).update(
      'local_clients',
      {
        'sync_status': status.name,
        'is_synced': status == SyncStatus.synced ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markClientAsSynced(String id) => updateSyncStatus(id, SyncStatus.synced);

  Future<void> markPendingDelete(String id) async {
    if (useMemoryFallback) {
      final existing = _memoryStore[id];
      if (existing != null) {
        _memoryStore[id] = existing.copyWith(pendingDelete: true);
      }
      return;
    }
    await (await database).update(
      'local_clients',
      {'pending_delete': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteLocally(String id) async {
    if (useMemoryFallback) {
      _memoryStore.remove(id);
      return;
    }
    await (await database).delete('local_clients', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertSyncedFromRemote(List<Client> clients) async {
    if (useMemoryFallback) {
      for (final client in clients) {
        final existing = _memoryStore[client.id];
        if (existing != null && (!existing.isSynced || existing.pendingDelete)) continue;
        _memoryStore[client.id] =
            client.copyWith(syncStatus: SyncStatus.synced, pendingDelete: false);
      }
      return;
    }
    final db = await database;
    await db.transaction((txn) async {
      for (final client in clients) {
        final existing = await txn.query(
          'local_clients',
          where: 'id = ?',
          whereArgs: [client.id],
          limit: 1,
        );
        if (existing.isNotEmpty &&
            (existing.first['is_synced'] == 0 ||
                existing.first['sync_status'] != SyncStatus.synced.name ||
                existing.first['pending_delete'] == 1)) {
          continue;
        }
        final synced = client.copyWith(syncStatus: SyncStatus.synced, pendingDelete: false);
        await txn.insert(
          'local_clients',
          synced.toLocalMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> removeSyncedNotIn(Set<String> ids) async {
    if (useMemoryFallback) {
      _memoryStore.removeWhere(
        (id, client) => client.isSynced && !client.pendingDelete && !ids.contains(id),
      );
      return;
    }
    final db = await database;
    final rows = await db.query(
      'local_clients',
      where: 'is_synced = ? AND pending_delete = ?',
      whereArgs: const [1, 0],
    );
    for (final row in rows) {
      final id = row['id'] as String;
      if (!ids.contains(id)) await deleteLocally(id);
    }
  }

  Future<void> close() async {
    _memoryStore.clear();
    if (_openingDatabase != null) {
      await _openingDatabase;
    }
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}
