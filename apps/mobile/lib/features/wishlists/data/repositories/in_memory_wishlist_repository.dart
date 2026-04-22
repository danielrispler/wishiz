import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_invite.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

class InMemoryWishlistRepository implements WishlistRepository {
  InMemoryWishlistRepository({
    required this.ownerUserId,
    List<Wishlist>? initialWishlists,
  }) : _wishlists = ValueNotifier<List<Wishlist>>(
         List<Wishlist>.unmodifiable(initialWishlists ?? const <Wishlist>[]),
       );

  static const Uuid _uuid = Uuid();

  final String ownerUserId;
  final ValueNotifier<List<Wishlist>> _wishlists;

  @override
  Future<void> refresh() async {}

  @override
  ValueListenable<List<Wishlist>> watchWishlists() => _wishlists;

  @override
  List<Wishlist> getWishlists() => _wishlists.value;

  @override
  Wishlist? findById(String id) {
    for (final wishlist in _wishlists.value) {
      if (wishlist.id == id) {
        return wishlist;
      }
    }

    return null;
  }

  @override
  Future<Wishlist?> joinWishlist({
    required String id,
    required String token,
  }) async {
    return findById(id);
  }

  @override
  Future<Wishlist> createWishlist({
    required String title,
    required String description,
    required int year,
    String? coverImageUrl,
  }) async {
    final now = DateTime.now();
    final wishlist = Wishlist(
      id: _uuid.v4(),
      ownerUserId: ownerUserId,
      ownerFullName: 'List Owner',
      title: title,
      description: description,
      year: year,
      coverImageUrl: coverImageUrl,
      createdAt: now,
      updatedAt: now,
    );

    _wishlists.value = List<Wishlist>.unmodifiable([
      wishlist,
      ..._wishlists.value,
    ]);
    return wishlist;
  }

