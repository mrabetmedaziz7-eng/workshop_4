import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/models/user_profile.dart';
import 'package:waiting_room_app/providers/auth_provider.dart';
import 'package:waiting_room_app/queue_provider.dart';
import 'package:waiting_room_app/repositories/auth_repository.dart';
import 'package:waiting_room_app/repositories/clients_repository.dart';
import 'package:waiting_room_app/screens/auth_gate.dart';
import 'package:waiting_room_app/screens/auth_screen.dart';
import 'package:waiting_room_app/screens/client_waiting_room_screen.dart';
import 'package:waiting_room_app/screens/waiting_room_screen.dart';
import 'package:waiting_room_app/services/connectivity_service.dart';
import 'package:waiting_room_app/services/geolocation_service.dart';
import 'package:waiting_room_app/services/local_queue_service.dart';

class _FakeAuthRepo implements AuthRepository {
  final _controller = StreamController<AuthState>.broadcast();
  UserProfile? mockProfile;
  User? mockUser;

  @override
  User? get currentUser => mockUser;

  @override
  Stream<AuthState> get onAuthStateChange => _controller.stream;

  @override
  Future<UserProfile?> getCurrentProfile() async => mockProfile;

  @override
  Future<AuthResponse> signIn({required String email, required String password}) async {
    mockProfile = UserProfile(
      id: 'test-user-id',
      name: 'Test Client',
      role: 'client',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    mockUser = const User(
      id: 'test-user-id',
      appMetadata: {},
      userMetadata: {'name': 'Test Client'},
      aud: 'authenticated',
      createdAt: '2026-01-01',
    );
    return AuthResponse(session: null, user: mockUser);
  }

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
    double? lat,
    double? lng,
  }) async {
    mockProfile = UserProfile(
      id: 'test-user-id',
      name: name,
      role: 'client',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    mockUser = User(
      id: 'test-user-id',
      appMetadata: const {},
      userMetadata: {'name': name},
      aud: 'authenticated',
      createdAt: '2026-01-01',
    );
    return AuthResponse(session: null, user: mockUser);
  }

  @override
  Future<void> signOut() async {
    mockProfile = null;
    mockUser = null;
  }
}

class _TestClientsRepo implements ClientsRepository {
  final List<Client> items = [];
  final _controller = StreamController<List<Client>>.broadcast();

  @override
  Stream<List<Client>> watchClients() => _controller.stream;
  @override
  Future<List<Client>> fetchPage({required int offset, required int limit}) async => items;
  @override
  Future<void> insert(String name) async {}
  @override
  Future<void> upsert(Client client) async {}
  @override
  Future<Client> registerOnServer(Client client) async => client;
  @override
  Future<void> delete(String id) async {
    items.removeWhere((c) => c.id == id);
  }
  @override
  Future<void> acceptClient(String id) async {
    final idx = items.indexWhere((c) => c.id == id);
    if (idx != -1) {
      items[idx] = items[idx].copyWith(status: 'accepted');
    }
  }
  @override
  Future<void> rejectClient(String id) async {
    final idx = items.indexWhere((c) => c.id == id);
    if (idx != -1) {
      items[idx] = items[idx].copyWith(status: 'rejected');
    }
  }
  @override
  Future<void> markNotified() async {}
}

class _ConstConnectivity implements ConnectivityService {
  @override
  Stream<bool> get onlineChanges => const Stream.empty();
  @override
  Future<bool> get isOnline async => true;
  @override
  Stream<bool> get networkChanges => const Stream.empty();
  @override
  Future<bool> hasNetwork() async => true;
  @override
  Future<bool> isSupabaseAvailable() async => true;
}

class _NoLocation implements GeolocationService {
  @override
  Future<Position?> getCurrentLocation() async => null;
}

