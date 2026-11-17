import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/models/app_connectivity.dart';
import 'package:waiting_room_app/providers/connectivity_provider.dart';
import 'package:waiting_room_app/services/connectivity_service.dart';

class _MockableConnectivityService implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();
  bool networkOn = true;
  bool supabaseUp = true;
  int supabaseChecks = 0;

  void emitNetwork(bool value) {
    networkOn = value;
    _controller.add(value);
  }

  @override
  Stream<bool> get networkChanges => _controller.stream;

  @override
  Stream<bool> get onlineChanges => _controller.stream;

  @override
  Future<bool> hasNetwork() async => networkOn;

  @override
  Future<bool> get isOnline async => networkOn;

  @override
  Future<bool> isSupabaseAvailable() async {
    supabaseChecks++;
    return supabaseUp;
  }

  void dispose() => _controller.close();
}

void main() {
  late _MockableConnectivityService service;
  late ConnectivityProvider provider;

  setUp(() {
    service = _MockableConnectivityService();
  });

  tearDown(() {
    provider.dispose();
    service.dispose();
  });

  test('transitions to offline immediately when network is lost', () async {
    service.networkOn = false;
    provider = ConnectivityProvider(
      service,
      debounceDuration: const Duration(milliseconds: 20),
    );
    await provider.initialized;

    expect(provider.status, AppConnectivity.offline);
    expect(provider.isOnline, isFalse);
  });

  test('debounces backend check and reports online when Supabase responds', () async {
    service.networkOn = true;
    service.supabaseUp = true;
    provider = ConnectivityProvider(
      service,
      debounceDuration: const Duration(milliseconds: 25),
    );
    await provider.initialized;

    expect(provider.status, AppConnectivity.checking);
    await Future<void>.delayed(const Duration(milliseconds: 45));

    expect(provider.status, AppConnectivity.online);
    expect(provider.isOnline, isTrue);
    expect(service.supabaseChecks, 1);
  });

  test('distinguishes backendUnavailable when network is on but Supabase is down', () async {
    service.networkOn = true;
    service.supabaseUp = false;
    provider = ConnectivityProvider(
      service,
      debounceDuration: const Duration(milliseconds: 10),
    );
    await provider.initialized;
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(provider.status, AppConnectivity.backendUnavailable);
    expect(provider.isOnline, isFalse);
  });
}

