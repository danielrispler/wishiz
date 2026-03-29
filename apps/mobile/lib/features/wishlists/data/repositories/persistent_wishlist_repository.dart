import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wishiz/features/wishlists/data/repositories/in_memory_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/data/storage/wishlist_storage.dart';
import 'package:wishiz/features/wishlists/data/storage/wishlist_storage_codec.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

class PersistentWishlistRepository implements WishlistRepository {
  PersistentWishlistRepository._({
    required WishlistStorage storage,
    required InMemoryWishlistRepository repository,
    WishlistStorageCodec codec = const WishlistStorageCodec(),
  })  : _storage = storage,
        _repository = repository,
        _codec = codec;

  final WishlistStorage _storage;
  final InMemoryWishlistRepository _repository;
  final WishlistStorageCodec _codec;

  Future<void> _pendingWrite = Future.value();

  static Future<PersistentWishlistRepository> create({
    required WishlistStorage storage,
    WishlistStorageCodec codec = const WishlistStorageCodec(),
  }) async {
    final source = await storage.read();
    final shouldPersistInitialState = source == null || source.trim().isEmpty;
    final initialWishlists = _decodeInitialWishlists(
      source: source,
      codec: codec,
    );

    final repository = PersistentWishlistRepository._(
      storage: storage,
      repository:
          InMemoryWishlistRepository(initialWishlists: initialWishlists),
      codec: codec,
    );

    if (shouldPersistInitialState) {
      repository._persist();
      await repository.flush();
    }

    return repository;
  }

  static List<Wishlist> _decodeInitialWishlists({
    required String? source,
    required WishlistStorageCodec codec,
  }) {
    if (source == null || source.trim().isEmpty) {
      return InMemoryWishlistRepository.seedWishlists();
    }

    try {
      return codec.decode(source);
    } on FormatException {
      return InMemoryWishlistRepository.seedWishlists();
    }
  }

  Future<void> flush() => _pendingWrite;

  Future<T> _persistAndReturn<T>(T value) async {
    _persist();
    await _pendingWrite;
    return value;
  }

  void _persist() {
    final snapshot = _codec.encode(_repository.getWishlists());
    _pendingWrite = _pendingWrite.then((_) => _storage.write(snapshot));
    unawaited(_pendingWrite);
  }

  @override
  ValueListenable<List<Wishlist>> watchWishlists() =>
      _repository.watchWishlists();

  @override
  List<Wishlist> getWishlists() => _repository.getWishlists();

  @override
  Wishlist? findById(String id) => _repository.findById(id);

  @override
  Future<Wishlist> createWishlist({
    required String title,
    required String description,
    required int year,
    String? coverImageUrl,
    bool isShared = false,
  }) async {
    final wishlist = await _repository.createWishlist(
      title: title,
      description: description,
      year: year,
      coverImageUrl: coverImageUrl,
      isShared: isShared,
    );
    return _persistAndReturn(wishlist);
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
    final wishlist = await _repository.updateWishlist(
      id: id,
      title: title,
      description: description,
      year: year,
      coverImageUrl: coverImageUrl,
      isShared: isShared,
    );
    if (wishlist != null) {
      return _persistAndReturn(wishlist);
    }
    return wishlist;
  }

  @override
  Future<Wishlist?> archiveWishlist(String id) async {
    final wishlist = await _repository.archiveWishlist(id);
    if (wishlist != null) {
      return _persistAndReturn(wishlist);
    }
    return wishlist;
  }

  @override
  Future<Wishlist?> restoreWishlist(String id) async {
    final wishlist = await _repository.restoreWishlist(id);
    if (wishlist != null) {
      return _persistAndReturn(wishlist);
    }
    return wishlist;
  }

  @override
  Future<bool> deleteWishlist(String id) async {
    final wasDeleted = await _repository.deleteWishlist(id);
    if (wasDeleted) {
      return _persistAndReturn(true);
    }
    return wasDeleted;
  }

  @override
  Future<Wishlist?> addSharedUser({
    required String wishlistId,
    required String name,
    required String email,
    required String role,
  }) async {
    final wishlist = await _repository.addSharedUser(
      wishlistId: wishlistId,
      name: name,
      email: email,
      role: role,
    );
    if (wishlist != null) {
      return _persistAndReturn(wishlist);
    }
    return wishlist;
  }

  @override
  Future<bool> removeSharedUser({
    required String wishlistId,
    required String userId,
  }) async {
    final wasRemoved = await _repository.removeSharedUser(
      wishlistId: wishlistId,
      userId: userId,
    );
    if (wasRemoved) {
      return _persistAndReturn(true);
    }
    return wasRemoved;
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
    final item = await _repository.addWishlistItem(
      wishlistId: wishlistId,
      title: title,
      notes: notes,
      priceLabel: priceLabel,
      priority: priority,
      status: status,
      imageUrl: imageUrl,
      productUrl: productUrl,
    );
    return _persistAndReturn(item);
  }

  @override
  Future<Wishlist?> reorderWishlistItems({
    required String wishlistId,
    required List<String> orderedItemIds,
  }) async {
    final wishlist = await _repository.reorderWishlistItems(
      wishlistId: wishlistId,
      orderedItemIds: orderedItemIds,
    );
    if (wishlist != null) {
      return _persistAndReturn(wishlist);
    }
    return wishlist;
  }

  @override
  Future<WishlistItem?> updateWishlistItemStatus({
    required String wishlistId,
    required String itemId,
    required String status,
  }) async {
    final item = await _repository.updateWishlistItemStatus(
      wishlistId: wishlistId,
      itemId: itemId,
      status: status,
    );
    if (item != null) {
      return _persistAndReturn(item);
    }
    return item;
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
    final item = await _repository.updateWishlistItem(
      wishlistId: wishlistId,
      itemId: itemId,
      title: title,
      notes: notes,
      priceLabel: priceLabel,
      priority: priority,
      status: status,
      imageUrl: imageUrl,
      productUrl: productUrl,
    );
    if (item != null) {
      return _persistAndReturn(item);
    }
    return item;
  }

  @override
  Future<bool> deleteWishlistItem({
    required String wishlistId,
    required String itemId,
  }) async {
    final wasDeleted = await _repository.deleteWishlistItem(
      wishlistId: wishlistId,
      itemId: itemId,
    );
    if (wasDeleted) {
      return _persistAndReturn(true);
    }
    return wasDeleted;
  }
}
