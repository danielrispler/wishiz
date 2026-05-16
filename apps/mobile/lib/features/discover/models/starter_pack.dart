import 'product.dart';

class StarterPack {
  final String id;
  final String title;
  final String subtitle;
  final String coverImageUrl;
  final int itemCount;
  final String? tag;
  final List<String> previewItems;
  final List<Product> items;

  const StarterPack({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverImageUrl,
    required this.itemCount,
    required this.previewItems,
    required this.items,
    this.tag,
  });

  factory StarterPack.fromJson(Map<String, dynamic> json) => StarterPack(
        id: json['id'] as String,
        title: json['title'] as String,
        subtitle: json['subtitle'] as String? ?? '',
        coverImageUrl: json['coverImageUrl'] as String,
        itemCount: json['itemCount'] as int? ?? 0,
        tag: json['tag'] as String?,
        previewItems:
            (json['previewItems'] as List<dynamic>?)?.cast<String>() ?? const [],
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static List<StarterPack> sample = [
    StarterPack(
      id: 'pack_summer_wardrobe',
      title: 'Summer Wardrobe',
      subtitle: '14 essentials · linen, gold, salt',
      coverImageUrl: 'https://picsum.photos/seed/summer/600/700',
      itemCount: 14,
      tag: "Editor's pick",
      previewItems: Product.sample.take(3).map((p) => p.imageUrl).toList(),
      items: Product.sample.take(4).toList(),
    ),
    StarterPack(
      id: 'pack_evening_skincare',
      title: 'Evening Skincare',
      subtitle: '9 holy-grail steps',
      coverImageUrl: 'https://picsum.photos/seed/skincare/600/700',
      itemCount: 9,
      previewItems: Product.sample.skip(1).take(3).map((p) => p.imageUrl).toList(),
      items: Product.sample.skip(1).take(4).toList(),
    ),
    StarterPack(
      id: 'pack_quiet_apartment',
      title: 'The Quiet Apartment',
      subtitle: 'Tonal pieces for slow rooms',
      coverImageUrl: 'https://picsum.photos/seed/apartment/600/700',
      itemCount: 22,
      previewItems: Product.sample.skip(2).take(3).map((p) => p.imageUrl).toList(),
      items: Product.sample.skip(2).take(4).toList(),
    ),
    StarterPack(
      id: 'pack_bridal_glow',
      title: 'Bridal Glow Kit',
      subtitle: 'From morning-of to after-party',
      coverImageUrl: 'https://picsum.photos/seed/bridal/600/700',
      itemCount: 18,
      previewItems: Product.sample.take(3).map((p) => p.imageUrl).toList(),
      items: Product.sample.take(4).toList(),
    ),
  ];
}
