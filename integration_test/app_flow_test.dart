import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wishiz/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('searches a list and opens its detail screen', (tester) async {
    await app.main();
    await tester.pumpAndSettle();

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
