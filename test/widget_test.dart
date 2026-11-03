import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/widgets/empty_state.dart';

void main() {
  testWidgets('EmptyStateWidget renders message and helper text',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyStateWidget(),
        ),
      ),
    );

    expect(find.text('No one in queue yet...'), findsOneWidget);
    expect(
      find.text(
        'Add client names above to start managing your queue in real time.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.people_outline_rounded), findsOneWidget);
  });
}
