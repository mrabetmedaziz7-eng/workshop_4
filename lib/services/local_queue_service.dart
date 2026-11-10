import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/client.dart';

class LocalQueueService {
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
          version: 1,
          onCreate: _onCreate,
          singleInstance: false,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final path = databasePath ?? p.join(directory.path, 'waiting_room.db');
        _database = await openDatabase(path, version: 1, onCreate: _onCreate);
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
        created_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        pending_delete INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  List<Client> _sorted(Iterable<Client> clients) =>
      clients.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Future<void> insertClientLocally(Client client) async {
    if (useMemoryFallback) {
      _memoryStore[client.id] = client;
      return;
    }
    await (await database).insert('local_clients', client.toLocalMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
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
    final rows = await (await database).query('local_clients',
        where: 'pending_delete = ?', whereArgs: const [0], orderBy: 'created_at ASC');
    return rows.map(Client.fromLocalMap).toList();
  }

  Future<List<Client>> getUnsyncedClients() async {
    if (useMemoryFallback) {
      return _sorted(_memoryStore.values.where((c) => !c.isSynced && !c.pendingDelete));
    }
    return (await (await database).query(
      'local_clients',
      where: 'is_synced = ? AND pending_delete = ?',
      whereArgs: const [0, 0],
      orderBy: 'created_at ASC',
    ))
        .map(Client.fromLocalMap)
        .toList();
  }

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

  Future<void> markClientAsSynced(String id) async {
    if (useMemoryFallback) {
      final existing = _memoryStore[id];
      if (existing != null) {
        _memoryStore[id] = existing.copyWith(isSynced: true);
      }
      return;
    }
    await (await database).update('local_clients', {'is_synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markPendingDelete(String id) async {
    if (useMemoryFallback) {
      final existing = _memoryStore[id];
      if (existing != null) {
        _memoryStore[id] = existing.copyWith(pendingDelete: true);
      }
      return;
    }
    await (await database).update('local_clients', {'pending_delete': 1}, where: 'id = ?', whereArgs: [id]);
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
        _memoryStore[client.id] = client.copyWith(isSynced: true, pendingDelete: false);
      }
      return;
    }
    final db = await database;
    await db.transaction((txn) async {
      for (final client in clients) {
        final existing = await txn.query('local_clients', where: 'id = ?', whereArgs: [client.id], limit: 1);
        if (existing.isNotEmpty && (existing.first['is_synced'] == 0 || existing.first['pending_delete'] == 1)) continue;
        final synced = client.copyWith(isSynced: true, pendingDelete: false);
        await txn.insert('local_clients', synced.toLocalMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> removeSyncedNotIn(Set<String> ids) async {
    if (useMemoryFallback) {
      _memoryStore.removeWhere((id, client) => client.isSynced && !client.pendingDelete && !ids.contains(id));
      return;
    }
    final db = await database;
    final rows = await db.query('local_clients',
        where: 'is_synced = ? AND pending_delete = ?', whereArgs: const [1, 0]);
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
