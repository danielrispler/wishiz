import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/entities/auth_result.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/wishlists/data/repositories/in_memory_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/wishlists/screens/wishlist_detail/wishlist_detail_screen.dart';

void main() {
  group('WishlistDetailScreen past list', () {
    testWidgets('shows how many days each item has been on the list', (
      tester,
    ) async {
      final itemOne = WishlistItem(
        id: 'item-1',
        title: 'Espresso cups',
        rank: 1,
        status: WishlistItemStatus.purchased,
        purchasedAt: null,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      final itemTwo = WishlistItem(
        id: 'item-2',
        title: 'Serving tray',
        rank: 2,
        status: WishlistItemStatus.purchased,
        purchasedAt: null,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final repository = InMemoryWishlistRepository(
        ownerUserId: _sampleUser.id,
        initialWishlists: [
          _buildWishlist(items: [itemOne, itemTwo]),
        ],
      );

      await tester.pumpWidget(_buildSubject(repository: repository));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Espresso cups'), 300);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('days-on-list-item-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('days-on-list-item-2')), findsOneWidget);
    });

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
                status: WishlistItemStatus.purchased,
                purchasedAt: null,
                createdAt: DateTime.now().subtract(const Duration(days: 3)),
              ),
              WishlistItem(
                id: 'item-2',
                title: 'Serving tray',
                rank: 2,
                status: WishlistItemStatus.purchased,
                purchasedAt: null,
                createdAt: DateTime.now().subtract(const Duration(days: 1)),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(_buildSubject(repository: repository));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Restore all'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.widgetWithText(FilledButton, 'Restore all'), findsOneWidget);

      await tester.tap(find.text('Restore all'));
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
          'No purchased items yet. Swipe right on an active item to mark it as purchased.',
        ),
        findsOneWidget,
      );
    });
  });

  group('WishlistDetailScreen sharing', () {
    testWidgets('share dialog creates an editor invite link', (tester) async {
      final repository = InMemoryWishlistRepository(
        ownerUserId: _sampleUser.id,
        initialWishlists: [_buildWishlist()],
      );

      await tester.pumpWidget(
        _buildSubject(repository: repository, showPurchasedOnly: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Share list'));
      await tester.pumpAndSettle();

      expect(find.text('Shared people'), findsOneWidget);
      expect(find.text('Name'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Share list'));
      await tester.pumpAndSettle();

      final wishlist = repository.findById('wishlist-1');
      expect(wishlist?.invites.single.role, WishlistMemberRole.editor);
    });
  });
}

Widget _buildSubject({
  required InMemoryWishlistRepository repository,
  bool showPurchasedOnly = true,
}) {
  return MaterialApp(
    home: WishlistDetailScreen(
      repository: repository,
      authRepository: _FakeAuthRepository(currentUser: _sampleUser),
      sharedProductRepository: _FakeSharedProductRepository(),
      wishlistId: 'wishlist-1',
      showPurchasedOnly: showPurchasedOnly,
    ),
  );
}

Wishlist _buildWishlist({List<WishlistItem> items = const []}) {
  return Wishlist(
    id: 'wishlist-1',
    ownerUserId: _sampleUser.id,
    ownerFullName: _sampleUser.fullName,
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
    String sharedText, {
    String targetCurrencyCode = 'USD',
  }) async {
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
  Future<AuthResult> savePreferences({
    required List<String> brandNames,
    String? gender,
  }) async => AuthResult.success(getCurrentUser()!);

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
    String? gender,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResult> updateCurrentUser({
    required String email,
    required String fullName,
    required DateTime birthday,
    String? gender,
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
