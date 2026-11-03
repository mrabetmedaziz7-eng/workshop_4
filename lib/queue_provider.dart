import 'dart:async';
import 'package:flutter/foundation.dart';
import 'models/client.dart';
import 'repositories/clients_repository.dart';

class QueueProvider extends ChangeNotifier {
  final ClientsRepository _repository;
  StreamSubscription<List<Client>>? _subscription;

  List<Client> _clients = [];
  bool _isLoading = true;
  String? _errorMessage;

  QueueProvider({ClientsRepository? repository})
      : _repository = repository ?? SupabaseClientsRepository() {
    startListening();
  }

  List<Client> get clients => List.unmodifiable(_clients);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => _clients.isEmpty;
  int get queueLength => _clients.length;
  Client? get currentClient => _clients.isNotEmpty ? _clients.first : null;

  void startListening() {
    _subscription?.cancel();
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    _subscription = _repository.watchClients().listen(
      (data) {
        _clients = data;
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
      },
      onError: (error) {
        _isLoading = false;
        _errorMessage = error.toString();
        notifyListeners();
      },
    );
  }

  void retry() {
    startListening();
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  Future<bool> addClient(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    try {
      await _repository.insert(trimmed);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeClient(String id) async {
    try {
      await _repository.delete(id);
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> nextClient() async {
    if (_clients.isEmpty) {
      return;
    }
    final firstId = _clients.first.id;
    await removeClient(firstId);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
