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

    if (find.text('Log In').evaluate().isNotEmpty) {
      await tester.enterText(find.byType(TextFormField).at(0), 'daniel');
      await tester.enterText(find.byType(TextFormField).at(1), 'daniel');
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Wishiz'), findsOneWidget);

    final searchField = find.byKey(const ValueKey('Search your lists-0'));

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
