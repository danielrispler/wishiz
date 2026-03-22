import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wishiz/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signs up, searches by name, and opens a list detail screen', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();

    if (find.text('Need an account? Sign up').evaluate().isNotEmpty) {
      await tester.tap(find.text('Need an account? Sign up'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Dana');
      await tester.enterText(find.byType(TextFormField).at(1), 'Rios');
      await tester.enterText(find.byType(TextFormField).at(2), '28');
      await tester.enterText(
        find.byType(TextFormField).at(3),
        'dana@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(4), 'password123');
      await tester.enterText(find.byType(TextFormField).at(5), 'password123');
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Wishiz'), findsOneWidget);

    final searchField = find.byWidgetPredicate((widget) {
      return widget is TextFormField &&
          widget.decoration?.hintText == 'Search your lists';
    });

    await tester.enterText(searchField, 'Tech');
    await tester.pumpAndSettle();

    expect(find.text('Tech Gear 2024'), findsOneWidget);
    expect(find.text('Home Decor'), findsNothing);

    await tester.tap(find.text('Tech Gear 2024'));
    await tester.pumpAndSettle();

    expect(find.text('List Details'), findsOneWidget);
    expect(find.text('Tech Gear 2024'), findsOneWidget);
  });
}
