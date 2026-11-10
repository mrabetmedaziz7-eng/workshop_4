import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/queue_provider.dart';
import 'package:waiting_room_app/repositories/clients_repository.dart';
import 'package:waiting_room_app/services/connectivity_service.dart';
import 'package:waiting_room_app/services/geolocation_service.dart';
import 'package:waiting_room_app/services/local_queue_service.dart';

class _OnlineConnectivity implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();
  @override
  Stream<bool> get onlineChanges => _controller.stream;
  @override
  Stream<bool> get networkChanges => _controller.stream;
  @override
  Future<bool> get isOnline async => true;
  @override
  Future<bool> hasNetwork() async => true;
  @override
  Future<bool> isSupabaseAvailable() async => true;
  void dispose() => _controller.close();
}

class _ConfigurableGeolocation implements GeolocationService {
  Position? positionToReturn;
  bool shouldThrow = false;

  @override
  Future<Position?> getCurrentLocation() async {
    if (shouldThrow) {
      throw Exception('GPS hardware failure');
    }
    return positionToReturn;
  }
}

class _InMemoryRepo implements ClientsRepository {
  final _controller = StreamController<List<Client>>.broadcast();
  final List<Client> items = [];

  @override
  Stream<List<Client>> watchClients() async* {
    yield List.unmodifiable(items);
    yield* _controller.stream;
  }

  @override
  Future<List<Client>> fetchPage({required int offset, required int limit}) async =>
      List.unmodifiable(items);

  @override
  Future<void> insert(String name) async {}

  @override
  Future<void> upsert(Client client) async {
    items.removeWhere((c) => c.id == client.id);
    items.add(client.copyWith(isSynced: true));
    _controller.add(List.unmodifiable(items));
  }

  @override
  Future<Client> registerOnServer(Client client) async {
    await upsert(client);
    return client.copyWith(isSynced: true);
  }

  @override
  Future<void> delete(String id) async {
    items.removeWhere((c) => c.id == id);
    _controller.add(List.unmodifiable(items));
  }

  void dispose() => _controller.close();
}

Position _position(double lat, double lng, {double accuracy = 10.0}) => Position(
      longitude: lng,
      latitude: lat,
      timestamp: DateTime.utc(2026, 1, 1),
      accuracy: accuracy,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LocalQueueService local;
  late _OnlineConnectivity connectivity;
  late _ConfigurableGeolocation geo;
  late _InMemoryRepo repo;
  late QueueProvider provider;

  setUp(() async {
    local = LocalQueueService(inMemory: true);
    connectivity = _OnlineConnectivity();
    geo = _ConfigurableGeolocation();
    repo = _InMemoryRepo();
    provider = QueueProvider.withServices(
      repository: repo,
      localQueueService: local,
      connectivityService: connectivity,
      geolocationService: geo,
      uuidGenerator: () => 'geo-uuid-1',
    );
    await provider.initialized;
  });

  tearDown(() async {
    provider.dispose();
    connectivity.dispose();
    repo.dispose();
    await local.close();
  });

  test('addClient captures valid coordinates, accuracy, and timestamp from GeolocationService', () async {
    geo.positionToReturn = _position(36.8065, 10.1815, accuracy: 8.5);

    final added = await provider.addClient('Tunis Client');
    await provider.sync();

    expect(added, isTrue);
    expect(provider.clients.single.lat, 36.8065);
    expect(provider.clients.single.lng, 10.1815);
    expect(provider.clients.single.locationAccuracy, 8.5);
    expect(provider.clients.single.locationCapturedAt, isNotNull);
    expect(repo.items.single.lat, 36.8065);
    expect(repo.items.single.lng, 10.1815);
    expect(repo.items.single.locationAccuracy, 8.5);
  });

  test('addClient stores null coordinates when GeolocationService returns null', () async {
    geo.positionToReturn = null;

    final added = await provider.addClient('No GPS Client');
    await provider.sync();

    expect(added, isTrue);
    expect(provider.clients.single.lat, isNull);
    expect(provider.clients.single.lng, isNull);
    expect(provider.clients.single.locationAccuracy, isNull);
  });

  test('addClient rejects (0, 0) coordinates and stores null instead', () async {
    geo.positionToReturn = _position(0.0, 0.0);

    final added = await provider.addClient('Null Island Client');
    await provider.sync();

    expect(added, isTrue);
    expect(provider.clients.single.lat, isNull);
    expect(provider.clients.single.lng, isNull);
  });

  test('addClient allows 0 latitude when longitude is non-zero (equator)', () async {
    geo.positionToReturn = _position(0.0, 12.3456);

    final added = await provider.addClient('Equator Client');
    await provider.sync();

    expect(added, isTrue);
    expect(provider.clients.single.lat, 0.0);
    expect(provider.clients.single.lng, 12.3456);
  });

  test('addClient handles GeolocationService exception gracefully without failing', () async {
    geo.shouldThrow = true;

    final added = await provider.addClient('Resilient Client');
    await provider.sync();

    expect(added, isTrue);
    expect(provider.clients.single.name, 'Resilient Client');
    expect(provider.clients.single.lat, isNull);
    expect(provider.clients.single.lng, isNull);
  });
}
