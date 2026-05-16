import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/entities/auth_result.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/wishlists/data/repositories/in_memory_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/app/dependencies.dart';
import 'package:wishiz/app/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('uses the default backend URL when no dart define is passed', (
    tester,
  ) async {
    String? capturedBaseUrl;

    await tester.pumpWidget(
      await createApp(
        authRepositoryFactory: (baseUrl) async {
          capturedBaseUrl = baseUrl;
          return _FakeAuthRepository();
        },
        sharedProductRepositoryFactory: (_) =>
            const _FakeSharedProductRepository(),
        clearLegacyWishlistStorage: () async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(capturedBaseUrl, 'https://wishiz.app');
    expect(
      find.text('Could not connect to the wishlist backend.'),
      findsNothing,
    );
  });

  testWidgets('shows a blocking error when startup cannot reach the backend', (
    tester,
  ) async {
    await tester.pumpWidget(
      await createApp(
        baseUrlOverride: 'https://api.example.com',
        authRepositoryFactory: (_) async {
          throw StateError('connection refused');
        },
        clearLegacyWishlistStorage: () async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Could not connect to the wishlist backend.'),
      findsOneWidget,
    );
    expect(find.textContaining('connection refused'), findsOneWidget);
  });

  testWidgets('renders the empty home state without demo wishlists', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository(currentUser: _sampleUser);

    await tester.pumpWidget(
      WishizApp(
        wishlistRepositoryLoader: (_) async =>
            InMemoryWishlistRepository(ownerUserId: _sampleUser.id),
        authRepository: authRepository,
        sharedProductRepository: const _FakeSharedProductRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No active lists yet'), findsOneWidget);
    expect(find.text('Home Decor'), findsNothing);
    expect(find.text('Tech Gear 2024'), findsNothing);
    expect(find.text('Weekend Hosting'), findsNothing);
  });
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({AppUser? currentUser})
    : _currentUser = currentUser,
      _notifier = ValueNotifier<AppUser?>(currentUser);

  AppUser? _currentUser;
  final ValueNotifier<AppUser?> _notifier;

  @override
  AppUser? getCurrentUser() => _currentUser;

  @override
  Future<AuthResult> logIn({
    required String email,
    required String password,
  }) async => const AuthResult.failure('unused');

  @override
  Future<AuthResult> savePreferences({
    required List<String> brandNames,
  }) async => AuthResult.success(getCurrentUser()!);

  @override
  Future<void> logOut() async {
    _currentUser = null;
    _notifier.value = null;
  }

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required DateTime birthday,
  }) async => const AuthResult.failure('unused');

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
  }) async => const AuthResult.failure('unused');

  @override
  ValueListenable<AppUser?> watchCurrentUser() => _notifier;
}

class _FakeSharedProductRepository implements SharedProductRepository {
  const _FakeSharedProductRepository();

  @override
  Future<SharedProductDraft?> createDraftFromSharedText(
    String sharedText, {
    String targetCurrencyCode = 'USD',
  }) async {
    return null;
  }
}

final _sampleUser = AppUser(
  id: 'user-1',
  email: 'maya@example.com',
  fullName: 'Maya Hope',
  birthday: DateTime(1992, 6, 15),
);
