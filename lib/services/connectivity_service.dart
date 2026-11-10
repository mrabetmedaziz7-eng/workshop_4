import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class ConnectivityService {
  Stream<bool> get onlineChanges;
  Future<bool> get isOnline;
  Stream<bool> get networkChanges;
  Future<bool> hasNetwork();
  Future<bool> isSupabaseAvailable();
}

class DeviceConnectivityService implements ConnectivityService {
  final Connectivity _connectivity;
  final SupabaseClient? _customSupabase;

  DeviceConnectivityService({
    Connectivity? connectivity,
    SupabaseClient? supabase,
  })  : _connectivity = connectivity ?? Connectivity(),
        _customSupabase = supabase;

  static bool _isConnected(List<ConnectivityResult> results) =>
      results.isNotEmpty && results.any((result) => result != ConnectivityResult.none);

  @override
  Stream<bool> get networkChanges =>
      _connectivity.onConnectivityChanged.map(_isConnected);

  @override
  Stream<bool> get onlineChanges => networkChanges;

  @override
  Future<bool> hasNetwork() async {
    final results = await _connectivity.checkConnectivity();
    return _isConnected(results);
  }

  @override
  Future<bool> get isOnline => hasNetwork();

  @override
  Future<bool> isSupabaseAvailable() async {
    try {
      final client = _customSupabase ?? Supabase.instance.client;
      await client
          .from('clients')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 5));
      return true;
    } catch (_) {
      return false;
    }
  }
}
