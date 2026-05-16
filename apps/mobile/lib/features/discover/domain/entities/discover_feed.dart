import 'package:wishiz/features/discover/models/product.dart';
import 'package:wishiz/features/discover/models/starter_pack.dart';

class DiscoverFeed {
  const DiscoverFeed({
    required this.starterPacks,
    required this.trending,
    required this.forYou,
  });

  final List<StarterPack> starterPacks;
  final List<Product> trending;
  final List<Product> forYou;
}
