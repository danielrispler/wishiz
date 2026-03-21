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
  }) : _storage = storage,
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
      repository: InMemoryWishlistRepository(initialWishlists: initialWishlists),
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

  void _persist() {
    final snapshot = _codec.encode(_repository.getWishlists());
    _pendingWrite = _pendingWrite.then((_) => _storage.write(snapshot));
    unawaited(_pendingWrite);
  }

  @override
  ValueListenable<List<Wishlist>> watchWishlists() => _repository.watchWishlists();

  @override
  List<Wishlist> getWishlists() => _repository.getWishlists();

  @override
  Wishlist? findById(String id) => _repository.findById(id);

  @override
  Wishlist createWishlist({
    required String title,
    required String description,
    String? coverImageUrl,
    bool isShared = false,
  }) {
    final wishlist = _repository.createWishlist(
      title: title,
      description: description,
      coverImageUrl: coverImageUrl,
      isShared: isShared,
    );
    _persist();
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
    final wishlist = _repository.updateWishlist(
      id: id,
      title: title,
      description: description,
      coverImageUrl: coverImageUrl,
      isShared: isShared,
    );
    if (wishlist != null) {
      _persist();
    }
    return wishlist;
  }

  @override
  Wishlist? archiveWishlist(String id) {
    final wishlist = _repository.archiveWishlist(id);
    if (wishlist != null) {
      _persist();
    }
    return wishlist;
  }

  @override
  Wishlist? restoreWishlist(String id) {
    final wishlist = _repository.restoreWishlist(id);
    if (wishlist != null) {
      _persist();
    }
    return wishlist;
  }

  @override
  bool deleteWishlist(String id) {
    final wasDeleted = _repository.deleteWishlist(id);
    if (wasDeleted) {
      _persist();
    }
    return wasDeleted;
  }

  @override
  Wishlist? addSharedUser({
    required String wishlistId,
    required String name,
    required String email,
    required String role,
  }) {
    final wishlist = _repository.addSharedUser(
      wishlistId: wishlistId,
      name: name,
      email: email,
      role: role,
    );
    if (wishlist != null) {
      _persist();
    }
    return wishlist;
  }

  @override
  bool removeSharedUser({
    required String wishlistId,
    required String userId,
  }) {
    final wasRemoved = _repository.removeSharedUser(
      wishlistId: wishlistId,
      userId: userId,
    );
    if (wasRemoved) {
      _persist();
    }
    return wasRemoved;
  }

  @override
  WishlistItem addWishlistItem({
    required String wishlistId,
    required String title,
    String? notes,
    String? priceLabel,
    String? imageUrl,
    String? productUrl,
  }) {
    final item = _repository.addWishlistItem(
      wishlistId: wishlistId,
      title: title,
      notes: notes,
      priceLabel: priceLabel,
      imageUrl: imageUrl,
      productUrl: productUrl,
    );
    _persist();
    return item;
  }

  @override
  WishlistItem? updateWishlistItem({
    required String wishlistId,
    required String itemId,
    required String title,
    String? notes,
    String? priceLabel,
    String? imageUrl,
    String? productUrl,
  }) {
    final item = _repository.updateWishlistItem(
      wishlistId: wishlistId,
      itemId: itemId,
      title: title,
      notes: notes,
      priceLabel: priceLabel,
      imageUrl: imageUrl,
      productUrl: productUrl,
    );
    if (item != null) {
      _persist();
    }
    return item;
  }

  @override
  bool deleteWishlistItem({
    required String wishlistId,
    required String itemId,
  }) {
    final wasDeleted = _repository.deleteWishlistItem(
      wishlistId: wishlistId,
      itemId: itemId,
    );
    if (wasDeleted) {
      _persist();
    }
    return wasDeleted;
  }
}
