import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'wishlist_detail_chips.dart';

class WishlistItemCard extends StatefulWidget {
  const WishlistItemCard({
    super.key,
    required this.item,
    required this.displayedPriceLabel,
    required this.canEdit,
    required this.showDragHandle,
    this.dragIndex,
    required this.onSwipeTogglePurchased,
    required this.onSwipeDelete,
    required this.onEdit,
    required this.onShare,
    this.onOpenLink,
  });

  final WishlistItem item;
  final String? displayedPriceLabel;
  final bool canEdit;
  final bool showDragHandle;
  final int? dragIndex;
  final Future<void> Function() onSwipeTogglePurchased;
  final Future<bool> Function() onSwipeDelete;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback? onOpenLink;

  @override
  State<WishlistItemCard> createState() => _WishlistItemCardState();
}

class _WishlistItemCardState extends State<WishlistItemCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.itemGap),
      child: Dismissible(
        key: ValueKey('dismiss-${widget.item.id}'),
        direction: widget.canEdit ? DismissDirection.horizontal : DismissDirection.none,
        background: _SwipeBackground(
          color: widget.item.status == WishlistItemStatus.purchased
              ? Colors.blue.shade600
              : Colors.green.shade600,
          alignment: Alignment.centerLeft,
          icon: widget.item.status == WishlistItemStatus.purchased
              ? Icons.restore_outlined
              : Icons.check_circle_outline,
          label: widget.item.status == WishlistItemStatus.purchased ? 'Restore' : 'Purchased',
        ),
        secondaryBackground: const _SwipeBackground(
          color: Colors.red,
          alignment: Alignment.centerRight,
          icon: Icons.delete_outline,
          label: 'Delete',
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            await widget.onSwipeTogglePurchased();
            return false;
          }
          return widget.onSwipeDelete();
        },
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.cardPadding,
                      vertical: AppConstants.spacing3,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 84),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (widget.showDragHandle && widget.dragIndex != null)
                            ReorderableDragStartListener(
                              index: widget.dragIndex!,
                              child: Padding(
                                padding: const EdgeInsets.only(right: AppConstants.spacing2),
                                child: Icon(
                                  Icons.drag_indicator,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          _ItemThumbnail(item: widget.item),
                          const SizedBox(width: AppConstants.spacing3),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.item.title,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.2),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 20,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: widget.displayedPriceLabel == null
                                        ? const SizedBox.shrink()
                                        : Text(
                                            widget.displayedPriceLabel!,
                                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                              color: Theme.of(context).colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppConstants.spacing2),
                          WishlistMetadataChip(label: '#${widget.item.rank}'),
                          const SizedBox(width: AppConstants.spacing2),
                          Icon(
                            _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                            size: 20,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.cardPadding, 0, AppConstants.cardPadding, AppConstants.spacing3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.item.notes != null && widget.item.notes!.isNotEmpty) ...[
                        Text(
                          widget.item.notes!,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppConstants.spacing4),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          WishlistMetadataChip(label: 'Rank #${widget.item.rank}'),
                          WishlistMetadataChip(
                            key: ValueKey('days-on-list-${widget.item.id}'),
                            label: '${widget.item.daysOnList} day${widget.item.daysOnList == 1 ? '' : 's'} on list',
                          ),
                        ],
                      ),
                      const SizedBox(height: AppConstants.spacing4),
                      Row(
                        children: [
                          _ActionButton(
                            onPressed: widget.onShare,
                            icon: Icons.share_outlined,
                            label: 'Share',
                          ),
                          if (widget.canEdit) ...[
                            const SizedBox(width: AppConstants.spacing2),
                            _ActionButton(
                              onPressed: widget.onEdit,
                              icon: Icons.edit_outlined,
                              label: 'Edit',
                            ),
                          ],
                          if (widget.onOpenLink != null) ...[
                            const SizedBox(width: AppConstants.spacing2),
                            _ActionButton(
                              onPressed: widget.onOpenLink!,
                              icon: Icons.open_in_new_outlined,
                              label: 'Open',
                              isPrimary: true,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 180),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemThumbnail extends StatelessWidget {
  const _ItemThumbnail({required this.item});

  final WishlistItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageUrl = item.imageUrl;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surfaceContainerHigh,
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null && imageUrl.isNotEmpty
          ? _ItemImage(imageUrl: imageUrl)
          : Icon(Icons.shopping_bag_outlined, color: colorScheme.onSurfaceVariant.withOpacity(0.7), size: 22),
    );
  }
}

class _ItemImage extends StatelessWidget {
  const _ItemImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(imageUrl);
    final isRemote = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'blob' || uri.scheme == 'data');
    final fallback = Container(
      color: colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: colorScheme.onSurfaceVariant),
    );

    final image = kIsWeb || isRemote
        ? Image.network(imageUrl, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => fallback)
        : Image.file(File(imageUrl), fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => fallback);

    return InkWell(
      onTap: () => _openImageViewer(context, imageUrl, isRemote),
      borderRadius: BorderRadius.circular(AppConstants.radiusXl - 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusXl - 8),
        child: AspectRatio(aspectRatio: 1, child: image),
      ),
    );
  }

  Future<void> _openImageViewer(BuildContext context, String source, bool isRemote) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            SafeArea(
              child: Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: kIsWeb || isRemote
                      ? Image.network(source, fit: BoxFit.contain)
                      : Image.file(File(source), fit: BoxFit.contain),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.alignment,
    required this.icon,
    required this.label,
  });

  final Color color;
  final Alignment alignment;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppConstants.radiusXl)),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacing4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: alignment == Alignment.centerLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.isPrimary = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isPrimary ? colorScheme.primary : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isPrimary ? colorScheme.onPrimary : colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: isPrimary ? colorScheme.onPrimary : colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
