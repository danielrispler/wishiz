import 'package:flutter/foundation.dart';
import 'package:wishiz/features/wishlists/data/api/wishlist_api_client.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

class HttpWishlistRepository implements WishlistRepository {
  HttpWishlistRepository._({
    required WishlistApiClient apiClient,
    required String currentUserId,
  }) : _apiClient = apiClient,
       _currentUserId = currentUserId;

  static Future<HttpWishlistRepository> create({
    required WishlistApiClient apiClient,
    required String currentUserId,
  }) async {
    final repository = HttpWishlistRepository._(
      apiClient: apiClient,
      currentUserId: currentUserId,
    );
    await repository.refresh();
    return repository;
  }

  final WishlistApiClient _apiClient;
  final String _currentUserId;
  final ValueNotifier<List<Wishlist>> _wishlists =
      ValueNotifier<List<Wishlist>>(const []);

  Future<void> refresh() async {
    final wishlists = await _apiClient.listWishlists();
    _wishlists.value = List<Wishlist>.unmodifiable(
      wishlists
          .map(
            (wishlist) =>
                wishlist.toEntity(fallbackOwnerUserId: _currentUserId),
          )
          .toList(growable: false),
    );
  }

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
  Future<Wishlist?> joinWishlist(String id) async {
    final joined = await _apiClient.joinWishlist(id);
    final wishlist = joined.toEntity(fallbackOwnerUserId: _currentUserId);
    _replaceWishlist(wishlist);
    return wishlist;
  }

