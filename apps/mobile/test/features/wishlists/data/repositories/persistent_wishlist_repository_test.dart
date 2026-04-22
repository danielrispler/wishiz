import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/data/repositories/persistent_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/data/storage/wishlist_storage.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';

void main() {
  const ownerUserId = 'user-dana';

  group('PersistentWishlistRepository', () {
    test(
      'starts empty on first launch and persists an empty snapshot',
      () async {
        final storage = _FakeWishlistStorage();

        final repository = await PersistentWishlistRepository.create(
          storage: storage,
          ownerUserId: ownerUserId,
        );

        expect(repository.getWishlists(), isEmpty);
        expect(storage.value, '[]');
      },
    );

    test('reloads saved wishlists and ranked items from storage', () async {
      final storage = _FakeWishlistStorage();
      final repository = await PersistentWishlistRepository.create(
        storage: storage,
        ownerUserId: ownerUserId,
      );

      final wishlist = await repository.createWishlist(
        title: 'Travel',
        description: 'Carry-on upgrades and essentials.',
        year: 2027,
        coverImageUrl: 'https://example.com/travel.jpg',
      );
      await repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Weekender bag',
        priority: WishlistItemPriority.high,
        status: WishlistItemStatus.considering,
        imageUrl: 'https://example.com/bag.jpg',
        productUrl: 'https://example.com/bag',
      );
      await repository.flush();

      final reloadedRepository = await PersistentWishlistRepository.create(
        storage: storage,
        ownerUserId: ownerUserId,
      );
      final reloadedWishlist = reloadedRepository.findById(wishlist.id);

      expect(reloadedWishlist, isNotNull);
      expect(reloadedWishlist?.ownerUserId, ownerUserId);
      expect(reloadedWishlist?.year, 2027);
      expect(reloadedWishlist?.coverImageUrl, 'https://example.com/travel.jpg');
      expect(reloadedWishlist?.items, hasLength(1));
      expect(reloadedWishlist?.items.first.title, 'Weekender bag');
      expect(reloadedWishlist?.items.first.rank, 1);
      expect(reloadedWishlist?.items.first.priority, WishlistItemPriority.high);
      expect(
        reloadedWishlist?.items.first.status,
        WishlistItemStatus.considering,
      );
      expect(
        reloadedWishlist?.items.first.imageUrl,
        'https://example.com/bag.jpg',
      );
      expect(
        reloadedWishlist?.items.first.productUrl,
        'https://example.com/bag',
      );
    });

    test('reloads invites from storage', () async {
      final storage = _FakeWishlistStorage();
      final repository = await PersistentWishlistRepository.create(
        storage: storage,
        ownerUserId: ownerUserId,
      );

      final wishlist = await repository.createWishlist(
        title: 'Dinner Party',
        description: 'Plates, flowers, and candles.',
        year: 2026,
      );
      await repository.createInvite(
        wishlistId: wishlist.id,
        email: 'maya@example.com',
        role: WishlistMemberRole.editor,
      );
      await repository.flush();

      final reloadedRepository = await PersistentWishlistRepository.create(
        storage: storage,
        ownerUserId: ownerUserId,
      );
      final reloadedWishlist = reloadedRepository.findById(wishlist.id);

      expect(reloadedWishlist?.ownerUserId, ownerUserId);
      expect(reloadedWishlist?.invites, hasLength(1));
      expect(reloadedWishlist?.invites.first.email, 'maya@example.com');
      expect(reloadedWishlist?.invites.first.role, WishlistMemberRole.editor);
    });

    test(
      'resolves mutation futures only after persistence completes',
      () async {
        final storage = _FakeWishlistStorage();
        final repository = await PersistentWishlistRepository.create(
          storage: storage,
          ownerUserId: ownerUserId,
        );

        final writeCompleter = Completer<void>();
        storage.nextWriteCompleter = writeCompleter;

        var didComplete = false;
        final createFuture = repository
            .createWishlist(
              title: 'Slow Save',
              description: 'Wait for disk before completing.',
              year: 2026,
            )
            .then((_) {
              didComplete = true;
            });

        expect(
          repository.getWishlists().any(
            (wishlist) => wishlist.title == 'Slow Save',
          ),
          isTrue,
        );

        await Future<void>.delayed(Duration.zero);
        expect(didComplete, isFalse);

        writeCompleter.complete();
        await createFuture;
        expect(didComplete, isTrue);
      },
    );

    test('replaces invalid stored data with an empty snapshot', () async {
      final storage = _FakeWishlistStorage()..value = '{"invalid":true}';

      final repository = await PersistentWishlistRepository.create(
        storage: storage,
        ownerUserId: ownerUserId,
      );

      expect(repository.getWishlists(), isEmpty);
      expect(storage.value, '[]');
    });
  });
}

class _FakeWishlistStorage implements WishlistStorage {
  String? value;
  Completer<void>? nextWriteCompleter;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String nextValue) async {
    value = nextValue;
    final completer = nextWriteCompleter;
    if (completer != null) {
      nextWriteCompleter = null;
      await completer.future;
    }
  }
}
