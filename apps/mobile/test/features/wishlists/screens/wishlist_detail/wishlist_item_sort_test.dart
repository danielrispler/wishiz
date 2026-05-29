import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/screens/wishlist_detail/wishlist_item_sort.dart';

void main() {
  group('sortWishlistItems', () {
    test('single rank criterion sorts ascending by rank', () {
      final items = [_item('a', rank: 3), _item('b', rank: 1), _item('c', rank: 2)];
      final result = sortWishlistItems(items, const [SortCriterion(SortField.rank)]);
      expect(result.map((i) => i.id), ['b', 'c', 'a']);
    });

    test('single rank criterion descending sorts by rank desc', () {
      final items = [_item('a', rank: 1), _item('b', rank: 3), _item('c', rank: 2)];
      final result = sortWishlistItems(
        items,
        const [SortCriterion(SortField.rank, ascending: false)],
      );
      expect(result.map((i) => i.id), ['b', 'c', 'a']);
    });

    test('multi-key: price asc then rank asc for equal prices', () {
      final items = [
        _item('a', rank: 2, price: '\$50'),
        _item('b', rank: 1, price: '\$50'),
        _item('c', rank: 1, price: '\$30'),
      ];
      final result = sortWishlistItems(items, const [
        SortCriterion(SortField.price),
        SortCriterion(SortField.rank),
      ]);
      expect(result.map((i) => i.id), ['c', 'b', 'a']);
    });

    test('null price sorts last in price ascending sort', () {
      final items = [
        _item('a', rank: 1, price: null),
        _item('b', rank: 2, price: '\$20'),
        _item('c', rank: 3, price: '\$10'),
      ];
      final result = sortWishlistItems(items, const [SortCriterion(SortField.price)]);
      expect(result.map((i) => i.id), ['c', 'b', 'a']);
    });

    test('date added descending puts newest first', () {
      final items = [
        _item('a', rank: 1, createdAt: DateTime(2026, 1, 1)),
        _item('b', rank: 2, createdAt: DateTime(2026, 3, 1)),
        _item('c', rank: 3, createdAt: DateTime(2026, 2, 1)),
      ];
      final result = sortWishlistItems(
        items,
        const [SortCriterion(SortField.dateAdded, ascending: false)],
      );
      expect(result.map((i) => i.id), ['b', 'c', 'a']);
    });
  });
}

WishlistItem _item(
  String id, {
  required int rank,
  String? price,
  DateTime? createdAt,
}) {
  return WishlistItem(
    id: id,
    title: 'Item $id',
    rank: rank,
    priceLabel: price,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
  );
}
