class Product {
  final String id;
  final String title;
  final String brand;
  final String category;
  final String imageUrl;
  final String? productUrl;
  final int saveCount;
  final bool isSavedByUser;
  final String? priceLabel;
  final String? gender;
  final String? productType;
  final String? savedItemId;
  final String? savedWishlistId;

  const Product({
    required this.id,
    required this.title,
    required this.brand,
    required this.category,
    required this.imageUrl,
    required this.saveCount,
    this.productUrl,
    this.isSavedByUser = false,
    this.priceLabel,
    this.gender,
    this.productType,
    this.savedItemId,
    this.savedWishlistId,
  });

  Product copyWith({
    bool? isSavedByUser,
    int? saveCount,
    String? priceLabel,
    String? gender,
    String? productType,
  }) => Product(
    id: id,
    title: title,
    brand: brand,
    category: category,
    imageUrl: imageUrl,
    productUrl: productUrl,
    saveCount: saveCount ?? this.saveCount,
    isSavedByUser: isSavedByUser ?? this.isSavedByUser,
    priceLabel: priceLabel ?? this.priceLabel,
    gender: gender ?? this.gender,
    productType: productType ?? this.productType,
    savedItemId: savedItemId,
    savedWishlistId: savedWishlistId,
  );

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    title: json['title'] as String,
    brand: json['brand'] as String,
    category: json['category'] as String? ?? '',
    imageUrl: json['imageUrl'] as String,
    productUrl: json['productUrl'] as String?,
    saveCount: json['saveCount'] as int? ?? 0,
    isSavedByUser: json['savedByUser'] as bool? ?? false,
    priceLabel: json['priceLabel'] as String?,
    gender: json['gender'] as String?,
    productType: json['productType'] as String?,
    savedItemId: json['savedItemId'] as String?,
    savedWishlistId: json['savedWishlistId'] as String?,
  );

  static List<Product> sample = [
    const Product(
      id: 'p_1',
      title: 'Aquazzura ivory slingback',
      brand: 'NET—A—PORTER',
      category: 'fashion',
      imageUrl: 'https://picsum.photos/seed/slingback/400/500',
      saveCount: 2100,
    ),
    const Product(
      id: 'p_2',
      title: 'Wave-cut silk slip',
      brand: 'REFORMATION',
      category: 'fashion',
      imageUrl: 'https://picsum.photos/seed/slip/400/500',
      saveCount: 1400,
      isSavedByUser: true,
    ),
    const Product(
      id: 'p_3',
      title: 'Tonal cashmere knit',
      brand: 'KHAITE',
      category: 'fashion',
      imageUrl: 'https://picsum.photos/seed/cashmere/400/500',
      saveCount: 1100,
    ),
    const Product(
      id: 'p_4',
      title: 'Sculpted gold cuff',
      brand: 'MISSOMA',
      category: 'accessories',
      imageUrl: 'https://picsum.photos/seed/cuff/400/500',
      saveCount: 980,
    ),
    const Product(
      id: 'p_5',
      title: 'Pearl-drop earring',
      brand: 'SOPHIE BUHAI',
      category: 'accessories',
      imageUrl: 'https://picsum.photos/seed/pearl/400/500',
      saveCount: 612,
    ),
    const Product(
      id: 'p_6',
      title: 'Diptyque Do Son EDP',
      brand: 'DIPTYQUE',
      category: 'beauty',
      imageUrl: 'https://picsum.photos/seed/diptyque/400/500',
      saveCount: 2400,
    ),
    const Product(
      id: 'p_7',
      title: 'Quilted leather mini',
      brand: 'POLÈNE',
      category: 'accessories',
      imageUrl: 'https://picsum.photos/seed/polene/400/500',
      saveCount: 1800,
    ),
    const Product(
      id: 'p_8',
      title: 'Linen wide-leg trouser',
      brand: 'TOTÊME',
      category: 'fashion',
      imageUrl: 'https://picsum.photos/seed/toteme/400/500',
      saveCount: 744,
    ),
  ];
}
