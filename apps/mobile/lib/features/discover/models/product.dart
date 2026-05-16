class Product {
  final String id;
  final String title;
  final String brand;
  final String imageUrl;
  final double priceUsd;
  final int saves;
  final bool isSavedByUser;

  const Product({
    required this.id,
    required this.title,
    required this.brand,
    required this.imageUrl,
    required this.priceUsd,
    required this.saves,
    this.isSavedByUser = false,
  });

  Product copyWith({bool? isSavedByUser, int? saves}) => Product(
        id: id,
        title: title,
        brand: brand,
        imageUrl: imageUrl,
        priceUsd: priceUsd,
        saves: saves ?? this.saves,
        isSavedByUser: isSavedByUser ?? this.isSavedByUser,
      );

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        title: json['title'] as String,
        brand: json['brand'] as String,
        imageUrl: json['image_url'] as String,
        priceUsd: (json['price_usd'] as num).toDouble(),
        saves: json['saves'] as int? ?? 0,
        isSavedByUser: json['is_saved_by_user'] as bool? ?? false,
      );

  // TODO: replace with fetch from Go/Postgres backend
  static List<Product> sample = [
    Product(
      id: 'p_1',
      title: 'Aquazzura ivory slingback',
      brand: 'NET—A—PORTER',
      imageUrl: 'https://picsum.photos/seed/slingback/400/500',
      priceUsd: 795,
      saves: 2100,
    ),
    Product(
      id: 'p_2',
      title: 'Wave-cut silk slip',
      brand: 'REFORMATION',
      imageUrl: 'https://picsum.photos/seed/slip/400/500',
      priceUsd: 320,
      saves: 1400,
      isSavedByUser: true,
    ),
    Product(
      id: 'p_3',
      title: 'Tonal cashmere knit',
      brand: 'KHAITE',
      imageUrl: 'https://picsum.photos/seed/cashmere/400/500',
      priceUsd: 890,
      saves: 1100,
    ),
    Product(
      id: 'p_4',
      title: 'Sculpted gold cuff',
      brand: 'MISSOMA',
      imageUrl: 'https://picsum.photos/seed/cuff/400/500',
      priceUsd: 210,
      saves: 980,
    ),
    Product(
      id: 'p_5',
      title: 'Pearl-drop earring',
      brand: 'SOPHIE BUHAI',
      imageUrl: 'https://picsum.photos/seed/pearl/400/500',
      priceUsd: 340,
      saves: 612,
    ),
    Product(
      id: 'p_6',
      title: 'Diptyque Do Son EDP',
      brand: 'DIPTYQUE',
      imageUrl: 'https://picsum.photos/seed/diptyque/400/500',
      priceUsd: 190,
      saves: 2400,
    ),
    Product(
      id: 'p_7',
      title: 'Quilted leather mini',
      brand: 'POLÈNE',
      imageUrl: 'https://picsum.photos/seed/polene/400/500',
      priceUsd: 420,
      saves: 1800,
    ),
    Product(
      id: 'p_8',
      title: 'Linen wide-leg trouser',
      brand: 'TOTÊME',
      imageUrl: 'https://picsum.photos/seed/toteme/400/500',
      priceUsd: 380,
      saves: 744,
    ),
  ];
}
