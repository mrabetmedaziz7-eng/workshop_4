import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/queue_provider.dart';
import 'package:waiting_room_app/repositories/clients_repository.dart';
import 'package:waiting_room_app/screens/waiting_room_screen.dart';
import 'package:waiting_room_app/services/connectivity_service.dart';
import 'package:waiting_room_app/services/geolocation_service.dart';
import 'package:waiting_room_app/services/local_queue_service.dart';
import 'package:waiting_room_app/widgets/client_tile.dart';
import 'package:waiting_room_app/widgets/empty_state.dart';

class _TestConnectivity implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();
  bool online;
  _TestConnectivity(this.online);

  @override
  Stream<bool> get onlineChanges => _controller.stream;
  @override
  Future<bool> get isOnline async => online;
  void dispose() => _controller.close();
}

class _TestGeo implements GeolocationService {
  @override
  Future<Position?> getCurrentLocation() async => null;
}

class _TestRepo implements ClientsRepository {
  final _controller = StreamController<List<Client>>.broadcast();
  @override
  Stream<List<Client>> watchClients() => _controller.stream;
  @override
  Future<void> insert(String name) async {}
  @override
  Future<void> upsert(Client client) async {}
  @override
  Future<void> delete(String id) async {}
  void dispose() => _controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('EmptyStateWidget renders message and helper text',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyStateWidget(),
        ),
      ),
    );

    expect(find.text('No one in queue yet...'), findsOneWidget);
    expect(
      find.text(
        'Add client names above to start managing your queue in real time.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.people_outline_rounded), findsOneWidget);
  });

  testWidgets('ClientTile renders coordinates formatted to 4 decimals',
      (WidgetTester tester) async {
    final client = Client(
      id: '1',
      name: 'Alice',
      createdAt: DateTime.utc(2026, 1, 1, 10, 30),
      lat: 36.80649,
      lng: 10.18153,
      isSynced: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientTile(
            client: client,
            position: 1,
            isNowServing: true,
            onRemove: () {},
          ),
        ),
      ),
    );

    expect(find.text('📍 36.8065, 10.1815'), findsOneWidget);
    expect(find.text('Waiting to sync'), findsNothing);
  });

  testWidgets('ClientTile renders Location not captured when lat/lng are null',
      (WidgetTester tester) async {
    final client = Client(
      id: '2',
      name: 'Bob',
      createdAt: DateTime.utc(2026, 1, 1, 10, 35),
      isSynced: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientTile(
            client: client,
            position: 2,
            isNowServing: false,
            onRemove: () {},
          ),
        ),
      ),
    );

    expect(find.text('📍 Location not captured'), findsOneWidget);
  });

  testWidgets('ClientTile renders Waiting to sync indicator when unsynced',
      (WidgetTester tester) async {
    final client = Client(
      id: '3',
      name: 'Charlie',
      createdAt: DateTime.utc(2026, 1, 1, 10, 40),
      isSynced: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientTile(
            client: client,
            position: 1,
            isNowServing: true,
            onRemove: () {},
          ),
        ),
      ),
    );

    expect(find.text('Waiting to sync'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('WaitingRoomScreen shows offline banner and Offline pill when offline',
      (WidgetTester tester) async {
    final connectivity = _TestConnectivity(false);
    final repo = _TestRepo();
    final local = LocalQueueService(inMemory: true);
    final provider = await tester.runAsync(() async {
      final p = QueueProvider(
        repository: repo,
        localQueueService: local,
        connectivityService: connectivity,
        geolocationService: _TestGeo(),
      );
      await p.initialized;
      return p;
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<QueueProvider>.value(
        value: provider!,
        child: const MaterialApp(
          home: WaitingRoomScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Offline · changes will sync when connected'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);

    await tester.runAsync(() async {
      provider.dispose();
      connectivity.dispose();
      repo.dispose();
      await local.close();
    });
  });
}
