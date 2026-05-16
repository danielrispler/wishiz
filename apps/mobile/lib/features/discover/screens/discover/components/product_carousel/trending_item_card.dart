import 'package:flutter/material.dart';
import 'package:wishiz/core/theme/app_colors.dart';
import 'package:wishiz/features/discover/models/product.dart';
import 'package:wishiz/shared/widgets/wishiz_image.dart';
import 'save_button.dart';

class TrendingItemCard extends StatelessWidget {
  const TrendingItemCard({
    super.key,
    required this.product,
    required this.onToggleSave,
    this.onTap,
  });

  final Product product;
  final ValueChanged<bool> onToggleSave;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 158,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 196 + 14,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    bottom: 14,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: WishizNetworkImage(
                        imageUrl: product.imageUrl,
                        width: 158,
                        height: 196,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(16),
                        measurementLabel: 'discover.trending_card',
                        errorChild: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFEEE4FF), Color(0xFF8E7AD8)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _SaveCountChip(saves: product.saveCount),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 10,
                    child: SaveButton(
                      isSaved: product.isSavedByUser,
                      onToggle: onToggleSave,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              product.brand,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              product.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
                height: 1.25,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveCountChip extends StatelessWidget {
  const _SaveCountChip({required this.saves});
  final int saves;

  String _format(int n) {
    if (n >= 1000) {
      final v = n / 1000;
      return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}k';
    }
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.favorite_rounded,
            size: 10,
            color: AppColors.primary,
          ),
          const SizedBox(width: 4),
          Text(
            _format(saves),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
