import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/client.dart';

abstract class ClientsRepository {
  Stream<List<Client>> watchClients();
  Future<void> insert(String name);
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
        .map((records) => records.map(Client.fromMap).toList());
  }

  @override
  Future<void> insert(String name) async {
    await _client.from('clients').insert({'name': name});
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('clients').delete().eq('id', id);
  }
}
