import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'queue_provider.dart';
import 'screens/waiting_room_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // 1. Initialize Flutter bindings
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Load environment variables
  await dotenv.load(fileName: '.env');

  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    developer.log(
      'Warning: SUPABASE_URL or SUPABASE_ANON_KEY is missing from .env file',
      name: 'Bootstrap',
    );
  }

  // 3. Initialize Supabase
  await Supabase.initialize(
    url: supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: supabaseAnonKey,
  );

  // 4. Anonymous sign-in if no active session
  final currentSession = Supabase.instance.client.auth.currentSession;
  if (currentSession == null) {
    try {
      await Supabase.instance.client.auth.signInAnonymously();
      developer.log('Signed in anonymously to Supabase', name: 'Auth');
    } catch (e, stackTrace) {
      developer.log(
        'Anonymous sign-in skipped or failed: $e',
        name: 'Auth',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  // 5. Run App
  runApp(
    ChangeNotifierProvider<QueueProvider>(
      create: (_) => QueueProvider(),
      child: const WaitingRoomApp(),
    ),
  );
}

class WaitingRoomApp extends StatelessWidget {
  const WaitingRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waiting Room',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const WaitingRoomScreen(),
    );
  }
}
