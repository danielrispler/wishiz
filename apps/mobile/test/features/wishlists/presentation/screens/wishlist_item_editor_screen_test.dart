import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/data/repositories/in_memory_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_item_editor_screen.dart';

void main() {
  group('WishlistItemEditorScreen imported link preview', () {
    testWidgets('shows a disclaimer for shared imports', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildSubject(
          isSharedImport: true,
          initialTitle: 'Imported mug',
          initialPriceLabel: 'USD 24.00',
          initialImageUrl: 'https://example.com/mug.png',
          initialProductUrl: 'https://example.com/products/mug',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Preview Item'), findsOneWidget);
      expect(find.text('Imported details may have problems'), findsOneWidget);
      expect(
        find.text(
          'Please verify the title, price, image, and link before saving. You can edit everything in this preview.',
        ),
        findsOneWidget,
      );
      expect(find.text('Verify And Save'), findsOneWidget);
    });

    testWidgets('shows the same disclaimer after generating from a link', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final sharedProductRepository = _FakeSharedProductRepository();

      await tester.pumpWidget(
        _buildSubject(sharedProductRepository: sharedProductRepository),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).last,
        'https://example.com/products/lamp',
      );
      await tester.tap(find.text('Generate From Link'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(sharedProductRepository.requestedSharedTexts, [
        'https://example.com/products/lamp',
      ]);
      expect(find.text('Preview Item'), findsOneWidget);
      expect(find.text('Imported details may have problems'), findsOneWidget);
      expect(find.text('Verify And Save'), findsOneWidget);
      expect(find.text('Generated lamp'), findsOneWidget);
    });
  });
}

Widget _buildSubject({
  SharedProductRepository? sharedProductRepository,
  bool isSharedImport = false,
  String? initialTitle,
  String? initialPriceLabel,
  String? initialImageUrl,
  String? initialProductUrl,
}) {
  final repository = InMemoryWishlistRepository(
    ownerUserId: 'user-1',
    initialWishlists: [
      Wishlist(
        id: 'wishlist-1',
        ownerUserId: 'user-1',
        title: 'Birthdays',
        description: 'Family gifts',
        year: 2026,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    ],
  );

  return MaterialApp(
    home: WishlistItemEditorScreen(
      repository: repository,
      wishlistId: 'wishlist-1',
      preferredCurrencyCode: 'USD',
      preferredCurrencySymbol: '\$',
      sharedProductRepository: sharedProductRepository,
      initialTitle: initialTitle,
      initialPriceLabel: initialPriceLabel,
      initialImageUrl: initialImageUrl,
      initialProductUrl: initialProductUrl,
      isSharedImport: isSharedImport,
    ),
  );
}

class _FakeSharedProductRepository implements SharedProductRepository {
  final List<String> requestedSharedTexts = [];

  @override
  Future<SharedProductDraft?> createDraftFromSharedText(
    String sharedText,
  ) async {
    requestedSharedTexts.add(sharedText);
    return SharedProductDraft(
      productUrl: sharedText,
      title: 'Generated lamp',
      notes: 'Verify the finish',
      priceLabel: 'USD 48.00',
      imageUrl: 'https://example.com/lamp.png',
      sharedText: sharedText,
    );
  }
}
