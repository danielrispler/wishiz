import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:wishiz/features/wishlists/data/api/wishlist_api_client.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_user.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

class HttpWishlistRepository implements WishlistRepository {
  HttpWishlistRepository._({
    required WishlistApiClient apiClient,
  }) : _apiClient = apiClient;

  static const Uuid _uuid = Uuid();

  static Future<HttpWishlistRepository> create({
    required WishlistApiClient apiClient,
  }) async {
    final repository = HttpWishlistRepository._(apiClient: apiClient);
    await repository.refresh();
    return repository;
  }

  final WishlistApiClient _apiClient;
  final ValueNotifier<List<Wishlist>> _wishlists =
      ValueNotifier<List<Wishlist>>(const []);

  Future<void> refresh() async {
    final wishlists = await _apiClient.listWishlists();
    _wishlists.value = List<Wishlist>.unmodifiable(
      wishlists.map((wishlist) => wishlist.toEntity()).toList(growable: false),
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

    final wishlist = created.toEntity();
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

    final wishlist = updated.toEntity();
    _replaceWishlist(wishlist);
    return wishlist;
  }

  @override
  Future<Wishlist?> archiveWishlist(String id) async {
    final updated = await _apiClient.archiveWishlist(id);
    final wishlist = updated.toEntity();
    _replaceWishlist(wishlist);
    return wishlist;
  }

  @override
  Future<Wishlist?> restoreWishlist(String id) async {
    final updated = await _apiClient.restoreWishlist(id);
    final wishlist = updated.toEntity();
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
    final wishlist = findById(wishlistId);
    if (wishlist == null) {
      return null;
    }

    final normalizedEmail = email.toLowerCase();
    final alreadyExists = wishlist.sharedUsers.any(
      (user) => user.email.toLowerCase() == normalizedEmail,
    );
    if (alreadyExists) {
      return wishlist;
    }

    // Collaborator routes do not exist in the Go backend yet, so we keep this
    // as a temporary in-memory behavior to avoid a wider UI rewrite in this step.
    final updatedWishlist = wishlist.copyWith(
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

    _replaceWishlist(updatedWishlist);
    return updatedWishlist;
  }

  @override
  Future<bool> removeSharedUser({
    required String wishlistId,
    required String userId,
  }) async {
    final wishlist = findById(wishlistId);
    if (wishlist == null) {
      return false;
    }

    final nextUsers = wishlist.sharedUsers
        .where((user) => user.id != userId)
        .toList(growable: false);
    final wasRemoved = nextUsers.length != wishlist.sharedUsers.length;
    if (!wasRemoved) {
      return false;
    }

    _replaceWishlist(
      wishlist.copyWith(
        isShared: nextUsers.isNotEmpty,
        sharedUsers: nextUsers,
        updatedAt: DateTime.now(),
      ),
    );
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

    final wishlist = await _refreshWishlist(wishlistId);
    return _findWishlistItem(
      wishlist: wishlist,
      itemId: createdItem.id,
      notFoundMessage:
          'Wishlist item "${createdItem.id}" was created but not returned by the refreshed wishlist.',
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

    final wishlist = updated.toEntity();
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
      body: {
        'status': status,
      },
    );

    final wishlist = await _refreshWishlist(wishlistId);
    return _findWishlistItem(
      wishlist: wishlist,
      itemId: updatedItem.id,
      notFoundMessage:
          'Wishlist item "${updatedItem.id}" was updated but not returned by the refreshed wishlist.',
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

    final wishlist = await _refreshWishlist(wishlistId);
    return _findWishlistItem(
      wishlist: wishlist,
      itemId: updatedItem.id,
      notFoundMessage:
          'Wishlist item "${updatedItem.id}" was updated but not returned by the refreshed wishlist.',
    );
  }

  @override
  Future<bool> deleteWishlistItem({
    required String wishlistId,
    required String itemId,
  }) async {
    await _apiClient.deleteWishlistItem(
      wishlistId: wishlistId,
      itemId: itemId,
    );

    await _refreshWishlist(wishlistId);
    return true;
  }

  Future<Wishlist> _refreshWishlist(String wishlistId) async {
    final refreshed = await _apiClient.getWishlist(wishlistId);
    final wishlist = refreshed.toEntity();
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
    final nextWishlists = _wishlists.value.map((existing) {
      if (existing.id != wishlist.id) {
        return existing;
      }

      return wishlist;
    }).toList(growable: false);

    final wasPresent = nextWishlists.any((entry) => entry.id == wishlist.id);
    _wishlists.value = List<Wishlist>.unmodifiable(
      wasPresent ? nextWishlists : [...nextWishlists, wishlist],
    );
  }
}
