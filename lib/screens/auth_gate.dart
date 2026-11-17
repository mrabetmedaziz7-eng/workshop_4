import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/loading_widget.dart';
import 'auth_screen.dart';
import 'client_waiting_room_screen.dart';
import 'waiting_room_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isLoading) {
      return const Scaffold(
        body: Center(
          child: LoadingWidget(message: 'Vérification de session...'),
        ),
      );
    }

    if (!auth.isAuthenticated) {
      return const AuthScreen();
    }

    if (auth.isAdmin) {
      return const WaitingRoomScreen();
    }

    // Default to client read-only screen
    return const ClientWaitingRoomScreen();
  }
}
