import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/client.dart';

abstract class ClientsRepository {
  Stream<List<Client>> watchClients();
  Future<List<Client>> fetchPage({required int offset, required int limit});
  Future<void> insert(String name);
  Future<void> upsert(Client client);
  Future<Client> registerOnServer(Client client);
  Future<void> delete(String id);
}

class SupabaseClientsRepository implements ClientsRepository {
  final SupabaseClient? _customClient;
  SupabaseClientsRepository({SupabaseClient? client}) : _customClient = client;
  SupabaseClient get _client => _customClient ?? Supabase.instance.client;

  @override
  Stream<List<Client>> watchClients() {
    return _client
        .from('clients')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true)
        .map((records) => records.map(Client.fromSupabaseMap).toList());
  }

  @override
  Future<List<Client>> fetchPage({required int offset, required int limit}) async {
    final rows = await _client
        .from('clients')
        .select()
        .order('created_at', ascending: true)
        .range(offset, offset + limit - 1);
    return rows
        .map<Client>((row) => Client.fromSupabaseMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  @override
  Future<void> insert(String name) async {
    await _client.from('clients').insert({'name': name});
  }

  @override
  Future<void> upsert(Client client) async {
    try {
      await _client
          .from('clients')
          .upsert(client.toSupabaseMap(includeExtendedLocation: true), onConflict: 'id');
    } on PostgrestException catch (error) {
      // Fallback if Workshop 6 optional location_accuracy_m / location_captured_at columns are not yet migrated.
      if (error.code == '42703' || error.code == 'PGRST204') {
        await _client
            .from('clients')
            .upsert(client.toSupabaseMap(includeExtendedLocation: false), onConflict: 'id');
        return;
      }
      rethrow;
    }
  }

  @override
  Future<Client> registerOnServer(Client client) async {
    try {
      final result = await _client.rpc(
        'register_queue_client',
        params: {
          'p_id': client.id,
          'p_name': client.name,
          'p_lat': client.lat,
          'p_lng': client.lng,
          'p_accuracy': client.locationAccuracy,
          'p_created_at': client.createdAt.toUtc().toIso8601String(),
        },
      );
      if (result is List && result.isNotEmpty) {
        return Client.fromSupabaseMap(Map<String, dynamic>.from(result.first as Map));
      }
      if (result is Map) {
        return Client.fromSupabaseMap(Map<String, dynamic>.from(result));
      }
      return client.copyWith(isSynced: true);
    } on PostgrestException catch (error) {
      // Fallback to direct upsert if register_queue_client RPC or extended columns are not deployed yet.
      if (error.code == '42883' ||
          error.code == '42703' ||
          (error.code?.startsWith('PGRST2') ?? false)) {
        await upsert(client);
        return client.copyWith(isSynced: true);
      }
      rethrow;
    }
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('clients').delete().eq('id', id);
  }
}
