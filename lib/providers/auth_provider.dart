import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import '../repositories/auth_repository.dart';

class AuthProvider extends ChangeNotifier {
  final AuthRepository _repository;
  StreamSubscription<AuthState>? _authSubscription;

  UserProfile? _profile;
  bool _isLoading = true;
  String? _errorMessage;

  AuthProvider({AuthRepository? repository, bool autoInit = true})
      : _repository = repository ?? SupabaseAuthRepository() {
    _authSubscription = _repository.onAuthStateChange.listen((data) async {
      final session = data.session;
      if (session == null) {
        _profile = null;
        _isLoading = false;
        notifyListeners();
      } else {
        await refreshProfile();
      }
    });

    if (autoInit) {
      initialize();
    }
  }

  UserProfile? get profile => _profile;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _profile != null && _repository.currentUser != null;
  bool get isAdmin => _profile?.isAdmin ?? false;
  bool get isClient => _profile?.isClient ?? false;
  String? get currentUserId => _repository.currentUser?.id;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    try {
      if (_repository.currentUser != null) {
        _profile = await _repository.getCurrentProfile();
      } else {
        _profile = null;
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshProfile() async {
    try {
      _profile = await _repository.getCurrentProfile();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.signIn(email: email, password: password);
      _profile = await _repository.getCurrentProfile();
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String name,
    double? lat,
    double? lng,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.signUp(
        email: email,
        password: password,
        name: name,
        lat: lat,
        lng: lng,
      );
      _profile = await _repository.getCurrentProfile();
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _repository.signOut();
      _profile = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
