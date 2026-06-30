import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/entities/auth_result.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/notifications/data/in_memory_notifications_repository.dart';
import 'package:wishiz/features/product_imports/data/in_memory_product_import_repository.dart';
import 'package:wishiz/features/wishlists/data/repositories/in_memory_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_member.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/home/screens/home/home_screen.dart';

void main() {
  group('HomeScreen — Shared Lists tab', () {
    testWidgets(
      'owner\'s list with collaborators stays in My Lists, not Shared Lists',
      (tester) async {
        final ownedListWithMember = _buildWishlist(
          id: 'my-list',
          ownerUserId: _currentUser.id,
          title: 'Birthday Wishes',
          members: [
            WishlistMember(
              userId: 'other-user',
              email: 'friend@example.com',
              fullName: 'Friend',
              role: WishlistMemberRole.viewer,
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          ],
        );

        final repository = InMemoryWishlistRepository(
          ownerUserId: _currentUser.id,
          initialWishlists: [ownedListWithMember],
        );

        await tester.pumpWidget(_buildSubject(repository: repository));
        await tester.pumpAndSettle();

        // Should appear in Lists tab (index 0 is default)
        expect(find.text('Birthday Wishes'), findsOneWidget);

        // Navigate to Shared tab (tap icon — label only shows when selected)
        await tester.tap(find.byIcon(Icons.favorite_outline_rounded));
        await tester.pumpAndSettle();

        // Should NOT appear in Shared tab — user owns it
        expect(find.text('Birthday Wishes'), findsNothing);
        expect(find.text('Nothing shared yet'), findsOneWidget);
      },
    );

    testWidgets(
      'list owned by another user appears in Shared Lists tab',
      (tester) async {
        final otherUsersList = _buildWishlist(
          id: 'their-list',
          ownerUserId: 'other-user-id',
          title: 'Their Wishlist',
        );

        final repository = InMemoryWishlistRepository(
          ownerUserId: _currentUser.id,
          initialWishlists: [otherUsersList],
        );

        await tester.pumpWidget(_buildSubject(repository: repository));
        await tester.pumpAndSettle();

        // Should NOT appear in Lists tab
        expect(find.text('Their Wishlist'), findsNothing);

        // Navigate to Shared tab (tap icon — label only shows when selected)
        await tester.tap(find.byIcon(Icons.favorite_outline_rounded));
        await tester.pumpAndSettle();

        // Should appear in Shared tab
        expect(find.text('Their Wishlist'), findsOneWidget);
      },
    );
  });
}

final _currentUser = AppUser(
  id: 'user-1',
  email: 'me@example.com',
  fullName: 'Me',
  birthday: DateTime(1990, 1, 1),
);

Widget _buildSubject({required InMemoryWishlistRepository repository}) {
  return MaterialApp(
    home: HomeScreen(
      repository: repository,
      productImportRepository: InMemoryProductImportRepository(),
      notificationsRepository: InMemoryNotificationsRepository(),
      sharedProductRepository: _FakeSharedProductRepository(),
      authRepository: _FakeAuthRepository(currentUser: _currentUser),
      currentUser: _currentUser,
    ),
  );
}

Wishlist _buildWishlist({
  required String id,
  required String ownerUserId,
  required String title,
  List<WishlistMember> members = const [],
}) {
  return Wishlist(
    id: id,
    ownerUserId: ownerUserId,
    ownerFullName: 'Owner',
    title: title,
    description: '',
    year: 2026,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    members: members,
  );
}

class _FakeSharedProductRepository implements SharedProductRepository {
  @override
  Future<SharedProductDraft?> createDraftFromSharedText(
    String sharedText, {
    String targetCurrencyCode = 'USD',
  }) async => null;
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({AppUser? currentUser})
    : _currentUser = ValueNotifier<AppUser?>(currentUser);

  final ValueNotifier<AppUser?> _currentUser;

  @override
  AppUser? getCurrentUser() => _currentUser.value;

  @override
  ValueListenable<AppUser?> watchCurrentUser() => _currentUser;

  @override
  Future<AuthResult> logIn({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required DateTime birthday,
    String? gender,
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

  @override
  Future<AuthResult> savePreferences({
    required List<String> brandNames,
    String? gender,
  }) async => AuthResult.success(getCurrentUser()!);

  @override
  Future<void> logOut() => throw UnimplementedError();
}
