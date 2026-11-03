import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/queue_provider.dart';
import 'package:waiting_room_app/repositories/clients_repository.dart';

class FakeClientsRepository implements ClientsRepository {
  final StreamController<List<Client>> _controller =
      StreamController<List<Client>>.broadcast();
  final List<Client> _storage = [];

  bool shouldThrowOnInsert = false;
  bool shouldThrowOnDelete = false;

  void emit(List<Client> clients) {
    _storage.clear();
    _storage.addAll(clients);
    _controller.add(List.unmodifiable(_storage));
  }

  void emitError(Object error) {
    _controller.addError(error);
  }

  @override
  Stream<List<Client>> watchClients() async* {
    yield List.unmodifiable(_storage);
    yield* _controller.stream;
  }

  int _idCounter = 0;

  @override
  Future<void> insert(String name) async {
    if (shouldThrowOnInsert) {
      throw Exception('Database insert error');
    }
    _idCounter++;
    final client = Client(
      id: 'id-$_idCounter',
      name: name,
      createdAt: DateTime.now(),
    );
    _storage.add(client);
    _controller.add(List.unmodifiable(_storage));
  }

  @override
  Future<void> delete(String id) async {
    if (shouldThrowOnDelete) {
      throw Exception('Database delete error');
    }
    _storage.removeWhere((c) => c.id == id);
    _controller.add(List.unmodifiable(_storage));
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  group('QueueProvider Tests with FakeClientsRepository', () {
    late FakeClientsRepository repository;
    late QueueProvider provider;

    setUp(() {
      repository = FakeClientsRepository();
      provider = QueueProvider(repository: repository);
    });

    tearDown(() {
      provider.dispose();
      repository.dispose();
    });

    test('initial state has empty clients and loads stream', () async {
      await pumpEventQueue();
      expect(provider.clients, isEmpty);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('addClient ignores empty or whitespace-only names', () async {
      await pumpEventQueue();
      final emptyResult = await provider.addClient('');
      final whitespaceResult = await provider.addClient('    \t\n  ');

      expect(emptyResult, isFalse);
      expect(whitespaceResult, isFalse);
      expect(provider.clients, isEmpty);
    });

    test('addClient trims leading and trailing whitespace', () async {
      await pumpEventQueue();
      final result = await provider.addClient('   Alice Wonderland   ');

      expect(result, isTrue);
      await pumpEventQueue();
      expect(provider.clients.length, 1);
      expect(provider.clients.first.name, 'Alice Wonderland');
    });

    test('removeClient removes the specified client', () async {
      await pumpEventQueue();
      await provider.addClient('Client 1');
      await provider.addClient('Client 2');
      await pumpEventQueue();

      expect(provider.clients.length, 2);
      final firstId = provider.clients.first.id;

      await provider.removeClient(firstId);
      await pumpEventQueue();

      expect(provider.clients.length, 1);
      expect(provider.clients.first.name, 'Client 2');
    });

    test('nextClient removes the first client in queue', () async {
      await pumpEventQueue();
      await provider.addClient('First in Line');
      await provider.addClient('Second in Line');
      await pumpEventQueue();

      expect(provider.currentClient?.name, 'First in Line');
      await provider.nextClient();
      await pumpEventQueue();

      expect(provider.clients.length, 1);
      expect(provider.currentClient?.name, 'Second in Line');
    });

    test('nextClient does nothing when queue is empty', () async {
      await pumpEventQueue();
      expect(provider.clients, isEmpty);

      // Should complete without error
      await provider.nextClient();
      expect(provider.clients, isEmpty);
      expect(provider.errorMessage, isNull);
    });

    test('stream error sets errorMessage and clears loading', () async {
      await pumpEventQueue();
      repository.emitError(Exception('Realtime connection lost'));
      await pumpEventQueue();

      expect(provider.errorMessage, contains('Realtime connection lost'));
      expect(provider.isLoading, isFalse);
    });

    test('insert failure sets errorMessage and rethrows', () async {
      await pumpEventQueue();
      repository.shouldThrowOnInsert = true;

      expect(
        () => provider.addClient('Test Name'),
        throwsA(isA<Exception>()),
      );
      await pumpEventQueue();
      expect(provider.errorMessage, contains('Database insert error'));
    });

    test('delete failure sets errorMessage and rethrows', () async {
      repository.shouldThrowOnDelete = true;

      expect(
        () => provider.removeClient('non-existent-id'),
        throwsA(isA<Exception>()),
      );
      await pumpEventQueue();
      expect(provider.errorMessage, contains('Database delete error'));
    });

    test('clients list is unmodifiable', () async {
      await pumpEventQueue();
      await provider.addClient('Alice');
      await pumpEventQueue();

      final list = provider.clients;
      expect(
        () => list.clear(),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
