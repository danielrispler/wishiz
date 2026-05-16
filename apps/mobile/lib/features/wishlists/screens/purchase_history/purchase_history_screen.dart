import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/utils/error_utils.dart';
import 'package:wishiz/shared/widgets/wishiz_app_bar.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

typedef _Entry = ({WishlistItem item, String wishlistTitle, String wishlistId});

class PurchaseHistoryScreen extends StatefulWidget {
  const PurchaseHistoryScreen({
    super.key,
    required this.repository,
    this.onWishlistTap,
  });

  final WishlistRepository repository;
  final Future<void> Function(String wishlistId)? onWishlistTap;

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  late final ValueListenable<List<Wishlist>> _wishlistsListenable;
  final Set<String> _loadingItemIds = {};

  @override
  void initState() {
    super.initState();
    _wishlistsListenable = widget.repository.watchWishlists();
  }

  List<_Entry> _buildEntries(List<Wishlist> wishlists) {
    final entries = <_Entry>[];
    for (final wishlist in wishlists) {
      if (wishlist.isArchived) continue;
      for (final item in wishlist.purchasedItems) {
        entries.add((
          item: item,
          wishlistTitle: wishlist.title,
          wishlistId: wishlist.id,
        ));
      }
    }
    entries.sort((a, b) {
      final aDate = a.item.purchasedAt ?? a.item.createdAt;
      final bDate = b.item.purchasedAt ?? b.item.createdAt;
      return bDate.compareTo(aDate);
    });
    return entries;
  }

  Map<String, List<_Entry>> _groupByMonth(List<_Entry> entries) {
    final map = <String, List<_Entry>>{};

    for (final entry in entries) {
      final date = entry.item.purchasedAt ?? entry.item.createdAt;
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      (map[key] ??= []).add(entry);
    }
    return map;
  }

  String _monthLabel(String key, int count) {
    final parts = key.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final itemWord = count == 1 ? 'item' : 'items';
    return '${months[month]} $year · $count $itemWord';
  }

  String _formatDate(DateTime date) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now();
    final label = '${months[date.month]} ${date.day}';
    return date.year == now.year ? label : '$label ${date.year}';
  }

  Future<void> _unpurchase(_Entry entry) async {
    final itemId = entry.item.id;
    setState(() => _loadingItemIds.add(itemId));
    try {
      await widget.repository.updateWishlistItemStatus(
        wishlistId: entry.wishlistId,
        itemId: itemId,
        status: WishlistItemStatus.saved,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              formatErrorMessage(
                error,
                fallbackMessage: 'Could not restore item.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _loadingItemIds.remove(itemId));
    }
  }

  Widget _buildThumbnail(BuildContext context, WishlistItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;

    Widget child;
    if (hasImage) {
      final uri = Uri.tryParse(item.imageUrl!);
      final isRemote =
          uri != null &&
          (uri.scheme == 'http' ||
              uri.scheme == 'https' ||
              uri.scheme == 'blob' ||
              uri.scheme == 'data');
      final fallback = Container(
        color: colorScheme.surfaceContainerHigh,
        alignment: Alignment.center,
        child: Icon(
          Icons.image_outlined,
          color: colorScheme.onSurfaceVariant,
          size: 18,
        ),
      );
      child = kIsWeb || isRemote
          ? Image.network(
              item.imageUrl!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => fallback,
            )
          : Image.file(
              File(item.imageUrl!),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => fallback,
            );
    } else {
      child = Center(
        child: Icon(
          Icons.shopping_bag_outlined,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          size: 22,
        ),
      );
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surfaceContainerHigh,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildEntryTile(BuildContext context, _Entry entry) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isLoading = _loadingItemIds.contains(entry.item.id);
    final date = entry.item.purchasedAt ?? entry.item.createdAt;

    return GestureDetector(
      onTap: widget.onWishlistTap != null
          ? () => widget.onWishlistTap!(entry.wishlistId)
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.itemGap),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        padding: const EdgeInsets.all(AppConstants.cardPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildThumbnail(context, entry.item),
            const SizedBox(width: AppConstants.spacing3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.item.title,
                    style: textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.wishlistTitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.item.priceLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.item.priceLabel!,
                      style: textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppConstants.spacing2),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatDate(date),
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: isLoading
                      ? Padding(
                          padding: const EdgeInsets.all(6),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      : IconButton(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Mark as active',
                          icon: Icon(
                            Icons.undo_outlined,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          onPressed: () => _unpurchase(entry),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppConstants.spacing5,
        bottom: AppConstants.spacing2,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No purchases yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppConstants.spacing2),
          Text(
            'Mark items as purchased in any list to see them here.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WishizAppBar(titleText: 'Purchase History'),
      body: SafeArea(
        child: ValueListenableBuilder<List<Wishlist>>(
          valueListenable: _wishlistsListenable,
          builder: (context, wishlists, _) {
            final entries = _buildEntries(wishlists);
            final grouped = _groupByMonth(entries);

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.pagePadding,
                AppConstants.spacing4,
                AppConstants.pagePadding,
                120,
              ),
              children: [
                if (entries.isEmpty)
                  _buildEmptyState(context)
                else
                  for (final group in grouped.entries) ...[
                    _buildMonthHeader(
                      context,
                      _monthLabel(group.key, group.value.length),
                    ),
                    for (final entry in group.value)
                      _buildEntryTile(context, entry),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}
