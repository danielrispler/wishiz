import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/shared/widgets/wishlist_analytics_sheet.dart';
import 'wishlist_detail_chips.dart';

String _formatRelativeDate(DateTime updatedAt) {
  final difference = DateTime.now().difference(updatedAt);
  if (difference.inDays >= 2) return '${difference.inDays} days ago';
  if (difference.inDays == 1) return 'yesterday';
  if (difference.inHours >= 1) return '${difference.inHours}h ago';
  if (difference.inMinutes >= 1) return '${difference.inMinutes}m ago';
  return 'just now';
}

class WishlistHeader extends StatelessWidget {
  const WishlistHeader({super.key, required this.wishlist});

  final Wishlist wishlist;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasImage = wishlist.coverImageUrl != null && wishlist.coverImageUrl!.isNotEmpty;
    final analytics = WishlistAnalytics(wishlist);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (hasImage) ...[
                _SmallLogo(context: context, imageUrl: wishlist.coverImageUrl!),
                const SizedBox(width: AppConstants.spacing4),
              ] else ...[
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.list_alt_rounded, color: colorScheme.primary, size: 28),
                ),
                const SizedBox(width: AppConstants.spacing4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wishlist.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (wishlist.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        wishlist.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacing4),
          Wrap(
            spacing: AppConstants.spacing2,
            runSpacing: AppConstants.spacing2,
            children: [
              WishlistMetadataChip(label: '${wishlist.year}', icon: Icons.calendar_today_outlined),
              WishlistMetadataChip(label: '${wishlist.activeItemCount} active', icon: Icons.checklist_rtl_rounded),
              WishlistMetadataChip(label: '${wishlist.purchasedItemCount} purchased', icon: Icons.shopping_bag_outlined),
              WishlistMetadataChip(label: 'Updated ${_formatRelativeDate(wishlist.updatedAt)}', icon: Icons.update_rounded),
              if (analytics.totalActiveValue != null)
                WishlistMetadataChip(label: analytics.totalActiveValue!, icon: Icons.attach_money_rounded),
              if (analytics.avgDaysOnList != null)
                WishlistMetadataChip(label: 'avg ${analytics.avgDaysOnList!.round()}d on list', icon: Icons.hourglass_top_rounded),
              if (analytics.completionRate != null)
                WishlistMetadataChip(label: '${(analytics.completionRate! * 100).round()}% gifted', icon: Icons.celebration_outlined),
              WishlistTapMetadataChip(
                label: 'Analytics',
                icon: Icons.bar_chart_rounded,
                onTap: () => showWishlistAnalyticsSheet(context, wishlist),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallLogo extends StatelessWidget {
  const _SmallLogo({required this.context, required this.imageUrl});

  final BuildContext context;
  final String imageUrl;

  @override
  Widget build(BuildContext buildContext) {
    final colorScheme = Theme.of(buildContext).colorScheme;
    final uri = Uri.tryParse(imageUrl);
    final isRemote = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'blob' || uri.scheme == 'data');
    final fallback = Container(
      color: colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: colorScheme.onSurfaceVariant),
    );

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: kIsWeb || isRemote
            ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback)
            : Image.file(File(imageUrl), fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}
