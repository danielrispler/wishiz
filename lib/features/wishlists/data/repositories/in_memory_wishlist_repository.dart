import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_user.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

class InMemoryWishlistRepository implements WishlistRepository {
  InMemoryWishlistRepository({List<Wishlist>? initialWishlists})
    : _wishlists = ValueNotifier<List<Wishlist>>(
        List<Wishlist>.unmodifiable(initialWishlists ?? seedWishlists()),
      );

  static final InMemoryWishlistRepository instance = InMemoryWishlistRepository();
  static final Uuid _uuid = Uuid();

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
  Wishlist createWishlist({
    required String title,
    required String description,
    String? coverImageUrl,
    bool isShared = false,
  }) {
    final now = DateTime.now();
    final wishlist = Wishlist(
      id: _uuid.v4(),
      title: title,
      description: description,
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
  Wishlist? updateWishlist({
    required String id,
    required String title,
    required String description,
    String? coverImageUrl,
    bool? isShared,
  }) {
    return _replaceWishlist(
      id,
      (wishlist) => wishlist.copyWith(
        title: title,
        description: description,
        coverImageUrl: coverImageUrl,
        isShared: isShared ?? wishlist.isShared,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Wishlist? archiveWishlist(String id) {
    return _replaceWishlist(
      id,
      (wishlist) => wishlist.copyWith(
        isArchived: true,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Wishlist? restoreWishlist(String id) {
    return _replaceWishlist(
      id,
      (wishlist) => wishlist.copyWith(
        isArchived: false,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  bool deleteWishlist(String id) {
    final previousLength = _wishlists.value.length;
    _wishlists.value = List<Wishlist>.unmodifiable(
      _wishlists.value.where((wishlist) => wishlist.id != id),
    );
    return previousLength != _wishlists.value.length;
  }

  @override
  Wishlist? addSharedUser({
    required String wishlistId,
    required String name,
    required String email,
    required String role,
  }) {
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
  bool removeSharedUser({
    required String wishlistId,
    required String userId,
  }) {
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
  WishlistItem addWishlistItem({
    required String wishlistId,
    required String title,
    String? notes,
    String? priceLabel,
    String priority = 'Medium',
    String status = 'Saved',
    String? imageUrl,
    String? productUrl,
  }) {
    final now = DateTime.now();
    final item = WishlistItem(
      id: _uuid.v4(),
      title: title,
      notes: notes,
      priceLabel: priceLabel,
      priority: priority,
      status: status,
      imageUrl: imageUrl,
      productUrl: productUrl,
      createdAt: now,
    );

    final updatedWishlist = _replaceWishlist(
      wishlistId,
      (wishlist) => wishlist.copyWith(
        items: [item, ...wishlist.items],
        updatedAt: now,
      ),
    );

    if (updatedWishlist == null) {
      throw StateError('Wishlist "$wishlistId" was not found.');
    }

    return item;
  }

  @override
  WishlistItem? updateWishlistItem({
    required String wishlistId,
    required String itemId,
    required String title,
    String? notes,
    String? priceLabel,
    String priority = 'Medium',
    String status = 'Saved',
    String? imageUrl,
    String? productUrl,
  }) {
    WishlistItem? updatedItem;
    var didUpdate = false;

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
          );
          didUpdate = true;
          return updatedItem!;
        }).toList(growable: false);

        return wishlist.copyWith(
          items: nextItems,
          updatedAt: didUpdate ? DateTime.now() : wishlist.updatedAt,
        );
      },
    );

    if (updatedWishlist == null || !didUpdate) {
      return null;
    }

    return updatedItem;
  }

  @override
  bool deleteWishlistItem({
    required String wishlistId,
    required String itemId,
  }) {
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

  static List<Wishlist> seedWishlists() {
    final now = DateTime.now();

    return [
      Wishlist(
        id: 'home-decor',
        title: 'Home Decor',
        description: 'Soft lighting, sculptural objects, and pieces for a calmer living room.',
        coverImageUrl: 'https://picsum.photos/seed/home-decor/1200/800',
        createdAt: now.subtract(const Duration(days: 21)),
        updatedAt: now.subtract(const Duration(days: 2)),
        items: [
          WishlistItem(
            id: 'decor-lamp',
            title: 'Marble table lamp',
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
        title: 'Tech Gear 2024',
        description: 'Portable tools and desk upgrades for daily work and travel.',
        coverImageUrl: 'https://picsum.photos/seed/tech-gear/1200/800',
        createdAt: now.subtract(const Duration(days: 60)),
        updatedAt: now.subtract(const Duration(days: 1)),
        items: [
          WishlistItem(
            id: 'tech-keyboard',
            title: 'Low-profile keyboard',
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
        title: 'Weekend Hosting',
        description: 'A collaborative list for pieces we both want before the next dinner party.',
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
            notes: 'For the dining setup.',
            priceLabel: '\$28',
            priority: 'Low',
            status: 'Purchased',
            imageUrl: 'https://picsum.photos/seed/hosting-candles/900/700',
            createdAt: now.subtract(const Duration(days: 2)),
          ),
        ],
      ),
      Wishlist(
        id: 'archived-registry',
        title: 'Summer Registry',
        description: 'An older collection we have already wrapped up.',
        coverImageUrl: 'https://picsum.photos/seed/archived-registry/1200/800',
        createdAt: now.subtract(const Duration(days: 180)),
        updatedAt: now.subtract(const Duration(days: 30)),
        isArchived: true,
        items: [
          WishlistItem(
            id: 'registry-tray',
            title: 'Walnut serving tray',
            notes: 'Already purchased.',
            priceLabel: '\$112',
            priority: 'Medium',
            status: 'Purchased',
            imageUrl: 'https://picsum.photos/seed/registry-tray/900/700',
            createdAt: now.subtract(const Duration(days: 90)),
          ),
        ],
      ),
    ];
  }
}
