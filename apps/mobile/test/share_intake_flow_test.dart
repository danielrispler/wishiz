import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/core/services/share_intake_service.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/entities/auth_result.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
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
      final shareIntakeService = FakeShareIntakeService(
        pendingResponses: ['https://example.com/products/mug'],
      );

      await tester.pumpWidget(
        buildTestApp(
          authRepository: authRepository,
          sharedProductRepository: sharedProductRepository,
          shareIntakeService: shareIntakeService,
        ),
      );
      await tester.pumpAndSettle();

      expect(sharedProductRepository.requestedSharedTexts, [
        'https://example.com/products/mug',
      ]);
      expect(find.text('Preview Item'), findsOneWidget);
      expect(find.text('Imported details may have problems'), findsOneWidget);
      expect(find.text('Imported mug'), findsOneWidget);
    });

    testWidgets('imports a newly pending link after the app resumes', (
      tester,
    ) async {
      final authRepository = FakeAuthRepository(currentUser: sampleUser);
      final sharedProductRepository = FakeSharedProductRepository();
      final shareIntakeService = FakeShareIntakeService(
        pendingResponses: [null, 'https://example.com/products/chair'],
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

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(sharedProductRepository.requestedSharedTexts, [
        'https://example.com/products/chair',
      ]);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(sharedProductRepository.requestedSharedTexts, [
        'https://example.com/products/chair',
      ]);
    });

    testWidgets('preserves a pending shared link until the user logs in', (
      tester,
    ) async {
      final authRepository = FakeAuthRepository();
      final sharedProductRepository = FakeSharedProductRepository();
      final shareIntakeService = FakeShareIntakeService(
        pendingResponses: ['https://example.com/products/lamp'],
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

      authRepository.setCurrentUser(sampleUser);
      await tester.pumpAndSettle();

      expect(sharedProductRepository.requestedSharedTexts, [
        'https://example.com/products/lamp',
      ]);
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

Widget buildTestApp({
  required FakeAuthRepository authRepository,
  required FakeSharedProductRepository sharedProductRepository,
  required FakeShareIntakeService shareIntakeService,
  Future<WishlistRepository> Function(AppUser user)? wishlistRepositoryLoader,
}) {
  final repository = InMemoryWishlistRepository(
    ownerUserId: sampleUser.id,
    initialWishlists: [
      Wishlist(
        id: 'wishlist-1',
        ownerUserId: sampleUser.id,
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
