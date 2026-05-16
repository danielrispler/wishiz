import 'package:wishiz/features/discover/domain/entities/discover_feed.dart';

abstract class DiscoverRepository {
  Future<DiscoverFeed> getFeed();

  Future<({bool saved, int saveCount})> toggleSave(String productId);

  Future<void> grabStarterPack(String packId, String wishlistId);
}
