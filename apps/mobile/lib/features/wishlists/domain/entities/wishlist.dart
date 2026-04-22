import 'package:wishiz/features/wishlists/domain/entities/wishlist_invite.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_member.dart';

class Wishlist {
  Wishlist({
    required this.id,
    required this.ownerUserId,
    required this.title,
    required this.description,
    required this.year,
    this.coverImageUrl,
    required this.createdAt,
    required this.updatedAt,
    this.isArchived = false,
    this.shareToken = '',
    List<WishlistMember> members = const [],
    List<WishlistInvite> invites = const [],
    List<WishlistItem> items = const [],
  }) : members = List.unmodifiable(members),
       invites = List.unmodifiable(invites),
       items = List.unmodifiable(items);

  final String id;
  final String ownerUserId;
  final String title;
  final String description;
  final int year;
  final String? coverImageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;
  final String shareToken;
  final List<WishlistMember> members;
  final List<WishlistInvite> invites;
  final List<WishlistItem> items;

  int get itemCount => items.length;
  List<WishlistItem> get activeItems => List.unmodifiable(
    items.where((item) => item.status != WishlistItemStatus.purchased),
  );
  List<WishlistItem> get purchasedItems => List.unmodifiable(
    items.where((item) => item.status == WishlistItemStatus.purchased),
  );
  int get activeItemCount => activeItems.length;
  int get purchasedItemCount => purchasedItems.length;

  Wishlist copyWith({
    String? id,
    String? ownerUserId,
    String? title,
    String? description,
    int? year,
    Object? coverImageUrl = _noValue,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isArchived,
    String? shareToken,
    List<WishlistMember>? members,
    List<WishlistInvite>? invites,
    List<WishlistItem>? items,
  }) {
    return Wishlist(
      id: id ?? this.id,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      title: title ?? this.title,
      description: description ?? this.description,
      year: year ?? this.year,
      coverImageUrl: identical(coverImageUrl, _noValue)
          ? this.coverImageUrl
          : coverImageUrl as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
      shareToken: shareToken ?? this.shareToken,
      members: members ?? this.members,
      invites: invites ?? this.invites,
      items: items ?? this.items,
    );
  }
}

const Object _noValue = Object();
