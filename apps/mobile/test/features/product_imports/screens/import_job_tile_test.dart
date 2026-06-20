import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';
import 'package:wishiz/features/product_imports/screens/import_queue/components/import_job_tile.dart';

void main() {
  Future<void> pumpTile(WidgetTester tester, ProductImportJob job) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportJobTile(
            job: job,
            onOpenWishlist: (_) {},
            onAssign: (_) {},
            onReview: (_) {},
            onRetry: (_) {},
            onAcknowledge: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('active job renders a progress bar reflecting progressPercent', (
    tester,
  ) async {
    await pumpTile(
      tester,
      _job(status: 'processing', stage: 'extracting', percent: 70),
    );
    // Advance past the bar's tween without pumpAndSettle (the leading spinner
    // animates forever, so pumpAndSettle would never return).
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Extracting details…'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.7, 0.001));
  });

  testWidgets('freshly claimed job shows an indeterminate bar', (tester) async {
    await pumpTile(
      tester,
      _job(status: 'processing', stage: 'validating', percent: 0),
    );
    await tester.pump();

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, isNull);
  });

  testWidgets('settled job shows no progress bar', (tester) async {
    await pumpTile(tester, _job(status: 'completed', stage: null, percent: 100));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('unsupported-store job shows a clear not-supported message '
      'and offers no Retry', (tester) async {
    await pumpTile(
      tester,
      _job(
        status: 'failed',
        stage: null,
        percent: 0,
        errorCode: 'unsupported_site',
        retryable: false,
        lastError: 'this store blocks automatic import',
      ),
    );
    await tester.pump();

    expect(
      find.textContaining("doesn't support automatic import"),
      findsOneWidget,
    );
    expect(find.byTooltip('Retry'), findsNothing);
    expect(find.byIcon(Icons.block), findsOneWidget);
    // Still lets the user add it by hand.
    expect(find.byTooltip('Edit manually'), findsOneWidget);
  });

  testWidgets('ordinary failed job keeps the generic message and Retry', (
    tester,
  ) async {
    await pumpTile(
      tester,
      _job(
        status: 'failed',
        stage: null,
        percent: 0,
        retryable: true,
        lastError: 'network error',
      ),
    );
    await tester.pump();

    expect(find.textContaining("doesn't support automatic import"), findsNothing);
    expect(find.byTooltip('Retry'), findsOneWidget);
  });
}

ProductImportJob _job({
  required String status,
  required String? stage,
  required int percent,
  String? errorCode,
  bool retryable = false,
  String? lastError,
}) {
  final now = DateTime(2026, 1, 1);
  return ProductImportJob(
    id: 'job-1',
    clientRequestId: 'req-1',
    normalizedUrl: 'https://example.com/products/mug',
    domain: 'example.com',
    targetCurrencyCode: 'USD',
    status: status,
    attemptCount: 1,
    lastError: lastError,
    errorCode: errorCode,
    retryable: retryable,
    completeness: 0,
    progressStage: stage,
    progressPercent: percent,
    createdAt: now,
    updatedAt: now,
  );
}