  @override
  Future<Wishlist> createWishlist({
    required String title,
    required String description,
    required int year,
    String? coverImageUrl,
    bool isShared = false,
  }) async {
    final created = await _apiClient.createWishlist(
      title: title,
      description: description,
      year: year,
      coverImageUrl: coverImageUrl,
      isShared: isShared,
    );

    final wishlist = created.toEntity(fallbackOwnerUserId: _currentUserId);
    _wishlists.value = List<Wishlist>.unmodifiable([
      wishlist,
      ..._wishlists.value.where((entry) => entry.id != wishlist.id),
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
    final updated = await _apiClient.updateWishlist(
      id: id,
      title: title,
      description: description,
      year: year,
      coverImageUrl: coverImageUrl,
      isShared: isShared ?? findById(id)?.isShared ?? false,
    );

    final wishlist = updated.toEntity(fallbackOwnerUserId: _currentUserId);
    _replaceWishlist(wishlist);
    return wishlist;
  }

  @override
  Future<Wishlist?> archiveWishlist(String id) async {
    final updated = await _apiClient.archiveWishlist(id);
    final wishlist = updated.toEntity(fallbackOwnerUserId: _currentUserId);
    _replaceWishlist(wishlist);
    return wishlist;
  }

  @override
  Future<Wishlist?> restoreWishlist(String id) async {
    final updated = await _apiClient.restoreWishlist(id);
    final wishlist = updated.toEntity(fallbackOwnerUserId: _currentUserId);
    _replaceWishlist(wishlist);
    return wishlist;
  }

  @override
  Future<bool> deleteWishlist(String id) async {
    await _apiClient.deleteWishlist(id);
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
    await _apiClient.addSharedUser(
      wishlistId: wishlistId,
      name: name,
      email: email,
      role: role,
    );

    return _refreshWishlist(wishlistId);
  }

  @override
  Future<bool> removeSharedUser({
    required String wishlistId,
    required String userId,
  }) async {
    await _apiClient.removeSharedUser(wishlistId: wishlistId, userId: userId);

    await _refreshWishlist(wishlistId);
    return true;
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
    final createdItem = await _apiClient.addWishlistItem(
      wishlistId: wishlistId,
      title: title,
      notes: notes,
      priceLabel: priceLabel,
      priority: priority,
      status: status,
      imageUrl: imageUrl,
      productUrl: productUrl,
    );

    final updatedWishlist = _patchWishlist(
      wishlistId,
      (wishlist) => wishlist.copyWith(
        items: [...wishlist.items, createdItem.toEntity()],
        updatedAt: createdItem.updatedAt,
      ),
    );
    if (updatedWishlist == null) {
      throw StateError('Wishlist "$wishlistId" was not found.');
    }

    return _findWishlistItem(
      wishlist: updatedWishlist,
      itemId: createdItem.id,
      notFoundMessage:
          'Wishlist item "${createdItem.id}" was created but not added to the local cache.',
    );
  }

  @override
  Future<Wishlist?> reorderWishlistItems({
    required String wishlistId,
    required List<String> orderedItemIds,
  }) async {
    final updated = await _apiClient.reorderWishlistItems(
      wishlistId: wishlistId,
      orderedItemIds: orderedItemIds,
    );

    final wishlist = updated.toEntity(fallbackOwnerUserId: _currentUserId);
    _replaceWishlist(wishlist);
    return wishlist;
  }

  @override
  Future<WishlistItem?> updateWishlistItemStatus({
    required String wishlistId,
    required String itemId,
    required String status,
  }) async {
    final updatedItem = await _apiClient.updateWishlistItem(
      wishlistId: wishlistId,
      itemId: itemId,
      body: {'status': status},
    );

    final updatedWishlist = _patchWishlist(
      wishlistId,
      (wishlist) => wishlist.copyWith(
        items: wishlist.items
            .map((item) => item.id == itemId ? updatedItem.toEntity() : item)
            .toList(growable: false),
        updatedAt: updatedItem.updatedAt,
      ),
    );
    if (updatedWishlist == null) {
      return null;
    }

    return _findWishlistItem(
      wishlist: updatedWishlist,
      itemId: updatedItem.id,
      notFoundMessage:
          'Wishlist item "${updatedItem.id}" was updated but not written to the local cache.',
    );
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
    final updatedItem = await _apiClient.updateWishlistItem(
      wishlistId: wishlistId,
      itemId: itemId,
      body: {
        'title': title,
        'notes': notes,
        'priceLabel': priceLabel,
        'priority': priority,
        'status': status,
        'imageUrl': imageUrl,
        'productUrl': productUrl,
      },
    );

    final updatedWishlist = _patchWishlist(
      wishlistId,
      (wishlist) => wishlist.copyWith(
        items: wishlist.items
            .map((item) => item.id == itemId ? updatedItem.toEntity() : item)
            .toList(growable: false),
        updatedAt: updatedItem.updatedAt,
      ),
    );
    if (updatedWishlist == null) {
      return null;
    }

    return _findWishlistItem(
      wishlist: updatedWishlist,
      itemId: updatedItem.id,
      notFoundMessage:
          'Wishlist item "${updatedItem.id}" was updated but not written to the local cache.',
    );
  }

  @override
  Future<bool> deleteWishlistItem({
    required String wishlistId,
    required String itemId,
  }) async {
    await _apiClient.deleteWishlistItem(wishlistId: wishlistId, itemId: itemId);

    final updatedWishlist = _patchWishlist(
      wishlistId,
      (wishlist) => wishlist.copyWith(
        items: wishlist.items
            .where((item) => item.id != itemId)
            .toList(growable: false),
        updatedAt: DateTime.now(),
      ),
    );
    return updatedWishlist != null;
  }

  Future<Wishlist> _refreshWishlist(String wishlistId) async {
    final refreshed = await _apiClient.getWishlist(wishlistId);
    final wishlist = refreshed.toEntity(fallbackOwnerUserId: _currentUserId);
    _replaceWishlist(wishlist);
    return wishlist;
  }

  WishlistItem _findWishlistItem({
    required Wishlist wishlist,
    required String itemId,
    required String notFoundMessage,
  }) {
    for (final item in wishlist.items) {
      if (item.id == itemId) {
        return item;
      }
    }

    throw StateError(notFoundMessage);
  }

  void _replaceWishlist(Wishlist wishlist) {
    final nextWishlists = _wishlists.value
        .map((existing) {
          if (existing.id != wishlist.id) {
            return existing;
          }

          return wishlist;
        })
        .toList(growable: false);

    final wasPresent = nextWishlists.any((entry) => entry.id == wishlist.id);
    _wishlists.value = List<Wishlist>.unmodifiable(
      wasPresent ? nextWishlists : [...nextWishlists, wishlist],
    );
  }

  Wishlist? _patchWishlist(
    String wishlistId,
    Wishlist Function(Wishlist wishlist) update,
  ) {
    Wishlist? updatedWishlist;
    final nextWishlists = _wishlists.value
        .map((wishlist) {
          if (wishlist.id != wishlistId) {
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
}
