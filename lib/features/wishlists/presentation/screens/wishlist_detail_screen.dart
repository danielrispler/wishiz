import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_editor_screen.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_item_editor_screen.dart';

class WishlistDetailScreen extends StatelessWidget {
  const WishlistDetailScreen({
    super.key,
    required this.repository,
    required this.wishlistId,
  });

  final WishlistRepository repository;
  final String wishlistId;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Wishlist>>(
      valueListenable: repository.watchWishlists(),
      builder: (context, _, __) {
        final wishlist = repository.findById(wishlistId);

        if (wishlist == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Text(
                'This list no longer exists.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('List Details'),
            actions: [
              IconButton(
                tooltip: 'Edit list',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WishlistEditorScreen(
                        repository: repository,
                        wishlist: wishlist,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.edit_outlined),
              ),
              PopupMenuButton<_WishlistAction>(
                onSelected: (action) async {
                  if (action == _WishlistAction.archive) {
                    repository.archiveWishlist(wishlist.id);
                    return;
                  }

                  if (action == _WishlistAction.restore) {
                    repository.restoreWishlist(wishlist.id);
                    return;
                  }

                  final shouldDelete = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete list?'),
                      content: const Text(
                        'This removes the list from the current app session.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );

                  if (shouldDelete == true) {
                    repository.deleteWishlist(wishlist.id);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  }
                },
                itemBuilder: (context) {
                  if (wishlist.isArchived) {
                    return const [
                      PopupMenuItem(
                        value: _WishlistAction.restore,
                        child: Text('Restore list'),
                      ),
                      PopupMenuItem(
                        value: _WishlistAction.delete,
                        child: Text('Delete list'),
                      ),
                    ];
                  }

                  return const [
                    PopupMenuItem(
                      value: _WishlistAction.archive,
                      child: Text('Archive list'),
                    ),
                    PopupMenuItem(
                      value: _WishlistAction.delete,
                      child: Text('Delete list'),
                    ),
                  ];
                },
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppConstants.spacing4),
              children: [
                _buildHeroCard(context, wishlist),
                const SizedBox(height: AppConstants.spacing6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Items',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    if (!wishlist.isArchived)
                      TextButton.icon(
                        onPressed: () => _openItemEditor(
                          context,
                          wishlistId: wishlist.id,
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Item'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  wishlist.isArchived
                      ? 'Archived lists stay readable here. Restore the list to change its items.'
                      : wishlist.items.isEmpty
                          ? 'This list is ready for its first item.'
                          : 'Capture, refine, and remove items directly from this collection.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppConstants.spacing4),
                if (wishlist.items.isEmpty)
                  _buildEmptyItemsState(context, wishlist)
                else
                  ...wishlist.items.map(
                    (item) => _buildItemCard(context, wishlist, item),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeroCard(BuildContext context, Wishlist wishlist) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wishlist.coverImageUrl != null &&
              wishlist.coverImageUrl!.isNotEmpty) ...[
            _buildNetworkImage(
              context,
              imageUrl: wishlist.coverImageUrl!,
              aspectRatio: 16 / 9,
            ),
            const SizedBox(height: AppConstants.spacing4),
          ],
          Text(
            wishlist.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            wishlist.description.isEmpty
                ? 'No description yet.'
                : wishlist.description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppConstants.spacing4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMetadataChip(
                context,
                label: '${wishlist.itemCount} items',
              ),
              _buildMetadataChip(
                context,
                label: wishlist.isArchived ? 'Archived' : 'Active',
              ),
              if (wishlist.isShared)
                _buildMetadataChip(context, label: 'Shared'),
              _buildMetadataChip(
                context,
                label: 'Updated ${_formatRelativeDate(wishlist.updatedAt)}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataChip(
    BuildContext context, {
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing3,
        vertical: 10,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }

  Future<void> _openItemEditor(
    BuildContext context, {
    required String wishlistId,
    WishlistItem? item,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WishlistItemEditorScreen(
          repository: repository,
          wishlistId: wishlistId,
          item: item,
        ),
      ),
    );
  }

  Widget _buildEmptyItemsState(BuildContext context, Wishlist wishlist) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            wishlist.isArchived
                ? 'No items were saved in this archived list.'
                : 'No items yet. Start the collection with the first saved piece.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (!wishlist.isArchived) ...[
            const SizedBox(height: AppConstants.spacing4),
            TextButton.icon(
              onPressed: () => _openItemEditor(
                context,
                wishlistId: wishlist.id,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add First Item'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemCard(
    BuildContext context,
    Wishlist wishlist,
    WishlistItem item,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacing3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
            _buildNetworkImage(
              context,
              imageUrl: item.imageUrl!,
              aspectRatio: 4 / 3,
            ),
            const SizedBox(height: AppConstants.spacing4),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (!wishlist.isArchived)
                PopupMenuButton<_WishlistItemAction>(
                  onSelected: (action) async {
                    if (action == _WishlistItemAction.edit) {
                      await _openItemEditor(
                        context,
                        wishlistId: wishlist.id,
                        item: item,
                      );
                      return;
                    }

                    final shouldDelete = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete item?'),
                        content: Text(
                          'Remove "${item.title}" from this list?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );

                    if (shouldDelete == true) {
                      repository.deleteWishlistItem(
                        wishlistId: wishlist.id,
                        itemId: item.id,
                      );
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _WishlistItemAction.edit,
                      child: Text('Edit item'),
                    ),
                    PopupMenuItem(
                      value: _WishlistItemAction.delete,
                      child: Text('Delete item'),
                    ),
                  ],
                ),
            ],
          ),
          if (item.notes != null && item.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.notes!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (item.priceLabel != null && item.priceLabel!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.priceLabel!,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
          if (item.productUrl != null && item.productUrl!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.productUrl!,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNetworkImage(
    BuildContext context, {
    required String imageUrl,
    required double aspectRatio,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXl - 8),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: colorScheme.surfaceContainerHigh,
              alignment: Alignment.center,
              child: Icon(
                Icons.image_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatRelativeDate(DateTime updatedAt) {
    final difference = DateTime.now().difference(updatedAt);

    if (difference.inDays >= 2) {
      return '${difference.inDays} days ago';
    }
    if (difference.inDays == 1) {
      return 'yesterday';
    }
    if (difference.inHours >= 1) {
      return '${difference.inHours}h ago';
    }
    if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m ago';
    }
    return 'just now';
  }
}

enum _WishlistAction {
  archive,
  restore,
  delete,
}

enum _WishlistItemAction {
  edit,
  delete,
}
