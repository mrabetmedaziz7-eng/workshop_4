import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('Live Supabase connection and clients query test', () async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {}

    final url = dotenv.env['SUPABASE_URL'] ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

    if (url.isEmpty || anonKey.isEmpty) {
      // Skip live test if environment variables are not populated (e.g. clean clone / CI)
      return;
    }

    final client = SupabaseClient(url, anonKey);

    // Verify reading from 'clients' table
    final data = await client
        .from('clients')
        .select()
        .order('created_at', ascending: true);

    expect(data, isA<List<dynamic>>());
  });
}
