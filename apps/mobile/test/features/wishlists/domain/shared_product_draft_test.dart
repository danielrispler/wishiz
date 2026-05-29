import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';

void main() {
  group('SharedProductDraft.hasCompleteRequiredFields', () {
    test('returns true when title and price are present, image absent', () {
      const draft = SharedProductDraft(
        productUrl: 'https://example.com/product',
        title: 'Nike Air Max 90',
        priceLabel: '\$120',
        imageUrl: null,
      );

      expect(draft.hasCompleteRequiredFields, isTrue);
    });

    test('returns false when title is absent', () {
      const draft = SharedProductDraft(
        productUrl: 'https://example.com/product',
        title: null,
        priceLabel: '\$120',
        imageUrl: 'https://example.com/img.jpg',
      );

      expect(draft.hasCompleteRequiredFields, isFalse);
    });

    test('returns false when price is absent', () {
      const draft = SharedProductDraft(
        productUrl: 'https://example.com/product',
        title: 'Nike Air Max 90',
        priceLabel: null,
        imageUrl: 'https://example.com/img.jpg',
      );

      expect(draft.hasCompleteRequiredFields, isFalse);
    });

    test('missingFieldLabels does not include image when image is absent', () {
      const draft = SharedProductDraft(
        productUrl: 'https://example.com/product',
        title: 'Nike Air Max 90',
        priceLabel: '\$120',
        imageUrl: null,
      );

      expect(draft.missingFieldLabels, isNot(contains('image')));
    });
  });
}
