import 'package:wishiz/features/discover/data/api/discover_api_client.dart';
import 'package:wishiz/features/discover/domain/entities/discover_feed.dart';
import 'package:wishiz/features/discover/domain/repositories/discover_repository.dart';
import 'package:wishiz/features/discover/models/product.dart';
import 'package:wishiz/features/discover/models/starter_pack.dart';

class ApiDiscoverRepository implements DiscoverRepository {
  ApiDiscoverRepository({required DiscoverApiClient apiClient})
      : _apiClient = apiClient;

  final DiscoverApiClient _apiClient;

  @override
  Future<DiscoverFeed> getFeed() async {
    final json = await _apiClient.getFeed();
    return DiscoverFeed(
      starterPacks: (json['starterPacks'] as List<dynamic>)
          .map((e) => StarterPack.fromJson(e as Map<String, dynamic>))
          .toList(),
      trending: (json['trending'] as List<dynamic>)
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList(),
      forYou: (json['forYou'] as List<dynamic>)
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<({bool saved, int saveCount})> toggleSave(String productId) async {
    final json = await _apiClient.toggleSave(productId);
    return (
      saved: json['saved'] as bool,
      saveCount: json['saveCount'] as int,
    );
  }

  @override
  Future<void> grabStarterPack(String packId, String wishlistId) async {
    await _apiClient.grabStarterPack(packId: packId, wishlistId: wishlistId);
  }
}
