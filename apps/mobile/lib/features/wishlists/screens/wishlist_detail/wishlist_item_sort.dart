import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';

enum SortField { rank, price, dateAdded }

const _defaultAscending = {
  SortField.rank: true,
  SortField.price: true,
  SortField.dateAdded: false,
};

class SortCriterion {
  const SortCriterion(this.field, {this.ascending = true});

  factory SortCriterion.defaultFor(SortField field) =>
      SortCriterion(field, ascending: _defaultAscending[field]!);

  final SortField field;
  final bool ascending;

  bool get isDefault => field == SortField.rank && ascending;

  SortCriterion copyWith({bool? ascending}) =>
      SortCriterion(field, ascending: ascending ?? this.ascending);

  SortCriterion toggleDirection() => SortCriterion(field, ascending: !ascending);

  String get label {
    final name = switch (field) {
      SortField.rank => 'Rank',
      SortField.price => 'Price',
      SortField.dateAdded => 'Date',
    };
    return '$name ${ascending ? '↑' : '↓'}';
  }

  @override
  bool operator ==(Object other) =>
      other is SortCriterion && other.field == field && other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);
}

List<WishlistItem> sortWishlistItems(
  List<WishlistItem> items,
  List<SortCriterion> criteria,
) {
  final sorted = List<WishlistItem>.from(items);
  sorted.sort((a, b) {
    for (final c in criteria) {
      final cmp = switch (c.field) {
        SortField.rank => c.ascending
            ? a.rank.compareTo(b.rank)
            : b.rank.compareTo(a.rank),
        SortField.price => _compareNullable(
            _parsePrice(a.priceLabel), _parsePrice(b.priceLabel),
            ascending: c.ascending),
        SortField.dateAdded => c.ascending
            ? a.createdAt.compareTo(b.createdAt)
            : b.createdAt.compareTo(a.createdAt),
      };
      if (cmp != 0) return cmp;
    }
    return 0;
  });
  return sorted;
}

double? _parsePrice(String? label) {
  if (label == null || label.isEmpty) return null;
  return double.tryParse(label.replaceAll(RegExp(r'[^\d.]'), ''));
}

int _compareNullable(double? a, double? b, {required bool ascending}) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  final cmp = a.compareTo(b);
  return ascending ? cmp : -cmp;
}
