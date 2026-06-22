import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:wishiz/features/discover/models/product.dart';
import 'trending_item_card.dart';

class ProductCarousel extends StatelessWidget {
  const ProductCarousel({
    super.key,
    required this.products,
    required this.onToggleSave,
    this.onProductTap,
    this.height = 296,
  });

  final List<Product> products;
  final void Function(Product product, bool isSaved) onToggleSave;
  final void Function(Product product)? onProductTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollCacheExtent: const ScrollCacheExtent.pixels(520),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = products[i];
          return RepaintBoundary(
            key: ValueKey(p.id),
            child: TrendingItemCard(
              product: p,
              onTap: onProductTap == null ? null : () => onProductTap!(p),
              onToggleSave: (isSaved) => onToggleSave(p, isSaved),
            ),
          );
        },
      ),
    );
  }
}
