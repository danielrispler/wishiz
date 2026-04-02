import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/entities/auth_result.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/wishlists/data/repositories/in_memory_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_detail_screen.dart';

void main() {
  group('WishlistDetailScreen past list', () {
    testWidgets('restores the whole list from the Restore All button', (
      tester,
    ) async {
      final repository = InMemoryWishlistRepository(
        ownerUserId: _sampleUser.id,
        initialWishlists: [
          _buildWishlist(
            items: [
              WishlistItem(
                id: 'item-1',
                title: 'Espresso cups',
                rank: 1,
                status: 'Purchased',
                purchasedAt: null,
                createdAt: DateTime(2026, 1, 1),
              ),
              WishlistItem(
                id: 'item-2',
                title: 'Serving tray',
                rank: 2,
                status: 'Purchased',
                purchasedAt: null,
                createdAt: DateTime(2026, 1, 1),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(_buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Restore All'), findsOneWidget);

      await tester.tap(find.text('Restore All'));
      await tester.pump();
      await tester.pumpAndSettle();

      final updatedWishlist = repository.findById('wishlist-1');
      expect(updatedWishlist?.purchasedItems, isEmpty);
      expect(updatedWishlist?.activeItems.map((item) => item.id), [
        'item-1',
        'item-2',
      ]);
      expect(find.byKey(const ValueKey('dismiss-item-1')), findsNothing);
      expect(find.byKey(const ValueKey('dismiss-item-2')), findsNothing);
      expect(
        find.text('All items moved back to active items.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'No purchased items yet. Swipe right on an active item to move it into Past Lists.',
        ),
        findsOneWidget,
      );
    });
  });
}

Widget _buildSubject({required InMemoryWishlistRepository repository}) {
  return MaterialApp(
    home: WishlistDetailScreen(
      repository: repository,
      authRepository: _FakeAuthRepository(currentUser: _sampleUser),
      sharedProductRepository: _FakeSharedProductRepository(),
      wishlistId: 'wishlist-1',
      showPurchasedOnly: true,
    ),
  );
}

Wishlist _buildWishlist({List<WishlistItem> items = const []}) {
  return Wishlist(
    id: 'wishlist-1',
    ownerUserId: _sampleUser.id,
    title: 'Hosting',
    description: 'Table setting ideas.',
    year: 2026,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    items: items,
  );
}

class _FakeSharedProductRepository implements SharedProductRepository {
  @override
  Future<SharedProductDraft?> createDraftFromSharedText(
    String sharedText,
  ) async {
    return null;
  }
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({AppUser? currentUser})
    : _currentUser = ValueNotifier<AppUser?>(currentUser);

  final ValueNotifier<AppUser?> _currentUser;

  @override
  AppUser? getCurrentUser() => _currentUser.value;

  @override
  Future<AuthResult> logIn({required String email, required String password}) {
    throw UnimplementedError();
  }

  @override
  Future<void> logOut() {
    throw UnimplementedError();
  }

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required DateTime birthday,
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }

  @override
  ValueListenable<AppUser?> watchCurrentUser() => _currentUser;
}

final _sampleUser = AppUser(
  id: 'user-1',
  email: 'maya@example.com',
  fullName: 'Maya Levy',
  birthday: DateTime(1995, 6, 20),
);
