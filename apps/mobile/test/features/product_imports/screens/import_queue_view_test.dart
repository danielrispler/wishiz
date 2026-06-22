import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/product_imports/data/in_memory_product_import_repository.dart';
import 'package:wishiz/features/product_imports/screens/import_queue/components/import_job_tile.dart';
import 'package:wishiz/features/product_imports/screens/import_queue/import_queue_view.dart';

void main() {
  Future<InMemoryProductImportRepository> seed(int count) async {
    final repo = InMemoryProductImportRepository();
    for (var i = 0; i < count; i++) {
      await repo.enqueue(
        sharedText: 'https://shop$i.example.com/p/$i',
        clientRequestId: 'req-$i',
        targetCurrencyCode: 'USD',
      );
    }
    return repo;
  }

  Future<void> pumpView(
    WidgetTester tester,
    InMemoryProductImportRepository repo,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ImportQueueView(
              repository: repo,
              isQueueing: false,
              onOpenWishlist: (_) {},
              onAssign: (_) {},
              onReview: (_) {},
              onRetry: (_) {},
              onAcknowledge: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('collapses to 2 tiles and expands via the more button', (
    tester,
  ) async {
    final repo = await seed(5);
    await pumpView(tester, repo);
    await tester.pumpAndSettle();

    // Collapsed: only 2 tiles + a "Show 3 more" toggle.
    expect(find.byType(ImportJobTile), findsNWidgets(2));
    expect(find.text('Show 3 more'), findsOneWidget);
    expect(find.text('Show less'), findsNothing);

    await tester.tap(find.text('Show 3 more'));
    await tester.pumpAndSettle();

    // Expanded: all 5 tiles + a "Show less" toggle.
    expect(find.byType(ImportJobTile), findsNWidgets(5));
    expect(find.text('Show less'), findsOneWidget);
    expect(find.text('Show 3 more'), findsNothing);

    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();

    expect(find.byType(ImportJobTile), findsNWidgets(2));
    expect(find.text('Show 3 more'), findsOneWidget);
  });

  testWidgets('shows no toggle when there are 2 or fewer jobs', (tester) async {
    final repo = await seed(2);
    await pumpView(tester, repo);
    await tester.pumpAndSettle();

    expect(find.byType(ImportJobTile), findsNWidgets(2));
    expect(find.textContaining('Show'), findsNothing);
  });
}
