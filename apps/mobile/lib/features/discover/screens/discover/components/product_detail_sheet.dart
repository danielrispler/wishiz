import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wishiz/core/theme/app_colors.dart';
import 'package:wishiz/features/discover/models/product.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/shared/widgets/wishiz_image.dart';

class ProductDetailSheet extends StatefulWidget {
  const ProductDetailSheet({
    super.key,
    required this.product,
    required this.onAddToList,
    required this.onRemove,
    this.onGoToList,
    this.savedToWishlist,
  });

  final Product product;

  /// Shows wishlist picker and saves; returns true on success.
  final Future<bool> Function() onAddToList;

  /// Removes product from saved list.
  final Future<void> Function() onRemove;

  /// Navigate to the Lists tab.
  final VoidCallback? onGoToList;

  /// If known, which wishlist the product was saved to.
  final Wishlist? savedToWishlist;

  @override
  State<ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurfaceVariant,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ProductDetailSheetState extends State<ProductDetailSheet> {
  late bool _isSaved;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isSaved = widget.product.isSavedByUser;
  }

  String _fmt(int n) {
    if (n >= 1000) {
      final v = n / 1000;
      return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}k';
    }
    return '$n';
  }

  Future<void> _handleAdd() async {
    setState(() => _isLoading = true);
    final success = await widget.onAddToList();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (success) _isSaved = true;
    });
  }

  Future<void> _handleRemove() async {
    setState(() => _isLoading = true);
    await widget.onRemove();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isSaved = false;
    });
  }

  Future<void> _handleViewOnSite() async {
    final url = widget.product.productUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final hasUrl = p.productUrl?.isNotEmpty ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SizedBox(
            height: 260,
            width: double.infinity,
            child: WishizNetworkImage(
              imageUrl: p.imageUrl,
              height: 260,
              fit: BoxFit.cover,
              measurementLabel: 'discover.detail_sheet',
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.favorite_rounded,
                          size: 11,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_fmt(p.saveCount)} saves',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    p.brand,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                p.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                  letterSpacing: -0.4,
                  height: 1.15,
                ),
              ),
              if (p.priceLabel?.isNotEmpty ?? false) ...[
                const SizedBox(height: 6),
                Text(
                  p.priceLabel!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
              if ((p.productType?.isNotEmpty ?? false) ||
                  p.category.isNotEmpty ||
                  (p.gender?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: [
                    if (p.productType?.isNotEmpty ?? false)
                      _MetaChip(label: p.productType!),
                    if (p.category.isNotEmpty)
                      _MetaChip(label: p.category),
                    if (p.gender?.isNotEmpty ?? false)
                      _MetaChip(label: p.gender!),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              if (_isSaved) ...[
                if (widget.onGoToList != null)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onGoToList!();
                      },
                      icon: const Icon(Icons.bookmark_rounded, size: 18),
                      label: Text(
                        widget.savedToWishlist != null
                            ? 'Go to "${widget.savedToWishlist!.title}"'
                            : 'Go to your list',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _handleRemove,
                    icon: const Icon(
                      Icons.remove_circle_outline_rounded,
                      size: 18,
                    ),
                    label: const Text('Remove from list'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _handleAdd,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Add to list'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
              if (hasUrl) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _handleViewOnSite,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('View on site'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom),
      ],
    );
  }
}
