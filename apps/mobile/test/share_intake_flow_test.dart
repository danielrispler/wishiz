import 'dart:async';
import 'dart:collection';

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
import 'package:wishiz/main.dart';

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
      expect(productImportRepository.requestedSharedTexts, isEmpty);
      expect(find.text('Choose a wishlist'), findsOneWidget);

      await chooseFirstWishlist(tester);

      expect(productImportRepository.requestedSharedTexts, [
        'https://example.com/products/mug',
      ]);
      expect(find.text('Shared item imports'), findsOneWidget);
      expect(
        find.text('Processing shared item. It will be added soon.'),
        findsOneWidget,
      );
    });

    testWidgets('imports a newly pending link after the app resumes', (
      tester,
    ) async {
      final authRepository = FakeAuthRepository(currentUser: sampleUser);
      final sharedProductRepository = FakeSharedProductRepository();
      final productImportRepository = FakeProductImportRepository();
      final shareIntakeService = FakeShareIntakeService(
        pendingResponses: [null, 'https://example.com/products/chair'],
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

      expect(sharedProductRepository.requestedSharedTexts, isEmpty);
      expect(productImportRepository.requestedSharedTexts, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(productImportRepository.requestedSharedTexts, isEmpty);
      expect(find.text('Choose a wishlist'), findsOneWidget);

      await chooseFirstWishlist(tester);

      expect(productImportRepository.requestedSharedTexts, [
        'https://example.com/products/chair',
      ]);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(productImportRepository.requestedSharedTexts, [
        'https://example.com/products/chair',
      ]);
    });

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

      expect(sharedProductRepository.requestedSharedTexts, isEmpty);
      expect(productImportRepository.requestedSharedTexts, isEmpty);

      authRepository.setCurrentUser(sampleUser);
      await tester.pump();
      await tester.pump();

      expect(productImportRepository.requestedSharedTexts, isEmpty);
      expect(find.text('Choose a wishlist'), findsOneWidget);

      await chooseFirstWishlist(tester);

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
            status: 'completed',
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
        ),
      ]);
      await tester.pump();

      await tester.tap(find.byTooltip('Hide'));
      await tester.pumpAndSettle();

      expect(productImportRepository.acknowledgedIds, ['needs-review-import']);
      expect(find.text('Needs review before saving'), findsNothing);
    });

    testWidgets(
      'opens a shared wishlist link instead of importing it as a product',
      (tester) async {
        final authRepository = FakeAuthRepository(currentUser: sampleUser);
        final sharedProductRepository = FakeSharedProductRepository();
        final shareIntakeService = FakeShareIntakeService(
          pendingResponses: [
            'https://wishiz.app/lists/wishlist-1\n\n'
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
          'https://wishiz.app/lists/wishlist-missing-token\n\n'
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

class FakeShareIntakeService extends ShareIntakeService {
  FakeShareIntakeService({List<String?> pendingResponses = const []})
    : _pendingResponses = Queue<String?>.from(pendingResponses);

  final Queue<String?> _pendingResponses;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  @override
  Future<String?> consumePendingSharedText() async {
    if (_pendingResponses.isEmpty) {
      return null;
    }
    return _pendingResponses.removeFirst();
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
    required String wishlistId,
    required String sharedText,
    required String clientRequestId,
    required String targetCurrencyCode,
  }) async {
    requestedSharedTexts.add(sharedText);
    final job = buildProductImportJob(
      id: clientRequestId,
      wishlistId: wishlistId,
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
      wishlistId: job.wishlistId,
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
}

ProductImportJob buildProductImportJob({
  required String id,
  String wishlistId = 'wishlist-1',
  String? clientRequestId,
  String normalizedUrl = 'https://example.com/products/mug',
  String domain = 'example.com',
  String targetCurrencyCode = 'USD',
  String status = 'completed',
  bool retryable = false,
  String? title,
  String? priceLabel,
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
  Future<void> logOut() async {
    setCurrentUser(null);
  }

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required DateTime birthday,
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
    required DateTime birthday,
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
