import 'package:connectivity_plus/connectivity_plus.dart';

abstract class ConnectivityService {
  Stream<bool> get onlineChanges;
  Future<bool> get isOnline;
}

class DeviceConnectivityService implements ConnectivityService {
  final Connectivity _connectivity;
  DeviceConnectivityService({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  @override
  Stream<bool> get onlineChanges => _connectivity.onConnectivityChanged.map(
      (results) => results.isNotEmpty && results.any((result) => result != ConnectivityResult.none));

  @override
  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();
    return results.isNotEmpty && results.any((result) => result != ConnectivityResult.none);
  }
}
