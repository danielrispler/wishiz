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

      expect(
        sharedProductRepository.requestedSharedTexts,
        ['https://example.com/products/mug'],
      );
      expect(find.text('Imported mug'), findsOneWidget);
    });

    testWidgets('imports a newly pending link after the app resumes',
        (tester) async {
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

      expect(
        sharedProductRepository.requestedSharedTexts,
        ['https://example.com/products/chair'],
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        sharedProductRepository.requestedSharedTexts,
        ['https://example.com/products/chair'],
      );
    });

    testWidgets('preserves a pending shared link until the user logs in',
        (tester) async {
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

      expect(
        sharedProductRepository.requestedSharedTexts,
        ['https://example.com/products/lamp'],
      );
    });
  });
}

Widget buildTestApp({
  required FakeAuthRepository authRepository,
  required FakeSharedProductRepository sharedProductRepository,
  required FakeShareIntakeService shareIntakeService,
}) {
  final repository = InMemoryWishlistRepository(
    initialWishlists: [
      Wishlist(
        id: 'wishlist-1',
        title: 'Birthdays',
        description: 'Family gifts',
        year: 2026,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ],
  );

  return WishizApp(
    wishlistRepository: repository,
    authRepository: authRepository,
    sharedProductRepository: sharedProductRepository,
    shareIntakeService: shareIntakeService,
  );
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
      String sharedText) async {
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
