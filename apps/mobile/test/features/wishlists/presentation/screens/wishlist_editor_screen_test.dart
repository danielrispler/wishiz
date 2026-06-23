import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/data/repositories/in_memory_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/screens/wishlist_editor/wishlist_editor_screen.dart';

void main() {
  group('WishlistEditorScreen', () {
    testWidgets('renders list form content on a phone-sized screen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Edit List'), findsOneWidget);
      expect(find.text('List details'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'List title'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Short note'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Save Changes'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Save Changes'), findsOneWidget);
    });
  });
}

Widget _buildSubject() {
  final repository = InMemoryWishlistRepository(
    ownerUserId: 'user-1',
    initialWishlists: [
      Wishlist(
        id: 'wishlist-1',
        ownerUserId: 'user-1',
        ownerFullName: 'Maya Chen',
        title: 'Birthdays',
        description: 'Family gifts',
        year: 2026,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    ],
  );

  return MaterialApp(
    home: WishlistEditorScreen(
      repository: repository,
      wishlist: repository.findById('wishlist-1'),
    ),
  );
}
