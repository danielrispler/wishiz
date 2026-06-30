import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/entities/auth_result.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/notifications/data/in_memory_notifications_repository.dart';
import 'package:wishiz/features/notifications/domain/entities/app_notification.dart';
import 'package:wishiz/features/notifications/screens/inbox/notifications_screen.dart';
import 'package:wishiz/features/wishlists/data/repositories/in_memory_wishlist_repository.dart';

void main() {
  final user = AppUser(
    id: 'user-1',
    email: 'me@example.com',
    fullName: 'Me',
    birthday: DateTime(1990, 1, 1),
  );

  AppNotification notification(String id, {DateTime? readAt, String? wishlistId = 'w1'}) {
    return AppNotification(
      id: id,
      type: NotificationType.itemAdded,
      title: 'Maya added an item ($id)',
      body: 'Headphones',
      wishlistId: wishlistId,
      readAt: readAt,
      createdAt: DateTime.now(),
    );
  }

  AppNotification importNotification(String id, {String? wishlistId, String? importJobId = 'job-1'}) {
    return AppNotification(
      id: id,
      type: NotificationType.importSettled,
      title: 'Import ($id)',
      body: '',
      wishlistId: wishlistId,
      importJobId: importJobId,
      createdAt: DateTime.now(),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    InMemoryNotificationsRepository repo, {
    required void Function(String) onOpenWishlist,
    VoidCallback? onOpenImportQueue,
  }) async {
    final screen = NotificationsScreen(
      authRepository: _FakeAuthRepository(currentUser: user),
      wishlistRepository: InMemoryWishlistRepository(ownerUserId: user.id),
      notificationsRepository: repo,
      currentUser: user,
      onOpenWishlist: onOpenWishlist,
      onOpenImportQueue: onOpenImportQueue,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => screen)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders event cards and marks read + navigates on tap', (tester) async {
    final repo = InMemoryNotificationsRepository(initial: [notification('n1')]);
    String? opened;
    await pumpScreen(tester, repo, onOpenWishlist: (id) => opened = id);

    expect(find.text('Maya added an item (n1)'), findsOneWidget);
    expect(repo.watchUnreadCount().value, 1);

    await tester.tap(find.text('Maya added an item (n1)'));
    await tester.pumpAndSettle();

    expect(opened, 'w1');
    expect(repo.watchUnreadCount().value, 0);
  });

  testWidgets('mark all read clears the unread count', (tester) async {
    final repo = InMemoryNotificationsRepository(
      initial: [notification('n1'), notification('n2')],
    );
    await pumpScreen(tester, repo, onOpenWishlist: (_) {});

    expect(repo.watchUnreadCount().value, 2);

    await tester.tap(find.text('Mark all read'));
    await tester.pump();

    expect(repo.watchUnreadCount().value, 0);
  });

  testWidgets('needs-review import (no wishlist) routes to the import queue', (tester) async {
    // Backend sends a nil wishlistId for needs_review, so the tap must fall through
    // to the import-review queue instead of opening an empty list.
    final repo = InMemoryNotificationsRepository(
      initial: [importNotification('n1', wishlistId: null)],
    );
    String? opened;
    var queueOpened = false;
    await pumpScreen(
      tester,
      repo,
      onOpenWishlist: (id) => opened = id,
      onOpenImportQueue: () => queueOpened = true,
    );

    await tester.tap(find.text('Import (n1)'));
    await tester.pumpAndSettle();

    expect(queueOpened, isTrue);
    expect(opened, isNull);
  });

  testWidgets('completed import (with wishlist) opens the wishlist', (tester) async {
    // A completed import carries the destination list — the tap opens it, NOT the
    // queue, even though importJobId is also present.
    final repo = InMemoryNotificationsRepository(
      initial: [importNotification('n1', wishlistId: 'w1')],
    );
    String? opened;
    var queueOpened = false;
    await pumpScreen(
      tester,
      repo,
      onOpenWishlist: (id) => opened = id,
      onOpenImportQueue: () => queueOpened = true,
    );

    await tester.tap(find.text('Import (n1)'));
    await tester.pumpAndSettle();

    expect(opened, 'w1');
    expect(queueOpened, isFalse);
  });

  testWidgets('shows an empty hint when there are no notifications', (tester) async {
    final repo = InMemoryNotificationsRepository();
    await pumpScreen(tester, repo, onOpenWishlist: (_) {});

    expect(find.textContaining('No notifications yet'), findsOneWidget);
  });
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
    DateTime? birthday,
    String? gender,
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

  @override
  Future<AuthResult> savePreferences({
    required List<String> brandNames,
    String? gender,
  }) async => AuthResult.success(getCurrentUser()!);

  @override
  Future<void> deleteAccount({required String password}) async {}

  @override
  Future<void> logOut() => throw UnimplementedError();
}
