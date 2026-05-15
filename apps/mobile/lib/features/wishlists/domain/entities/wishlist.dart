import 'package:wishiz/features/wishlists/domain/entities/wishlist_invite.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_member.dart';

class Wishlist {
  Wishlist({
    required this.id,
    required this.ownerUserId,
    required this.ownerFullName,
    required this.title,
    required this.description,
    required this.year,
    this.coverImageUrl,
    required this.createdAt,
    required this.updatedAt,
    this.isArchived = false,
    List<WishlistMember>? members,
    List<WishlistInvite>? invites,
    List<WishlistItem>? items,
  }) : members = List.unmodifiable(members ?? const <WishlistMember>[]),
       invites = List.unmodifiable(invites ?? const <WishlistInvite>[]),
       items = List.unmodifiable(items ?? const <WishlistItem>[]);

  final String id;
  final String ownerUserId;
  final String ownerFullName;
  final String title;
  final String description;
  final int year;
  final String? coverImageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;
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
    String? ownerFullName,
    String? title,
    String? description,
    int? year,
    Object? coverImageUrl = _noValue,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isArchived,
    List<WishlistMember>? members,
    List<WishlistInvite>? invites,
    List<WishlistItem>? items,
  }) {
    return Wishlist(
      id: id ?? this.id,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      ownerFullName: ownerFullName ?? this.ownerFullName,
      title: title ?? this.title,
      description: description ?? this.description,
      year: year ?? this.year,
      coverImageUrl: identical(coverImageUrl, _noValue)
          ? this.coverImageUrl
          : coverImageUrl as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
      members: members ?? this.members,
      invites: invites ?? this.invites,
      items: items ?? this.items,
    );
  }
}

const Object _noValue = Object();