void main() {
  group('UserProfile Model Tests', () {
    test('Serializes and deserializes correctly', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0);
      final profile = UserProfile(
        id: 'u1',
        name: 'Sarah Connor',
        role: 'admin',
        createdAt: now,
      );

      final map = profile.toMap();
      expect(map['role'], 'admin');
      expect(map['name'], 'Sarah Connor');

      final fromMap = UserProfile.fromMap(map);
      expect(fromMap.id, 'u1');
      expect(fromMap.name, 'Sarah Connor');
      expect(fromMap.role, 'admin');
      expect(fromMap.isAdmin, isTrue);
      expect(fromMap.isClient, isFalse);
    });

    test('Defaults to client role', () {
      final profile = UserProfile.fromMap({'id': 'u2', 'name': 'John'});
      expect(profile.role, 'client');
      expect(profile.isClient, isTrue);
      expect(profile.isAdmin, isFalse);
    });
  });

  group('Client Model Status & Notification Tests', () {
    test('Default status is accepted and notified is false', () {
      final client = Client(
        id: 'c1',
        name: 'Alice',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      expect(client.status, 'accepted');
      expect(client.isAccepted, isTrue);
      expect(client.isPending, isFalse);
      expect(client.isRejected, isFalse);
      expect(client.notified, isFalse);
    });

    test('Serialization includes user_id, status, notified', () {
      final client = Client(
        id: 'c2',
        name: 'Bob',
        createdAt: DateTime.utc(2026, 1, 1),
        userId: 'u99',
        status: 'pending',
        notified: true,
      );

      final map = client.toSupabaseMap();
      expect(map['user_id'], 'u99');
      expect(map['status'], 'pending');
      expect(map['notified'], isTrue);

      final restored = Client.fromSupabaseMap(map);
      expect(restored.userId, 'u99');
      expect(restored.status, 'pending');
      expect(restored.isPending, isTrue);
      expect(restored.notified, isTrue);
    });
  });

  group('QueueProvider Status Filtering & Actions', () {
    test('filters clients: main queue shows accepted only, pendingClients shows pending', () async {
      final repo = _TestClientsRepo();
      final local = LocalQueueService(useMemoryFallback: true);

      final acceptedClient = Client(
        id: '1',
        name: 'Accepted Client',
        createdAt: DateTime.utc(2026, 1, 1, 10, 0),
        status: 'accepted',
      );
      final pendingClient = Client(
        id: '2',
        name: 'Pending Client',
        createdAt: DateTime.utc(2026, 1, 1, 10, 1),
        status: 'pending',
      );

      await local.insertClientLocally(acceptedClient);
      await local.insertClientLocally(pendingClient);

      final provider = QueueProvider(
        repository: repo,
        localQueueService: local,
        connectivityService: _ConstConnectivity(),
        geolocationService: _NoLocation(),
      );

      await provider.initialized;

      expect(provider.clients.length, 1);
      expect(provider.clients.first.name, 'Accepted Client');
      expect(provider.pendingClients.length, 1);
      expect(provider.pendingClients.first.name, 'Pending Client');

      // Admin accepts pending client
      await provider.acceptClient('2');
      expect(provider.pendingClients.length, 0);
      expect(provider.clients.length, 2);

      provider.dispose();
    });
  });

  group('AuthGate Navigation Tests', () {
    testWidgets('renders AuthScreen when not authenticated', (tester) async {
      final fakeAuth = _FakeAuthRepo();
      final authProvider = AuthProvider(repository: fakeAuth, autoInit: false);
      await authProvider.initialize();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: authProvider),
          ],
          child: const MaterialApp(
            home: AuthGate(),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(AuthScreen), findsOneWidget);
    });

    testWidgets('renders ClientWaitingRoomScreen when authenticated as client', (tester) async {
      final fakeAuth = _FakeAuthRepo();
      fakeAuth.mockProfile = UserProfile(
        id: 'user-client',
        name: 'Client User',
        role: 'client',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      fakeAuth.mockUser = const User(
        id: 'user-client',
        appMetadata: {},
        userMetadata: {'name': 'Client User'},
        aud: 'authenticated',
        createdAt: '2026-01-01',
      );

      final authProvider = AuthProvider(repository: fakeAuth, autoInit: false);
      await authProvider.initialize();

      final repo = _TestClientsRepo();
      final local = LocalQueueService(useMemoryFallback: true);
      final queueProvider = QueueProvider(
        repository: repo,
        localQueueService: local,
        connectivityService: _ConstConnectivity(),
        geolocationService: _NoLocation(),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: authProvider),
            ChangeNotifierProvider.value(value: queueProvider),
          ],
          child: const MaterialApp(
            home: AuthGate(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(ClientWaitingRoomScreen), findsOneWidget);

      queueProvider.dispose();
    });

    testWidgets('renders WaitingRoomScreen (admin) when authenticated as admin', (tester) async {
      final fakeAuth = _FakeAuthRepo();
      fakeAuth.mockProfile = UserProfile(
        id: 'user-admin',
        name: 'Admin User',
        role: 'admin',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      fakeAuth.mockUser = const User(
        id: 'user-admin',
        appMetadata: {},
        userMetadata: {'name': 'Admin User'},
        aud: 'authenticated',
        createdAt: '2026-01-01',
      );

      final authProvider = AuthProvider(repository: fakeAuth, autoInit: false);
      await authProvider.initialize();

      final repo = _TestClientsRepo();
      final local = LocalQueueService(useMemoryFallback: true);
      final queueProvider = QueueProvider(
        repository: repo,
        localQueueService: local,
        connectivityService: _ConstConnectivity(),
        geolocationService: _NoLocation(),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: authProvider),
            ChangeNotifierProvider.value(value: queueProvider),
          ],
          child: const MaterialApp(
            home: AuthGate(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(WaitingRoomScreen), findsOneWidget);

      queueProvider.dispose();
    });
  });
}
