import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';

abstract class AuthRepository {
  User? get currentUser;
  Stream<AuthState> get onAuthStateChange;
  Future<UserProfile?> getCurrentProfile();
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
    double? lat,
    double? lng,
  });
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  });
  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  final SupabaseClient? _customClient;

  SupabaseAuthRepository({SupabaseClient? client}) : _customClient = client;

  SupabaseClient get _client => _customClient ?? Supabase.instance.client;

  @override
  User? get currentUser => _client.auth.currentUser;

  @override
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  @override
  Future<UserProfile?> getCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (response != null) {
        return UserProfile.fromMap(response);
      }
    } catch (_) {
      // In case table or row is temporarily unavailable, fallback below
    }

    // Default client profile fallback
    return UserProfile(
      id: user.id,
      name: (user.userMetadata?['name'] as String?) ??
          user.email?.split('@').first ??
          'Client',
      role: 'client',
      createdAt: DateTime.tryParse(user.createdAt) ?? DateTime.now().toUtc(),
    );
  }

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
    double? lat,
    double? lng,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'name': name},
    );

    final user = response.user;
    if (user != null) {
      // Automatically register a pending client entry for this account
      try {
        await _client.from('clients').insert({
          'name': name,
          'user_id': user.id,
          'status': 'pending',
          'notified': false,
          'lat': lat,
          'lng': lng,
        });
      } catch (_) {
        // Ignored if user already has an entry or table not yet migrated
      }
    }

    return response;
  }

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