  @override
  Future<Wishlist?> updateWishlist({
    required String id,
    required String title,
    required String description,
    required int year,
    String? coverImageUrl,
  }) async {
    return _replaceWishlist(
      id,
      (wishlist) => wishlist.copyWith(
        title: title,
        description: description,
        year: year,
        coverImageUrl: coverImageUrl,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<Wishlist?> archiveWishlist(String id) async {
    return _replaceWishlist(
      id,
      (wishlist) =>
          wishlist.copyWith(isArchived: true, updatedAt: DateTime.now()),
    );
  }

  @override
  Future<Wishlist?> restoreWishlist(String id) async {
    return _replaceWishlist(
      id,
      (wishlist) =>
          wishlist.copyWith(isArchived: false, updatedAt: DateTime.now()),
    );
  }

  @override
  Future<bool> deleteWishlist(String id) async {
    final previousLength = _wishlists.value.length;
    _wishlists.value = List<Wishlist>.unmodifiable(
      _wishlists.value.where((wishlist) => wishlist.id != id),
    );
    return previousLength != _wishlists.value.length;
  }

  @override
  Future<WishlistInvite> createInvite({
    required String wishlistId,
    required String email,
    required WishlistMemberRole role,
  }) async {
    final now = DateTime.now();
    final invite = WishlistInvite(
      id: _uuid.v4(),
      email: email,
      role: role,
      expiresAt: now.add(const Duration(days: 7)),
      createdAt: now,
      updatedAt: now,
      token: _uuid.v4(),
    );

    final updated = _replaceWishlist(wishlistId, (wishlist) {
      final normalizedEmail = email.toLowerCase();
      final invites = wishlist.invites.where(
        (existing) => existing.email.toLowerCase() != normalizedEmail,
      );
      return wishlist.copyWith(invites: [...invites, invite], updatedAt: now);
    });

    if (updated == null) {
      throw StateError('Wishlist "$wishlistId" was not found.');
    }
    return invite;
  }

  @override
  Future<bool> deleteInvite({
    required String wishlistId,
    required String inviteId,
  }) async {
    var wasRemoved = false;

    final updatedWishlist = _replaceWishlist(wishlistId, (wishlist) {
      final nextInvites = wishlist.invites
          .where((invite) => invite.id != inviteId)
          .toList(growable: false);
      wasRemoved = nextInvites.length != wishlist.invites.length;

      return wishlist.copyWith(
        invites: nextInvites,
        updatedAt: wasRemoved ? DateTime.now() : wishlist.updatedAt,
      );
    });

    return updatedWishlist != null && wasRemoved;
  }

  @override
  Future<bool> removeMember({
    required String wishlistId,
    required String userId,
  }) async {
    var wasRemoved = false;

    final updatedWishlist = _replaceWishlist(wishlistId, (wishlist) {
      final nextMembers = wishlist.members
          .where((member) => member.userId != userId)
          .toList(growable: false);
      wasRemoved = nextMembers.length != wishlist.members.length;

      return wishlist.copyWith(
        members: nextMembers,
        updatedAt: wasRemoved ? DateTime.now() : wishlist.updatedAt,
      );
    });

    return updatedWishlist != null && wasRemoved;
  }

  @override
  Future<WishlistItem> addWishlistItem({
    required String wishlistId,
    required String title,
    String? notes,
    String? priceLabel,
    WishlistItemPriority priority = WishlistItemPriority.medium,
    WishlistItemStatus status = WishlistItemStatus.saved,
    String? imageUrl,
    String? productUrl,
  }) async {
    final wishlist = findById(wishlistId);
    if (wishlist == null) {
      throw StateError('Wishlist "$wishlistId" was not found.');
    }

    final now = DateTime.now();
    final item = WishlistItem(
      id: _uuid.v4(),
      title: title,
      rank: _nextRankForWishlist(wishlist),
      notes: notes,
      priceLabel: priceLabel,
      priority: priority,
      status: status,
      imageUrl: imageUrl,
      productUrl: productUrl,
      purchasedAt: status == WishlistItemStatus.purchased ? now : null,
      createdAt: now,
    );

    final updatedWishlist = _replaceWishlist(
      wishlistId,
      (wishlist) =>
          wishlist.copyWith(items: [...wishlist.items, item], updatedAt: now),
    );

    if (updatedWishlist == null) {
      throw StateError('Wishlist "$wishlistId" was not found.');
    }

    return item;
  }

  @override
  Future<Wishlist?> reorderWishlistItems({
    required String wishlistId,
    required List<String> orderedItemIds,
  }) async {
    if (orderedItemIds.isEmpty) {
      return findById(wishlistId);
    }

    return _replaceWishlist(wishlistId, (wishlist) {
      final itemById = {for (final item in wishlist.items) item.id: item};
      final prioritizedItems = orderedItemIds
          .map(itemById.remove)
          .whereType<WishlistItem>()
          .toList(growable: false);
      final remainingItems = wishlist.items
          .where((item) => itemById.containsKey(item.id))
          .toList(growable: false);
      final reorderedItems = [...prioritizedItems, ...remainingItems];
      final rankedItems = List<WishlistItem>.generate(
        reorderedItems.length,
        (index) => reorderedItems[index].copyWith(rank: index + 1),
        growable: false,
      );

      return wishlist.copyWith(items: rankedItems, updatedAt: DateTime.now());
    });
  }

  @override
  Future<WishlistItem?> updateWishlistItemStatus({
    required String wishlistId,
    required String itemId,
    required WishlistItemStatus status,
  }) async {
    WishlistItem? updatedItem;
    var didUpdate = false;
    final now = DateTime.now();

    final updatedWishlist = _replaceWishlist(wishlistId, (wishlist) {
      final nextItems = wishlist.items
          .map((item) {
            if (item.id != itemId) {
              return item;
            }

            updatedItem = item.copyWith(
              status: status,
              purchasedAt: _nextPurchasedAt(
                previousStatus: item.status,
                nextStatus: status,
                currentPurchasedAt: item.purchasedAt,
                now: now,
              ),
            );
            didUpdate = true;
            return updatedItem!;
          })
          .toList(growable: false);

      return wishlist.copyWith(
        items: nextItems,
        updatedAt: didUpdate ? now : wishlist.updatedAt,
      );
    });

    if (updatedWishlist == null || !didUpdate) {
      return null;
    }

    return updatedItem;
  }

  @override
  Future<WishlistItem?> updateWishlistItem({
    required String wishlistId,
    required String itemId,
    required String title,
    String? notes,
    String? priceLabel,
    WishlistItemPriority priority = WishlistItemPriority.medium,
    WishlistItemStatus status = WishlistItemStatus.saved,
    String? imageUrl,
    String? productUrl,
  }) async {
    WishlistItem? updatedItem;
    var didUpdate = false;
    final now = DateTime.now();

    final updatedWishlist = _replaceWishlist(wishlistId, (wishlist) {
      final nextItems = wishlist.items
          .map((item) {
            if (item.id != itemId) {
              return item;
            }

            updatedItem = item.copyWith(
              title: title,
              notes: notes,
              priceLabel: priceLabel,
              priority: priority,
              status: status,
              imageUrl: imageUrl,
              productUrl: productUrl,
              purchasedAt: _nextPurchasedAt(
                previousStatus: item.status,
                nextStatus: status,
                currentPurchasedAt: item.purchasedAt,
                now: now,
              ),
            );
            didUpdate = true;
            return updatedItem!;
          })
          .toList(growable: false);

      return wishlist.copyWith(
        items: nextItems,
        updatedAt: didUpdate ? now : wishlist.updatedAt,
      );
    });

    if (updatedWishlist == null || !didUpdate) {
      return null;
    }

    return updatedItem;
  }

  @override
  Future<bool> deleteWishlistItem({
    required String wishlistId,
    required String itemId,
  }) async {
    var wasDeleted = false;

    final updatedWishlist = _replaceWishlist(wishlistId, (wishlist) {
      final nextItems = wishlist.items
          .where((item) => item.id != itemId)
          .toList(growable: false);
      wasDeleted = nextItems.length != wishlist.items.length;

      return wishlist.copyWith(
        items: nextItems,
        updatedAt: wasDeleted ? DateTime.now() : wishlist.updatedAt,
      );
    });

    return updatedWishlist != null && wasDeleted;
  }

  Wishlist? _replaceWishlist(
    String id,
    Wishlist Function(Wishlist wishlist) update,
  ) {
    Wishlist? updatedWishlist;
    final nextWishlists = _wishlists.value
        .map((wishlist) {
          if (wishlist.id != id) {
            return wishlist;
          }

          updatedWishlist = update(wishlist);
          return updatedWishlist!;
        })
        .toList(growable: false);

    if (updatedWishlist == null) {
      return null;
    }

    _wishlists.value = List<Wishlist>.unmodifiable(nextWishlists);
    return updatedWishlist;
  }

  int _nextRankForWishlist(Wishlist wishlist) {
    return wishlist.items.fold<int>(
          0,
          (highestRank, item) => math.max(highestRank, item.rank),
        ) +
        1;
  }

  DateTime? _nextPurchasedAt({
    required WishlistItemStatus previousStatus,
    required WishlistItemStatus nextStatus,
    required DateTime? currentPurchasedAt,
    required DateTime now,
  }) {
    if (nextStatus != WishlistItemStatus.purchased) {
      return null;
    }
    if (previousStatus != WishlistItemStatus.purchased) {
      return now;
    }

    return currentPurchasedAt;
  }
}
