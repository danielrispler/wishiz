import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/core/services/share_intake_service.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/entities/auth_result.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';
import 'package:wishiz/features/product_imports/domain/product_import_repository.dart';
import 'package:wishiz/features/wishlists/data/repositories/in_memory_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/app/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wishiz share intake flow', () {
    testWidgets('imports a pending shared link on cold start', (tester) async {
      final authRepository = FakeAuthRepository(currentUser: sampleUser);
      final sharedProductRepository = FakeSharedProductRepository();
      final productImportRepository = FakeProductImportRepository();
      final shareIntakeService = FakeShareIntakeService(
        pendingResponses: ['https://example.com/products/mug'],
      );

      await tester.pumpWidget(
        buildTestApp(
          authRepository: authRepository,
          sharedProductRepository: sharedProductRepository,
          productImportRepository: productImportRepository,
          shareIntakeService: shareIntakeService,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(sharedProductRepository.requestedSharedTexts, isEmpty);
      // Import is auto-queued without a wishlist-selection dialog.
      expect(productImportRepository.requestedSharedTexts, [
        'https://example.com/products/mug',
      ]);
      expect(
        find.text('Processing shared item. Check the queue to assign it.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'imports two product URLs that are both pending in the native queue',
      (tester) async {
        final authRepository = FakeAuthRepository(currentUser: sampleUser);
        final productImportRepository = FakeProductImportRepository();
        final shareIntakeService = FakeShareIntakeService(
          pendingResponses: [
            'https://example.com/products/mug',
            'https://example.com/products/chair',
          ],
        );

        await tester.pumpWidget(
          buildTestApp(
            authRepository: authRepository,
            sharedProductRepository: FakeSharedProductRepository(),
            productImportRepository: productImportRepository,
            shareIntakeService: shareIntakeService,
          ),
        );
        await tester.pumpAndSettle();

        // Both URLs enqueued: first consumed at startup,
        // second consumed after first is handled.
        expect(productImportRepository.requestedSharedTexts, [
          'https://example.com/products/mug',
          'https://example.com/products/chair',
        ]);
      },
    );

    testWidgets(
      'unmounting the app mid-enqueue does not setState after dispose',
      (tester) async {
        final authRepository = FakeAuthRepository(currentUser: sampleUser);
        final enqueueGate = Completer<void>();
        final productImportRepository = GatedProductImportRepository(
          gate: enqueueGate,
        );
        final shareIntakeService = FakeShareIntakeService(
          pendingResponses: ['https://example.com/products/mug'],
        );

        await tester.pumpWidget(
          buildTestApp(
            authRepository: authRepository,
            sharedProductRepository: FakeSharedProductRepository(),
            productImportRepository: productImportRepository,
            shareIntakeService: shareIntakeService,
          ),
        );
        // Let the post-frame callback start the (now-blocked) enqueue.
        await tester.pump();
        await tester.pump();

        // Tear the whole app down while the import is still in flight.
        await tester.pumpWidget(const SizedBox());

        // Completing now runs HomeScreen's finally → onInitialSharedTextHandled
        // on the already-disposed _RootScreenState. The parent's setState must be
        // guarded by its own mounted, so this must NOT throw.
        enqueueGate.complete();
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('imports a newly pending link after the app resumes', (
      tester,
    ) async {
      final authRepository = FakeAuthRepository(currentUser: sampleUser);
      final sharedProductRepository = FakeSharedProductRepository();
      final productImportRepository = FakeProductImportRepository();
      final shareIntakeService = FakeShareIntakeService();

      await tester.pumpWidget(
        buildTestApp(
          authRepository: authRepository,
          sharedProductRepository: sharedProductRepository,
          productImportRepository: productImportRepository,
          shareIntakeService: shareIntakeService,
        ),
      );
      await tester.pumpAndSettle();

      expect(sharedProductRepository.requestedSharedTexts, isEmpty);
      expect(productImportRepository.requestedSharedTexts, isEmpty);

      // A share arrives while the app is backgrounded, then it resumes.
      shareIntakeService.enqueuePending(['https://example.com/products/chair']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Import auto-queued on resume, no dialog.
      expect(productImportRepository.requestedSharedTexts, [
        'https://example.com/products/chair',
      ]);

      // Extra resume with nothing pending — no duplicate import.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(productImportRepository.requestedSharedTexts, [
        'https://example.com/products/chair',
      ]);
    });

    testWidgets(
      'drains the whole native queue exactly once despite a resume during '
      'cold-start mount',
      (tester) async {
        final authRepository = FakeAuthRepository(currentUser: sampleUser);
        final productImportRepository = FakeProductImportRepository();
        final shareIntakeService = FakeShareIntakeService(
          pendingResponses: [
            'https://example.com/products/mug',
            'https://example.com/products/chair',
          ],
        );
        final gate = Completer<void>();
        final repository = InMemoryWishlistRepository(
          ownerUserId: sampleUser.id,
        );

        await tester.pumpWidget(
          buildTestApp(
            authRepository: authRepository,
            sharedProductRepository: FakeSharedProductRepository(),
            productImportRepository: productImportRepository,
            shareIntakeService: shareIntakeService,
            wishlistRepositoryLoader: (_) async {
              await gate.future;
              return repository;
            },
          ),
        );

        // HomeScreen has not mounted yet (loader still pending). Fire a resume
        // so the initState consume and the resumed consume race.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        gate.complete();
        await tester.pumpAndSettle();

        // Both items land, each exactly once — the second (racing) drain saw
        // an already-emptied native queue.
        expect(productImportRepository.requestedSharedTexts, [
          'https://example.com/products/mug',
          'https://example.com/products/chair',
        ]);
        expect(shareIntakeService.consumeCallCount, greaterThanOrEqualTo(2));
      },
    );

    testWidgets('imports a duplicate URL in a single batch only once', (
      tester,
    ) async {
      final authRepository = FakeAuthRepository(currentUser: sampleUser);
      final productImportRepository = FakeProductImportRepository();
      final shareIntakeService = FakeShareIntakeService(
        pendingResponses: [
          'https://example.com/products/mug',
          'https://example.com/products/mug',
        ],
      );

      await tester.pumpWidget(
        buildTestApp(
          authRepository: authRepository,
          sharedProductRepository: FakeSharedProductRepository(),
          productImportRepository: productImportRepository,
          shareIntakeService: shareIntakeService,
        ),
      );
      // Must return — duplicate heads must not deadlock the re-trigger.
      await tester.pumpAndSettle();

      expect(productImportRepository.requestedSharedTexts, [
        'https://example.com/products/mug',
      ]);
    });

    testWidgets('re-imports the same URL shared again after the buffer drains', (
      tester,
    ) async {
      final authRepository = FakeAuthRepository(currentUser: sampleUser);
      final productImportRepository = FakeProductImportRepository();
      final shareIntakeService = FakeShareIntakeService(
        pendingResponses: ['https://example.com/products/mug'],
      );

      await tester.pumpWidget(
        buildTestApp(
          authRepository: authRepository,
          sharedProductRepository: FakeSharedProductRepository(),
          productImportRepository: productImportRepository,
          shareIntakeService: shareIntakeService,
        ),
      );
      await tester.pumpAndSettle();

      expect(productImportRepository.requestedSharedTexts, [
        'https://example.com/products/mug',
      ]);

      // Same URL shared again as a genuinely new event after the buffer empties
      // — de-dupe is batch-scoped, not a permanent global set.
      shareIntakeService.enqueuePending(['https://example.com/products/mug']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(productImportRepository.requestedSharedTexts, [
        'https://example.com/products/mug',
        'https://example.com/products/mug',
      ]);
    });

    testWidgets(
      'imports every product in a mixed batch, then opens the first queued '
      'wishlist link',
      (tester) async {
        final authRepository = FakeAuthRepository(currentUser: sampleUser);
        final sharedProductRepository = FakeSharedProductRepository();
        final productImportRepository = FakeProductImportRepository();
        final shareIntakeService = FakeShareIntakeService(
          pendingResponses: [
            'https://wishiz-api-pdst26qeja-ey.a.run.app/lists/wishlist-1',
            'https://example.com/products/mug',
            'https://example.com/products/chair',
            'https://wishiz-api-pdst26qeja-ey.a.run.app/lists/wishlist-2',
          ],
        );

        await tester.pumpWidget(
          buildTestApp(
            authRepository: authRepository,
            sharedProductRepository: sharedProductRepository,
            productImportRepository: productImportRepository,
            shareIntakeService: shareIntakeService,
          ),
        );
        await tester.pumpAndSettle();

        // Both products import in FIFO order; the list link is not imported.
        expect(productImportRepository.requestedSharedTexts, [
          'https://example.com/products/mug',
          'https://example.com/products/chair',
        ]);
        expect(sharedProductRepository.requestedSharedTexts, isEmpty);

        // First-wins: wishlist-2 is ignored, wishlist-1 detail opens once the
        // product buffer drains.
        expect(find.text('List Details'), findsOneWidget);
        expect(find.text('Birthdays'), findsOneWidget);
      },
    );

    testWidgets('preserves a pending shared link until the user logs in', (
      tester,
    ) async {
      final authRepository = FakeAuthRepository();
      final sharedProductRepository = FakeSharedProductRepository();
      final productImportRepository = FakeProductImportRepository();
      final shareIntakeService = FakeShareIntakeService(
        pendingResponses: ['https://example.com/products/lamp'],
      );

      await tester.pumpWidget(
        buildTestApp(
          authRepository: authRepository,
          sharedProductRepository: sharedProductRepository,
          productImportRepository: productImportRepository,
          shareIntakeService: shareIntakeService,
        ),
      );
      await tester.pumpAndSettle();

      // Not yet imported — no user logged in.
      expect(sharedProductRepository.requestedSharedTexts, isEmpty);
      expect(productImportRepository.requestedSharedTexts, isEmpty);

      authRepository.setCurrentUser(sampleUser);
      await tester.pump();
      await tester.pump();

      // Import auto-queued after login, no dialog.
      expect(productImportRepository.requestedSharedTexts, [
        'https://example.com/products/lamp',
      ]);
    });

    testWidgets('retry starts product import sync polling', (tester) async {
      final authRepository = FakeAuthRepository(currentUser: sampleUser);
      final sharedProductRepository = FakeSharedProductRepository();
      final productImportRepository = FakeProductImportRepository()
        ..setJobs([
          buildProductImportJob(
            id: 'failed-import',
            status: 'failed',
            retryable: true,
          ),
        ]);

      await tester.pumpWidget(
        buildTestApp(
          authRepository: authRepository,
          sharedProductRepository: sharedProductRepository,
          productImportRepository: productImportRepository,
          shareIntakeService: FakeShareIntakeService(),
        ),
      );
      await tester.pumpAndSettle();

      expect(productImportRepository.refreshCallCount, 1);

      await tester.tap(find.byTooltip('Retry'));
      await tester.pump();
      await tester.pump();

      expect(productImportRepository.retriedIds, ['failed-import']);
      expect(productImportRepository.refreshCallCount, 2);
    });

    testWidgets('acknowledge removes the visible import job', (tester) async {
      final authRepository = FakeAuthRepository(currentUser: sampleUser);
      final sharedProductRepository = FakeSharedProductRepository();
      final productImportRepository = FakeProductImportRepository()
        ..setJobs([
          buildProductImportJob(
            id: 'completed-import',
            title: 'Imported mug',
            status: 'needs_review',
            retryable: false,
          ),
        ]);

      await tester.pumpWidget(
        buildTestApp(
          authRepository: authRepository,
          sharedProductRepository: sharedProductRepository,
          productImportRepository: productImportRepository,
          shareIntakeService: FakeShareIntakeService(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Imported mug'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide'));
      await tester.pumpAndSettle();

      expect(productImportRepository.acknowledgedIds, ['completed-import']);
      expect(find.text('Imported mug'), findsNothing);
    });

    testWidgets('needs review import can be retried or hidden', (tester) async {
      final authRepository = FakeAuthRepository(currentUser: sampleUser);
      final sharedProductRepository = FakeSharedProductRepository();
      final productImportRepository = FakeProductImportRepository()
        ..setJobs([
          buildProductImportJob(
            id: 'needs-review-import',
            title: 'example.com',
            status: 'needs_review',
            retryable: true,
            priceConfidence: 'high',
          ),
        ]);

      await tester.pumpWidget(
        buildTestApp(
          authRepository: authRepository,
          sharedProductRepository: sharedProductRepository,
          productImportRepository: productImportRepository,
          shareIntakeService: FakeShareIntakeService(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Needs review before saving'), findsOneWidget);
      expect(find.byTooltip('Retry'), findsOneWidget);
      expect(find.byTooltip('Review'), findsOneWidget);
      expect(find.byTooltip('Hide'), findsOneWidget);

      await tester.tap(find.byTooltip('Retry'));
      await tester.pump();
      await tester.pump();

      expect(productImportRepository.retriedIds, ['needs-review-import']);

      productImportRepository.setJobs([
        buildProductImportJob(
          id: 'needs-review-import',
          title: 'example.com',
          status: 'needs_review',
          retryable: true,
          priceConfidence: 'high',
        ),
      ]);
      await tester.pump();

      await tester.tap(find.byTooltip('Hide'));
      await tester.pumpAndSettle();

      expect(productImportRepository.acknowledgedIds, ['needs-review-import']);
      expect(find.text('Needs review before saving'), findsNothing);
    });

    testWidgets('terminal failed import explains it will not retry', (
      tester,
    ) async {
      final authRepository = FakeAuthRepository(currentUser: sampleUser);
      final sharedProductRepository = FakeSharedProductRepository();
      final productImportRepository = FakeProductImportRepository()
        ..setJobs([
          buildProductImportJob(
            id: 'failed-import',
            title: 'example.com',
            status: 'failed',
            retryable: false,
          ),
        ]);

      await tester.pumpWidget(
        buildTestApp(
          authRepository: authRepository,
          sharedProductRepository: sharedProductRepository,
          productImportRepository: productImportRepository,
          shareIntakeService: FakeShareIntakeService(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Import failed. Add it manually.'), findsOneWidget);
      expect(find.byTooltip('Retry'), findsNothing);
      expect(find.byTooltip('Edit manually'), findsOneWidget);
      expect(find.byTooltip('Hide'), findsOneWidget);
    });

    testWidgets(
      'opens a shared wishlist link instead of importing it as a product',
      (tester) async {
        final authRepository = FakeAuthRepository(currentUser: sampleUser);
        final sharedProductRepository = FakeSharedProductRepository();
        final shareIntakeService = FakeShareIntakeService(
          pendingResponses: [
            'https://wishiz-api-pdst26qeja-ey.a.run.app/lists/wishlist-1\n\n'
                'Open this Wishiz list in the app.\n'
                'Join my Wishiz list "Birthdays" for 2026.',
          ],
        );

        await tester.pumpWidget(
          buildTestApp(
            authRepository: authRepository,
            sharedProductRepository: sharedProductRepository,
            shareIntakeService: shareIntakeService,
          ),
        );
        await tester.pumpAndSettle();

        expect(sharedProductRepository.requestedSharedTexts, isEmpty);
        expect(find.text('List Details'), findsOneWidget);
        expect(find.text('Birthdays'), findsOneWidget);
      },
    );

    testWidgets('does not join a shared wishlist link without a token', (
      tester,
    ) async {
      final authRepository = FakeAuthRepository(currentUser: sampleUser);
      final sharedProductRepository = FakeSharedProductRepository();
      final repository = CountingWishlistRepository(ownerUserId: sampleUser.id);
      final shareIntakeService = FakeShareIntakeService(
        pendingResponses: [
          'https://wishiz-api-pdst26qeja-ey.a.run.app/lists/wishlist-missing-token\n\n'
              'Open this Wishiz list in the app.',
        ],
      );

      await tester.pumpWidget(
        buildTestApp(
          authRepository: authRepository,
          sharedProductRepository: sharedProductRepository,
          shareIntakeService: shareIntakeService,
          wishlistRepositoryLoader: (_) async => repository,
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.joinCallCount, 0);
      expect(
        find.text('This invite link is missing an invite token.'),
        findsOneWidget,
      );
    });

    testWidgets('switches to the signed in user repository', (tester) async {
      final authRepository = FakeAuthRepository(currentUser: sampleUser);
      final sharedProductRepository = FakeSharedProductRepository();
      final shareIntakeService = FakeShareIntakeService();
      final secondUser = sampleUser.copyWith(
        id: 'user-2',
        email: 'dana@example.com',
        fullName: 'Dana Rios',
      );

      final repositoriesByUser = <String, WishlistRepository>{
        sampleUser.id: InMemoryWishlistRepository(
          ownerUserId: sampleUser.id,
          initialWishlists: [
            Wishlist(
              id: 'wishlist-1',
              ownerUserId: sampleUser.id,
              ownerFullName: sampleUser.fullName,
              title: 'Maya Birthday Ideas',
              description: 'Family gifts',
              year: 2026,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
        ),
        secondUser.id: InMemoryWishlistRepository(
          ownerUserId: secondUser.id,
          initialWishlists: [
            Wishlist(
              id: 'wishlist-2',
              ownerUserId: secondUser.id,
              ownerFullName: secondUser.fullName,
              title: 'Dana Travel List',
              description: 'Carry-on upgrades',
              year: 2026,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
        ),
      };

      await tester.pumpWidget(
        buildTestApp(
          authRepository: authRepository,
          sharedProductRepository: sharedProductRepository,
          shareIntakeService: shareIntakeService,
          wishlistRepositoryLoader: (user) async =>
              repositoriesByUser[user.id]!,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Maya Birthday Ideas'), findsOneWidget);
      expect(find.text('Dana Travel List'), findsNothing);

      authRepository.setCurrentUser(secondUser);
      await tester.pumpAndSettle();

      expect(find.text('Dana Travel List'), findsOneWidget);
      expect(find.text('Maya Birthday Ideas'), findsNothing);
    });
  });
}

Future<void> chooseFirstWishlist(WidgetTester tester) async {
  await tester.tap(find.byType(SimpleDialogOption).first);
  await tester.pumpAndSettle();
}

Widget buildTestApp({
  required FakeAuthRepository authRepository,
  required FakeSharedProductRepository sharedProductRepository,
  required FakeShareIntakeService shareIntakeService,
  FakeProductImportRepository? productImportRepository,
  Future<WishlistRepository> Function(AppUser user)? wishlistRepositoryLoader,
}) {
  final repository = InMemoryWishlistRepository(
    ownerUserId: sampleUser.id,
    initialWishlists: [
      Wishlist(
        id: 'wishlist-1',
        ownerUserId: sampleUser.id,
        ownerFullName: sampleUser.fullName,
        title: 'Birthdays',
        description: 'Family gifts',
        year: 2026,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ],
  );

  return WishizApp(
    wishlistRepositoryLoader:
        wishlistRepositoryLoader ?? (_) async => repository,
    productImportRepositoryFactory: (_) =>
        productImportRepository ?? FakeProductImportRepository(),
    authRepository: authRepository,
    sharedProductRepository: sharedProductRepository,
    shareIntakeService: shareIntakeService,
  );
}

class CountingWishlistRepository extends InMemoryWishlistRepository {
  CountingWishlistRepository({required super.ownerUserId});

  int joinCallCount = 0;

  @override
  Future<Wishlist?> joinWishlist({
    required String id,
    required String token,
  }) async {
    joinCallCount += 1;
    return super.joinWishlist(id: id, token: token);
  }
}

/// A product-import repository whose enqueue blocks until [gate] completes, so a
/// test can unmount the app while an import is in flight.
class GatedProductImportRepository extends FakeProductImportRepository {
  GatedProductImportRepository({required this.gate});

  final Completer<void> gate;

  @override
  Future<ProductImportJob> enqueue({
    String? wishlistId,
    required String sharedText,
    required String clientRequestId,
    required String targetCurrencyCode,
  }) async {
    await gate.future;
    return super.enqueue(
      wishlistId: wishlistId,
      sharedText: sharedText,
      clientRequestId: clientRequestId,
      targetCurrencyCode: targetCurrencyCode,
    );
  }
}

class FakeShareIntakeService extends ShareIntakeService {
  FakeShareIntakeService({List<String> pendingResponses = const []})
    : _pending = List<String>.from(pendingResponses);

  final List<String> _pending;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  int consumeCallCount = 0;

  /// Re-arm the native queue with a fresh batch (a new share event arriving
  /// after a previous batch was already drained).
  void enqueuePending(List<String> texts) => _pending.addAll(texts);

  @override
  Future<List<String>> consumePendingSharedTexts() async {
    consumeCallCount += 1;
    final drained = List<String>.from(_pending);
    _pending.clear();
    return drained;
  }

  @override
  Stream<String> watchSharedText() => _controller.stream;
}

class FakeSharedProductRepository implements SharedProductRepository {
  final List<String> requestedSharedTexts = [];

  @override
  Future<SharedProductDraft?> createDraftFromSharedText(
    String sharedText, {
    String targetCurrencyCode = 'USD',
  }) async {
    requestedSharedTexts.add(sharedText);
    return SharedProductDraft(
      productUrl: sharedText,
      title: 'Imported mug',
      notes: 'From share',
      priceLabel: 'USD 24.00',
      imageUrl: 'https://example.com/images/mug.png',
      sharedText: sharedText,
    );
  }
}

class FakeProductImportRepository implements ProductImportRepository {
  final List<String> requestedSharedTexts = [];
  final List<String> retriedIds = [];
  final List<String> acknowledgedIds = [];
  final ValueNotifier<List<ProductImportJob>> _jobs =
      ValueNotifier<List<ProductImportJob>>(const []);
  int refreshCallCount = 0;

  void setJobs(List<ProductImportJob> jobs) {
    _jobs.value = List<ProductImportJob>.unmodifiable(jobs);
  }

  @override
  ValueListenable<List<ProductImportJob>> watchJobs() => _jobs;

  @override
  List<ProductImportJob> getJobs() => _jobs.value;

  @override
  Future<ProductImportJob> enqueue({
    String? wishlistId,
    required String sharedText,
    required String clientRequestId,
    required String targetCurrencyCode,
  }) async {
    requestedSharedTexts.add(sharedText);
    final job = buildProductImportJob(
      id: clientRequestId,
      wishlistId: wishlistId ?? 'wishlist-1',
      clientRequestId: clientRequestId,
      normalizedUrl: sharedText,
      domain: Uri.tryParse(sharedText)?.host ?? '',
      targetCurrencyCode: targetCurrencyCode,
      status: 'completed',
      title: 'Imported mug',
      priceLabel: 'USD 24.00',
      imageUrl: 'https://example.com/images/mug.png',
    );
    _jobs.value = [job, ..._jobs.value];
    return job;
  }

  @override
  Future<void> refresh() async {
    refreshCallCount += 1;
  }

  @override
  Future<ProductImportJob> retry(String id) async {
    retriedIds.add(id);
    final job = _jobs.value.firstWhere((job) => job.id == id);
    final retried = buildProductImportJob(
      id: job.id,
      wishlistId: job.wishlistId ?? 'wishlist-1',
      clientRequestId: job.clientRequestId,
      normalizedUrl: job.normalizedUrl,
      domain: job.domain,
      targetCurrencyCode: job.targetCurrencyCode,
      status: 'pending',
      title: job.title,
      priceLabel: job.priceLabel,
      imageUrl: job.imageUrl,
    );
    _jobs.value = [retried, ..._jobs.value.where((job) => job.id != id)];
    return retried;
  }

  @override
  Future<ProductImportJob> acknowledge(String id) async {
    acknowledgedIds.add(id);
    final job = _jobs.value.firstWhere((job) => job.id == id);
    _jobs.value = _jobs.value.where((job) => job.id != id).toList();
    return job;
  }

  @override
  Future<ProductImportJob> assign(String id, String wishlistId) async {
    return _jobs.value.firstWhere((job) => job.id == id);
  }
}

ProductImportJob buildProductImportJob({
  required String id,
  String? wishlistId = 'wishlist-1',
  String? clientRequestId,
  String normalizedUrl = 'https://example.com/products/mug',
  String domain = 'example.com',
  String targetCurrencyCode = 'USD',
  String status = 'completed',
  bool retryable = false,
  String? title,
  String? priceLabel,
  String? priceConfidence,
  String? imageUrl,
}) {
  final now = DateTime.now();
  return ProductImportJob(
    id: id,
    wishlistId: wishlistId,
    clientRequestId: clientRequestId ?? id,
    normalizedUrl: normalizedUrl,
    domain: domain,
    targetCurrencyCode: targetCurrencyCode,
    status: status,
    attemptCount: 0,
    retryable: retryable,
    title: title,
    priceLabel: priceLabel,
    priceConfidence: priceConfidence,
    imageUrl: imageUrl,
    completeness: 3,
    createdAt: now,
    updatedAt: now,
  );
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AppUser? currentUser})
    : _currentUser = ValueNotifier<AppUser?>(currentUser);

  final ValueNotifier<AppUser?> _currentUser;

  void setCurrentUser(AppUser? user) {
    _currentUser.value = user;
  }

  @override
  AppUser? getCurrentUser() => _currentUser.value;

  @override
  Future<AuthResult> logIn({
    required String email,
    required String password,
  }) async {
    final user = sampleUser.copyWith(email: email);
    setCurrentUser(user);
    return AuthResult.success(user);
  }

  @override
  Future<AuthResult> savePreferences({
    required List<String> brandNames,
    String? gender,
  }) async => AuthResult.success(getCurrentUser()!);

  @override
  Future<void> deleteAccount({required String password}) async {}

  @override
  Future<void> logOut() async {
    setCurrentUser(null);
  }

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    DateTime? birthday,
    String? gender,
  }) async {
    final user = AppUser(
      id: 'user-1',
      email: email,
      fullName: fullName,
      birthday: birthday,
    );
    setCurrentUser(user);
    return AuthResult.success(user);
  }

  @override
  Future<AuthResult> updateCurrentUser({
    required String email,
    required String fullName,
    DateTime? birthday,
    String? gender,
    required String preferredCurrencyCode,
    required bool notificationsEnabled,
    required int reminderDays,
    String? currentPassword,
    String? newPassword,
  }) async {
    final currentUser = _currentUser.value ?? sampleUser;
    final updatedUser = currentUser.copyWith(
      email: email,
      fullName: fullName,
      birthday: birthday,
      preferredCurrencyCode: preferredCurrencyCode,
      notificationsEnabled: notificationsEnabled,
      reminderDays: reminderDays,
    );
    setCurrentUser(updatedUser);
    return AuthResult.success(updatedUser);
  }

  @override
  ValueListenable<AppUser?> watchCurrentUser() => _currentUser;
}

final sampleUser = AppUser(
  id: 'user-1',
  email: 'maya@example.com',
  fullName: 'Maya Levy',
  birthday: DateTime(1995, 6, 20),
);
