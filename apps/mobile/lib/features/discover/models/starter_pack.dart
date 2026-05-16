import 'product.dart';

class StarterPack {
  final String id;
  final String title;
  final String subtitle;
  final String coverImageUrl;
  final int itemCount;
  final double totalPriceUsd;
  final String? tag;
  final List<Product> previewItems;

  const StarterPack({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverImageUrl,
    required this.itemCount,
    required this.totalPriceUsd,
    required this.previewItems,
    this.tag,
  });

  factory StarterPack.fromJson(Map<String, dynamic> json) => StarterPack(
        id: json['id'] as String,
        title: json['title'] as String,
        subtitle: json['subtitle'] as String? ?? '',
        coverImageUrl: json['cover_image_url'] as String,
        itemCount: json['item_count'] as int,
        totalPriceUsd: (json['total_price_usd'] as num).toDouble(),
        tag: json['tag'] as String?,
        previewItems: (json['preview_items'] as List<dynamic>? ?? [])
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  // TODO: replace with fetch from Go/Postgres backend
  static List<StarterPack> sample = [
    StarterPack(
      id: 'pack_summer_wardrobe',
      title: 'Summer Wardrobe',
      subtitle: '14 essentials · linen, gold, salt',
      coverImageUrl: 'https://picsum.photos/seed/summer/600/700',
      itemCount: 14,
      totalPriceUsd: 2140,
      tag: "Editor's pick",
      previewItems: Product.sample.take(4).toList(),
    ),
    StarterPack(
      id: 'pack_evening_skincare',
      title: 'Evening Skincare',
      subtitle: '9 holy-grail steps',
      coverImageUrl: 'https://picsum.photos/seed/skincare/600/700',
      itemCount: 9,
      totalPriceUsd: 680,
      previewItems: Product.sample.skip(1).take(4).toList(),
    ),
    StarterPack(
      id: 'pack_quiet_apartment',
      title: 'The Quiet Apartment',
      subtitle: 'Tonal pieces for slow rooms',
      coverImageUrl: 'https://picsum.photos/seed/apartment/600/700',
      itemCount: 22,
      totalPriceUsd: 5400,
      previewItems: Product.sample.skip(2).take(4).toList(),
    ),
    StarterPack(
      id: 'pack_bridal_glow',
      title: 'Bridal Glow Kit',
      subtitle: 'From morning-of to after-party',
      coverImageUrl: 'https://picsum.photos/seed/bridal/600/700',
      itemCount: 18,
      totalPriceUsd: 1920,
      previewItems: Product.sample.take(4).toList(),
    ),
  ];
}
