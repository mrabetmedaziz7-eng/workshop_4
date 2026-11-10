import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/models/client.dart';

void main() {
  group('Client Model Tests', () {
    test('fromMap and toMap round-trip preserves data', () {
      final now = DateTime.utc(2026, 11, 3, 14, 30, 0);
      final client = Client(
        id: 'client-123',
        name: 'John Doe',
        createdAt: now,
      );

      final map = client.toMap();
      expect(map['id'], 'client-123');
      expect(map['name'], 'John Doe');
      expect(map['created_at'], now.toIso8601String());

      final restored = Client.fromMap(map);
      expect(restored.id, client.id);
      expect(restored.name, client.name);
      expect(restored.createdAt.isAtSameMomentAs(client.createdAt), isTrue);
      expect(restored, equals(client));
    });

    test('fromMap handles DateTime instance directly in created_at', () {
      final now = DateTime.now();
      final map = {
        'id': 'abc-1',
        'name': 'Alice Smith',
        'created_at': now,
      };

      final client = Client.fromMap(map);
      expect(client.id, 'abc-1');
      expect(client.name, 'Alice Smith');
      expect(client.createdAt, equals(now));
    });

    test('fromMap handles null or missing values gracefully', () {
      final map = <String, dynamic>{};
      final client = Client.fromMap(map);

      expect(client.id, '');
      expect(client.name, '');
      expect(client.createdAt, isA<DateTime>());
    });

    test('copyWith updates specified fields', () {
      final client = Client(
        id: '1',
        name: 'Bob',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final updated = client.copyWith(name: 'Robert');
      expect(updated.id, '1');
      expect(updated.name, 'Robert');
      expect(updated.createdAt, client.createdAt);
    });

    test('toString includes key details', () {
      final client = Client(
        id: '1',
        name: 'Bob',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      expect(client.toString(), contains('Bob'));
      expect(client.toString(), contains('1'));
    });

    test('toMap excludes local-only fields is_synced and pending_delete', () {
      final client = Client(
        id: '1',
        name: 'Bob',
        createdAt: DateTime.utc(2026, 1, 1),
        lat: 36.8065,
        lng: 10.1815,
        isSynced: false,
        pendingDelete: true,
      );

      final remoteMap = client.toMap();
      expect(remoteMap['lat'], 36.8065);
      expect(remoteMap['lng'], 10.1815);
      expect(remoteMap.containsKey('is_synced'), isFalse);
      expect(remoteMap.containsKey('pending_delete'), isFalse);
    });

    test('toLocalMap and fromLocalMap round-trip preserves sync flags and coordinates', () {
      final client = Client(
        id: 'local-1',
        name: 'Local User',
        createdAt: DateTime.utc(2026, 1, 1, 12, 0),
        lat: 36.8065,
        lng: 10.1815,
        isSynced: false,
        pendingDelete: true,
      );

      final localMap = client.toLocalMap();
      expect(localMap['is_synced'], 0);
      expect(localMap['pending_delete'], 1);

      final restored = Client.fromLocalMap(localMap);
      expect(restored, equals(client));
    });

    test('copyWith can clear lat and lng to null', () {
      final client = Client(
        id: '1',
        name: 'Bob',
        createdAt: DateTime.utc(2026, 1, 1),
        lat: 10.0,
        lng: 20.0,
      );

      final cleared = client.copyWith(lat: null, lng: null);
      expect(cleared.lat, isNull);
      expect(cleared.lng, isNull);
    });
  });
}
