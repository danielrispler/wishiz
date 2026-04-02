import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_user.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

class InMemoryWishlistRepository implements WishlistRepository {
  InMemoryWishlistRepository({
    required this.ownerUserId,
    List<Wishlist>? initialWishlists,
  })
      : _wishlists = ValueNotifier<List<Wishlist>>(
          List<Wishlist>.unmodifiable(
            initialWishlists ?? seedWishlists(ownerUserId: ownerUserId),
          ),
        );

  static final InMemoryWishlistRepository instance =
      InMemoryWishlistRepository(ownerUserId: 'demo-user');
  static const Uuid _uuid = Uuid();

  final String ownerUserId;
  final ValueNotifier<List<Wishlist>> _wishlists;

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
  Future<Wishlist> createWishlist({
    required String title,
    required String description,
    required int year,
    String? coverImageUrl,
    bool isShared = false,
  }) async {
    final now = DateTime.now();
    final wishlist = Wishlist(
      id: _uuid.v4(),
      ownerUserId: ownerUserId,
      title: title,
      description: description,
      year: year,
      coverImageUrl: coverImageUrl,
      createdAt: now,
      updatedAt: now,
      isShared: isShared,
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
    bool? isShared,
  }) async {
    return _replaceWishlist(
      id,
      (wishlist) => wishlist.copyWith(
        title: title,
        description: description,
        year: year,
        coverImageUrl: coverImageUrl,
        isShared: isShared ?? wishlist.isShared,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<Wishlist?> archiveWishlist(String id) async {
    return _replaceWishlist(
      id,
      (wishlist) => wishlist.copyWith(
        isArchived: true,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<Wishlist?> restoreWishlist(String id) async {
    return _replaceWishlist(
      id,
      (wishlist) => wishlist.copyWith(
        isArchived: false,
        updatedAt: DateTime.now(),
      ),
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
  Future<Wishlist?> addSharedUser({
    required String wishlistId,
    required String name,
    required String email,
    required String role,
  }) async {
    return _replaceWishlist(
      wishlistId,
      (wishlist) {
        final normalizedEmail = email.toLowerCase();
        final alreadyExists = wishlist.sharedUsers.any(
          (user) => user.email.toLowerCase() == normalizedEmail,
        );
        if (alreadyExists) {
          return wishlist;
        }

        return wishlist.copyWith(
          isShared: true,
          sharedUsers: [
            ...wishlist.sharedUsers,
            SharedUser(
              id: _uuid.v4(),
              name: name,
              email: email,
              role: role,
            ),
          ],
          updatedAt: DateTime.now(),
        );
      },
    );
  }

  @override
  Future<bool> removeSharedUser({
    required String wishlistId,
    required String userId,
  }) async {
    var wasRemoved = false;

    final updatedWishlist = _replaceWishlist(
      wishlistId,
      (wishlist) {
        final nextUsers = wishlist.sharedUsers
            .where((user) => user.id != userId)
            .toList(growable: false);
        wasRemoved = nextUsers.length != wishlist.sharedUsers.length;

        return wishlist.copyWith(
          isShared: nextUsers.isNotEmpty,
          sharedUsers: nextUsers,
          updatedAt: wasRemoved ? DateTime.now() : wishlist.updatedAt,
        );
      },
    );

    return updatedWishlist != null && wasRemoved;
  }

  @override
  Future<WishlistItem> addWishlistItem({
    required String wishlistId,
    required String title,
    String? notes,
    String? priceLabel,
    String priority = 'Medium',
    String status = 'Saved',
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
      purchasedAt: status == 'Purchased' ? now : null,
      createdAt: now,
    );

    final updatedWishlist = _replaceWishlist(
      wishlistId,
      (wishlist) => wishlist.copyWith(
        items: [...wishlist.items, item],
        updatedAt: now,
      ),
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

    return _replaceWishlist(
      wishlistId,
      (wishlist) {
        final itemById = {
          for (final item in wishlist.items) item.id: item,
        };
        final prioritizedItems = orderedItemIds
            .map(itemById.remove)
            .whereType<WishlistItem>()
            .toList(growable: false);
        final remainingItems = wishlist.items
            .where((item) => itemById.containsKey(item.id))
            .toList(growable: false);
        final reorderedItems = [
          ...prioritizedItems,
          ...remainingItems,
        ];
        final rankedItems = List<WishlistItem>.generate(
          reorderedItems.length,
          (index) => reorderedItems[index].copyWith(rank: index + 1),
          growable: false,
        );

        return wishlist.copyWith(
          items: rankedItems,
          updatedAt: DateTime.now(),
        );
      },
    );
  }

  @override
  Future<WishlistItem?> updateWishlistItemStatus({
    required String wishlistId,
    required String itemId,
    required String status,
  }) async {
    WishlistItem? updatedItem;
    var didUpdate = false;
    final now = DateTime.now();

    final updatedWishlist = _replaceWishlist(
      wishlistId,
      (wishlist) {
        final nextItems = wishlist.items.map((item) {
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
        }).toList(growable: false);

        return wishlist.copyWith(
          items: nextItems,
          updatedAt: didUpdate ? now : wishlist.updatedAt,
        );
      },
    );

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
    String priority = 'Medium',
    String status = 'Saved',
    String? imageUrl,
    String? productUrl,
  }) async {
    WishlistItem? updatedItem;
    var didUpdate = false;
    final now = DateTime.now();

    final updatedWishlist = _replaceWishlist(
      wishlistId,
      (wishlist) {
        final nextItems = wishlist.items.map((item) {
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
        }).toList(growable: false);

        return wishlist.copyWith(
          items: nextItems,
          updatedAt: didUpdate ? now : wishlist.updatedAt,
        );
      },
    );

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

    final updatedWishlist = _replaceWishlist(
      wishlistId,
      (wishlist) {
        final nextItems = wishlist.items
            .where((item) => item.id != itemId)
            .toList(growable: false);
        wasDeleted = nextItems.length != wishlist.items.length;

        return wishlist.copyWith(
          items: nextItems,
          updatedAt: wasDeleted ? DateTime.now() : wishlist.updatedAt,
        );
      },
    );

    return updatedWishlist != null && wasDeleted;
  }

  Wishlist? _replaceWishlist(
    String id,
    Wishlist Function(Wishlist wishlist) update,
  ) {
    Wishlist? updatedWishlist;
    final nextWishlists = _wishlists.value.map((wishlist) {
      if (wishlist.id != id) {
        return wishlist;
      }

      updatedWishlist = update(wishlist);
      return updatedWishlist!;
    }).toList(growable: false);

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
    required String previousStatus,
    required String nextStatus,
    required DateTime? currentPurchasedAt,
    required DateTime now,
  }) {
    if (nextStatus != 'Purchased') {
      return null;
    }
    if (previousStatus != 'Purchased') {
      return now;
    }

    return currentPurchasedAt;
  }

  static List<Wishlist> seedWishlists({
    required String ownerUserId,
  }) {
    final now = DateTime.now();

    return [
      Wishlist(
        id: 'home-decor',
        ownerUserId: ownerUserId,
        title: 'Home Decor',
        description:
            'Soft lighting, sculptural objects, and pieces for a calmer living room.',
        year: 2026,
        coverImageUrl: 'https://picsum.photos/seed/home-decor/1200/800',
        createdAt: now.subtract(const Duration(days: 21)),
        updatedAt: now.subtract(const Duration(days: 2)),
        items: [
          WishlistItem(
            id: 'decor-lamp',
            title: 'Marble table lamp',
            rank: 1,
            notes: 'Warm bulb, low profile shade.',
            priceLabel: '\$180',
            priority: 'High',
            status: 'Saved',
            imageUrl: 'https://picsum.photos/seed/decor-lamp/900/700',
            createdAt: now.subtract(const Duration(days: 7)),
          ),
          WishlistItem(
            id: 'decor-vase',
            title: 'Stoneware floor vase',
            rank: 2,
            notes: 'Neutral finish, tall silhouette.',
            priceLabel: '\$96',
            priority: 'Medium',
            status: 'Considering',
            imageUrl: 'https://picsum.photos/seed/decor-vase/900/700',
            createdAt: now.subtract(const Duration(days: 5)),
          ),
          WishlistItem(
            id: 'decor-throw',
            title: 'Brushed wool throw',
            rank: 3,
            notes: 'Textural layer for the reading chair.',
            priceLabel: '\$74',
            priority: 'Low',
            status: 'Saved',
            imageUrl: 'https://picsum.photos/seed/decor-throw/900/700',
            createdAt: now.subtract(const Duration(days: 4)),
          ),
        ],
      ),
      Wishlist(
        id: 'tech-gear',
        ownerUserId: ownerUserId,
        title: 'Tech Gear 2024',
        description:
            'Portable tools and desk upgrades for daily work and travel.',
        year: 2024,
        coverImageUrl: 'https://picsum.photos/seed/tech-gear/1200/800',
        createdAt: now.subtract(const Duration(days: 60)),
        updatedAt: now.subtract(const Duration(days: 1)),
        items: [
          WishlistItem(
            id: 'tech-keyboard',
            title: 'Low-profile keyboard',
            rank: 1,
            notes: 'Quiet switches and compact layout.',
            priceLabel: '\$129',
            priority: 'High',
            status: 'Considering',
            imageUrl: 'https://picsum.photos/seed/tech-keyboard/900/700',
            createdAt: now.subtract(const Duration(days: 10)),
          ),
          WishlistItem(
            id: 'tech-monitor-light',
            title: 'Monitor light bar',
            rank: 2,
            notes: 'For late-night desk work.',
            priceLabel: '\$89',
            priority: 'Medium',
            status: 'Saved',
            imageUrl: 'https://picsum.photos/seed/tech-monitor-light/900/700',
            createdAt: now.subtract(const Duration(days: 8)),
          ),
        ],
      ),
      Wishlist(
        id: 'shared-weekend',
        ownerUserId: ownerUserId,
        title: 'Weekend Hosting',
        description:
            'A collaborative list for pieces we both want before the next dinner party.',
        year: 2026,
        coverImageUrl: 'https://picsum.photos/seed/shared-weekend/1200/800',
        createdAt: now.subtract(const Duration(days: 14)),
        updatedAt: now.subtract(const Duration(hours: 6)),
        isShared: true,
        sharedUsers: const [
          SharedUser(
            id: 'user-maya',
            name: 'Maya',
            email: 'maya@example.com',
            role: 'Owner',
          ),
          SharedUser(
            id: 'user-dan',
            name: 'Dan',
            email: 'dan@example.com',
            role: 'Editor',
          ),
        ],
        items: [
          WishlistItem(
            id: 'hosting-plates',
            title: 'Set of dinner plates',
            rank: 1,
            notes: 'Matte finish, set of six.',
            priceLabel: '\$148',
            priority: 'High',
            status: 'Saved',
            imageUrl: 'https://picsum.photos/seed/hosting-plates/900/700',
            createdAt: now.subtract(const Duration(days: 3)),
          ),
          WishlistItem(
            id: 'hosting-candles',
            title: 'Taper candle pair',
            rank: 2,
            notes: 'For the dining setup.',
            priceLabel: '\$28',
            priority: 'Low',
            status: 'Purchased',
            imageUrl: 'https://picsum.photos/seed/hosting-candles/900/700',
            purchasedAt: now.subtract(const Duration(days: 1)),
            createdAt: now.subtract(const Duration(days: 2)),
          ),
        ],
      ),
      Wishlist(
        id: 'archived-registry',
        ownerUserId: ownerUserId,
        title: 'Summer Registry',
        description: 'An older collection we have already wrapped up.',
        year: 2025,
        coverImageUrl: 'https://picsum.photos/seed/archived-registry/1200/800',
        createdAt: now.subtract(const Duration(days: 180)),
        updatedAt: now.subtract(const Duration(days: 30)),
        items: [
          WishlistItem(
            id: 'registry-tray',
            title: 'Walnut serving tray',
            rank: 1,
            notes: 'Already purchased.',
            priceLabel: '\$112',
            priority: 'Medium',
            status: 'Purchased',
            imageUrl: 'https://picsum.photos/seed/registry-tray/900/700',
            purchasedAt: now.subtract(const Duration(days: 80)),
            createdAt: now.subtract(const Duration(days: 90)),
          ),
        ],
      ),
    ];
  }
}
