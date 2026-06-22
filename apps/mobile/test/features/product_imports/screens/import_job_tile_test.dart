import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';
import 'package:wishiz/features/product_imports/screens/import_queue/components/import_job_tile.dart';
import 'package:wishiz/shared/widgets/gradient_progress_bar.dart';
import 'package:wishiz/shared/widgets/shimmer_box.dart';

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

  GradientProgressBar progressBar(WidgetTester tester) =>
      tester.widget<GradientProgressBar>(find.byType(GradientProgressBar));

  testWidgets('active job renders a gradient progress bar reflecting '
      'progressPercent', (tester) async {
    await pumpTile(
      tester,
      _job(status: 'processing', stage: 'extracting', percent: 70),
    );
    // Advance past the bar's tween without pumpAndSettle (the skeleton sweep
    // animates forever, so pumpAndSettle would never return).
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Extracting details…'), findsOneWidget);
    expect(progressBar(tester).value, closeTo(0.7, 0.001));
  });

  testWidgets('active job shows a shimmer skeleton and no real title', (
    tester,
  ) async {
    await pumpTile(
      tester,
      _job(status: 'processing', stage: 'extracting', percent: 40),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Thumbnail + ghost title + ghost price lines are all shimmer boxes.
    expect(find.byType(ShimmerBox), findsWidgets);
    // While processing there is no real product data to show yet.
    expect(find.text('example.com'), findsNothing);
  });

  testWidgets('freshly claimed job shows an indeterminate bar', (tester) async {
    await pumpTile(
      tester,
      _job(status: 'processing', stage: 'validating', percent: 0),
    );
    await tester.pump();

    expect(progressBar(tester).value, isNull);
  });

  testWidgets('settled job shows no progress bar', (tester) async {
    await pumpTile(tester, _job(status: 'completed', stage: null, percent: 100));
    await tester.pump();

    expect(find.byType(GradientProgressBar), findsNothing);
  });

  testWidgets('completed-unassigned job morphs to real content with a Ready '
      'pill', (tester) async {
    await pumpTile(
      tester,
      _job(
        status: 'completed',
        stage: null,
        percent: 100,
        title: 'Nike Air Max 90',
        priceLabel: r'$129.00',
        imageUrl: 'https://example.com/shoe.jpg',
      ),
    );
    await tester.pump();

    expect(find.text('Nike Air Max 90'), findsOneWidget);
    expect(find.text(r'$129.00'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.byType(ShimmerBox), findsNothing);
    expect(find.byTooltip('Assign to list'), findsOneWidget);
  });

  testWidgets('needs_review job shows the amber Needs review pill', (
    tester,
  ) async {
    await pumpTile(
      tester,
      _job(
        status: 'needs_review',
        stage: null,
        percent: 0,
        title: 'Mystery Mug',
        priceConfidence: 'low',
      ),
    );
    await tester.pump();

    expect(find.text('Needs review'), findsOneWidget);
    expect(find.byTooltip('Review'), findsOneWidget);
  });

  testWidgets('failed job shows the Couldn\'t import pill', (tester) async {
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

    expect(find.text("Couldn't import"), findsOneWidget);
    expect(find.byTooltip('Retry'), findsOneWidget);
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

    expect(
      find.textContaining("doesn't support automatic import"),
      findsNothing,
    );
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
  String? title,
  String? priceLabel,
  String? priceConfidence,
  String? imageUrl,
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
    title: title,
    priceLabel: priceLabel,
    priceConfidence: priceConfidence,
    imageUrl: imageUrl,
    completeness: 0,
    progressStage: stage,
    progressPercent: percent,
    createdAt: now,
    updatedAt: now,
  );
}
