import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/utils/currency_utils.dart';
import 'package:wishiz/core/utils/error_utils.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_user.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_editor_screen.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_item_editor_screen.dart';

class WishlistDetailScreen extends StatefulWidget {
  const WishlistDetailScreen({
    super.key,
    required this.repository,
    required this.authRepository,
    required this.wishlistId,
    this.showPurchasedOnly = false,
  });

  final WishlistRepository repository;
  final AuthRepository authRepository;
  final String wishlistId;
  final bool showPurchasedOnly;

  @override
  State<WishlistDetailScreen> createState() => _WishlistDetailScreenState();
}

class _WishlistDetailScreenState extends State<WishlistDetailScreen> {
  static const String _allFilter = 'All';
  static const String _sortHighestRank = 'Highest Rank';
  static const String _sortLowestRank = 'Lowest Rank';
  static const String _sortNewestAdded = 'Newest Added';

  String _selectedStatus = _allFilter;
  String _selectedPriority = _allFilter;
  String _selectedSort = _sortHighestRank;

  void _showError(Object error, {required String fallbackMessage}) {
    _showFeedback(
      context,
      formatErrorMessage(
        error,
        fallbackMessage: fallbackMessage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: widget.authRepository.watchCurrentUser(),
      builder: (context, currentUser, __) {
        return ValueListenableBuilder<List<Wishlist>>(
          valueListenable: widget.repository.watchWishlists(),
          builder: (context, _, __) {
            final wishlist = widget.repository.findById(widget.wishlistId);

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

            final sourceItems = widget.showPurchasedOnly
                ? wishlist.purchasedItems
                : wishlist.activeItems;
            final visibleItems = _applyFilters(sourceItems);
            final canReorder = !widget.showPurchasedOnly &&
                _selectedStatus == _allFilter &&
                _selectedPriority == _allFilter &&
                _selectedSort == _sortHighestRank &&
                visibleItems.length > 1;

            return Scaffold(
              appBar: AppBar(
                title: Text(
                    widget.showPurchasedOnly ? 'Past List' : 'List Details'),
                actions: [
                  IconButton(
                    tooltip: 'Share list',
                    onPressed: () => _shareWishlist(wishlist, currentUser),
                    icon: const Icon(Icons.share_outlined),
                  ),
                  if (!widget.showPurchasedOnly)
                    IconButton(
                      tooltip: 'Edit list',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => WishlistEditorScreen(
                              repository: widget.repository,
                              wishlist: wishlist,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  PopupMenuButton<_WishlistAction>(
                    onSelected: (action) async {
                      if (action == _WishlistAction.delete) {
                        final shouldDelete = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete list?'),
                            content: Text(
                              'Remove "${wishlist.title}" permanently from this device?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );

                        if (shouldDelete == true) {
                          try {
                            await widget.repository.deleteWishlist(wishlist.id);
                            _showFeedback(context, 'List deleted.');
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          } catch (error) {
                            if (!context.mounted) {
                              return;
                            }
                            _showError(
                              error,
                              fallbackMessage: 'Could not delete this list.',
                            );
                          }
                        }
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _WishlistAction.delete,
                        child: Text('Delete list'),
                      ),
                    ],
                  ),
                ],
              ),
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.pagePadding,
                    AppConstants.pagePadding,
                    AppConstants.pagePadding,
                    120,
                  ),
                  children: [
                    _buildHeroCard(context, wishlist),
                    const SizedBox(height: AppConstants.sectionGap),
                    _buildSharingSection(context, wishlist, currentUser),
                    const SizedBox(height: AppConstants.sectionGap),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.showPurchasedOnly
                                ? 'Purchased Items'
                                : 'Items',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        if (!widget.showPurchasedOnly)
                          Tooltip(
                            message: 'Add a new item',
                            child: TextButton.icon(
                              onPressed: () => _openItemEditor(
                                context,
                                wishlistId: wishlist.id,
                                currentUser: currentUser,
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('Add Item'),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spacing2),
                    Text(
                      widget.showPurchasedOnly
                          ? 'Past lists only show items that were marked as purchased.'
                          : 'Swipe right to mark purchased, swipe left to delete, and drag the handle to reprioritize.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppConstants.sectionGap),
                    if (sourceItems.isNotEmpty) ...[
                      _buildItemControls(context),
                      const SizedBox(height: AppConstants.sectionGap),
                    ],
                    if (sourceItems.isEmpty)
                      _buildEmptyItemsState(context)
                    else if (visibleItems.isEmpty)
                      _buildFilteredItemsEmptyState(context)
                    else if (canReorder)
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: visibleItems.length,
                        onReorder: (oldIndex, newIndex) {
                          _reorderItems(
                            wishlist: wishlist,
                            visibleItems: visibleItems,
                            oldIndex: oldIndex,
                            newIndex: newIndex,
                          );
                        },
                        itemBuilder: (context, index) {
                          final item = visibleItems[index];
                          return _buildItemCard(
                            context,
                            wishlist: wishlist,
                            item: item,
                            key: ValueKey('reorder-${item.id}'),
                            showDragHandle: true,
                            dragIndex: index,
                            currentUser: currentUser,
                          );
                        },
                      )
                    else
                      ...visibleItems.map(
                        (item) => _buildItemCard(
                          context,
                          wishlist: wishlist,
                          item: item,
                          key: ValueKey('item-${item.id}'),
                          currentUser: currentUser,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
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
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wishlist.coverImageUrl != null &&
              wishlist.coverImageUrl!.isNotEmpty) ...[
            _buildImage(
              context,
              imageSource: wishlist.coverImageUrl!,
              aspectRatio: 16 / 9,
            ),
            const SizedBox(height: AppConstants.spacing4),
          ],
          Text(
            wishlist.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppConstants.spacing2),
          Text(
            wishlist.description.isEmpty
                ? 'No description yet.'
                : wishlist.description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppConstants.spacing4),
          Wrap(
            spacing: AppConstants.spacing2,
            runSpacing: AppConstants.spacing2,
            children: [
              _buildMetadataChip(context, label: '${wishlist.year}'),
              _buildMetadataChip(
                context,
                label: '${wishlist.activeItemCount} active',
              ),
              _buildMetadataChip(
                context,
                label: '${wishlist.purchasedItemCount} purchased',
              ),
              if (wishlist.isShared)
                _buildMetadataChip(context, label: 'Shared'),
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

  Widget _buildSharingSection(
    BuildContext context,
    Wishlist wishlist,
    AppUser? currentUser,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppConstants.spacing3,
            runSpacing: AppConstants.spacing3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 120),
                child: Text(
                  'Sharing',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              TextButton.icon(
                onPressed: () => _shareWishlist(wishlist, currentUser),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share Link'),
              ),
              if (!widget.showPurchasedOnly)
                TextButton.icon(
                  onPressed: () => _openInviteDialog(context, wishlist),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Invite'),
                ),
            ],
          ),
          const SizedBox(height: AppConstants.spacing2),
          Text(
            'Send the list link through WhatsApp, email, or messages. Members can still be tracked locally until the backend arrives.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (wishlist.sharedUsers.isNotEmpty) ...[
            const SizedBox(height: AppConstants.spacing4),
            ...wishlist.sharedUsers.map(
              (user) => _buildSharedUserRow(context, wishlist, user),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSharedUserRow(
    BuildContext context,
    Wishlist wishlist,
    SharedUser user,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.itemGap),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      child: Row(
        children: [
          CircleAvatar(
            child: Text(user.name.isEmpty ? '?' : user.name[0].toUpperCase()),
          ),
          const SizedBox(width: AppConstants.spacing4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppConstants.spacing1),
                Text(
                  '${user.role} · ${user.email}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (!widget.showPurchasedOnly)
            IconButton(
              tooltip: 'Remove collaborator',
              onPressed: () => _removeCollaborator(context, wishlist, user),
              icon: const Icon(Icons.person_remove_outlined),
            ),
        ],
      ),
    );
  }

  Widget _buildItemControls(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sort by rank',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppConstants.spacing2),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.cardPadding,
            vertical: 2,
          ),
          child: DropdownButtonFormField<String>(
            value: _selectedSort,
            decoration: const InputDecoration(
              border: InputBorder.none,
              labelText: 'Order',
            ),
            items: const [
              DropdownMenuItem(
                value: _sortHighestRank,
                child: Text(_sortHighestRank),
              ),
              DropdownMenuItem(
                value: _sortLowestRank,
                child: Text(_sortLowestRank),
              ),
              DropdownMenuItem(
                value: _sortNewestAdded,
                child: Text(_sortNewestAdded),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedSort = value ?? _sortHighestRank;
              });
            },
          ),
        ),
        const SizedBox(height: AppConstants.itemGap),
        if (!widget.showPurchasedOnly) ...[
          Text(
            'Filter by status',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: AppConstants.spacing2),
          Wrap(
            spacing: AppConstants.spacing2,
            runSpacing: AppConstants.spacing2,
            children: [
              _buildFilterChip(
                label: _allFilter,
                isSelected: _selectedStatus == _allFilter,
                onSelected: () {
                  setState(() {
                    _selectedStatus = _allFilter;
                  });
                },
              ),
              ...WishlistItem.statuses
                  .where((status) => status != 'Purchased')
                  .map(
                    (status) => _buildFilterChip(
                      label: status,
                      isSelected: _selectedStatus == status,
                      onSelected: () {
                        setState(() {
                          _selectedStatus = status;
                        });
                      },
                    ),
                  ),
            ],
          ),
          const SizedBox(height: AppConstants.itemGap),
        ],
        Text(
          'Filter by priority',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppConstants.spacing2),
        Wrap(
          spacing: AppConstants.spacing2,
          runSpacing: AppConstants.spacing2,
          children: [
            _buildFilterChip(
              label: _allFilter,
              isSelected: _selectedPriority == _allFilter,
              onSelected: () {
                setState(() {
                  _selectedPriority = _allFilter;
                });
              },
            ),
            ...WishlistItem.priorities.map(
              (priority) => _buildFilterChip(
                label: priority,
                isSelected: _selectedPriority == priority,
                onSelected: () {
                  setState(() {
                    _selectedPriority = priority;
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
    );
  }

  Widget _buildEmptyItemsState(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      child: Text(
        widget.showPurchasedOnly
            ? 'No purchased items yet. Swipe right on an active item to move it into Past Lists.'
            : 'No active items yet. Add the first item to start ranking this list.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildFilteredItemsEmptyState(BuildContext context) {
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
            'No items match these filters.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppConstants.spacing2),
          Text(
            'Clear the current filters to see the rest of the ranked items again.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppConstants.itemGap),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedStatus = _allFilter;
                _selectedPriority = _allFilter;
              });
            },
            child: const Text('Clear Filters'),
          ),
        ],
      ),
    );
  }

  List<WishlistItem> _applyFilters(List<WishlistItem> items) {
    final filteredItems = items.where((item) {
      final statusMatches = widget.showPurchasedOnly
          ? true
          : _selectedStatus == _allFilter || item.status == _selectedStatus;
      final priorityMatches =
          _selectedPriority == _allFilter || item.priority == _selectedPriority;
      return statusMatches && priorityMatches;
    }).toList(growable: false);

    filteredItems.sort((left, right) {
      switch (_selectedSort) {
        case _sortLowestRank:
          return right.rank.compareTo(left.rank);
        case _sortNewestAdded:
          return right.createdAt.compareTo(left.createdAt);
        case _sortHighestRank:
        default:
          return left.rank.compareTo(right.rank);
      }
    });

    return filteredItems;
  }

  void _reorderItems({
    required Wishlist wishlist,
    required List<WishlistItem> visibleItems,
    required int oldIndex,
    required int newIndex,
  }) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final nextItems = List<WishlistItem>.from(visibleItems);
    final movedItem = nextItems.removeAt(oldIndex);
    nextItems.insert(newIndex, movedItem);

    try {
      await widget.repository.reorderWishlistItems(
        wishlistId: wishlist.id,
        orderedItemIds:
            nextItems.map((item) => item.id).toList(growable: false),
      );
      _showFeedback(context, 'Item rank updated.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(
        error,
        fallbackMessage: 'Could not reorder items.',
      );
    }
  }

  Widget _buildItemCard(
    BuildContext context, {
    required Wishlist wishlist,
    required WishlistItem item,
    required Key key,
    required AppUser? currentUser,
    bool showDragHandle = false,
    int? dragIndex,
  }) {
    final displayedPriceLabel =
        _formatPriceLabelForUser(item.priceLabel, currentUser);

    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: AppConstants.itemGap),
      child: Dismissible(
        key: ValueKey('dismiss-${item.id}'),
        direction: widget.showPurchasedOnly
            ? DismissDirection.endToStart
            : DismissDirection.horizontal,
        background: _buildSwipeBackground(
          context,
          color: Colors.green.shade600,
          alignment: Alignment.centerLeft,
          icon: Icons.check_circle_outline,
          label: 'Purchased',
        ),
        secondaryBackground: _buildSwipeBackground(
          context,
          color: Colors.red.shade600,
          alignment: Alignment.centerRight,
          icon: Icons.delete_outline,
          label: 'Delete',
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd &&
              !widget.showPurchasedOnly) {
            try {
              await widget.repository.updateWishlistItemStatus(
                wishlistId: wishlist.id,
                itemId: item.id,
                status: 'Purchased',
              );
              _showFeedback(context, 'Moved to Past Lists.');
            } catch (error) {
              if (!context.mounted) {
                return false;
              }
              _showError(
                error,
                fallbackMessage: 'Could not update this item.',
              );
            }
            return false;
          }

          return _confirmDeleteItem(context, wishlist, item);
        },
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          ),
          padding: const EdgeInsets.all(AppConstants.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
                _buildImage(
                  context,
                  imageSource: item.imageUrl!,
                  aspectRatio: 4 / 3,
                ),
                const SizedBox(height: AppConstants.itemGap),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showDragHandle && dragIndex != null)
                    ReorderableDragStartListener(
                      index: dragIndex,
                      child: Padding(
                        padding: const EdgeInsets.only(right: AppConstants.spacing2),
                        child: Icon(
                          Icons.drag_indicator,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Share item',
                    onPressed: () => _shareItem(wishlist, item),
                    icon: const Icon(Icons.share_outlined),
                  ),
                  PopupMenuButton<_WishlistItemAction>(
                    tooltip: 'Item actions',
                    onSelected: (action) async {
                      if (action == _WishlistItemAction.edit) {
                        await _openItemEditor(
                          context,
                          wishlistId: wishlist.id,
                          item: item,
                          currentUser: currentUser,
                        );
                        return;
                      }

                      if (action == _WishlistItemAction.moveToActive) {
                        try {
                          await widget.repository.updateWishlistItemStatus(
                            wishlistId: wishlist.id,
                            itemId: item.id,
                            status: 'Saved',
                          );
                          _showFeedback(
                            context,
                            'Moved back to active items.',
                          );
                        } catch (error) {
                          if (!context.mounted) {
                            return;
                          }
                          _showError(
                            error,
                            fallbackMessage: 'Could not update this item.',
                          );
                        }
                        return;
                      }

                      await _confirmDeleteItem(context, wishlist, item);
                    },
                    itemBuilder: (context) {
                      if (widget.showPurchasedOnly) {
                        return const [
                          PopupMenuItem(
                            value: _WishlistItemAction.edit,
                            child: Text('Edit item'),
                          ),
                          PopupMenuItem(
                            value: _WishlistItemAction.moveToActive,
                            child: Text('Move back to active'),
                          ),
                          PopupMenuItem(
                            value: _WishlistItemAction.delete,
                            child: Text('Delete item'),
                          ),
                        ];
                      }

                      return const [
                        PopupMenuItem(
                          value: _WishlistItemAction.edit,
                          child: Text('Edit item'),
                        ),
                        PopupMenuItem(
                          value: _WishlistItemAction.delete,
                          child: Text('Delete item'),
                        ),
                      ];
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildMetadataChip(context, label: 'Rank #${item.rank}'),
                  _buildMetadataChip(context, label: item.status),
                  _buildMetadataChip(context,
                      label: '${item.priority} priority'),
                ],
              ),
              if (item.notes != null && item.notes!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.notes!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (displayedPriceLabel != null) ...[
                const SizedBox(height: 8),
                Text(
                  displayedPriceLabel,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
              if (item.productUrl != null && item.productUrl!.isNotEmpty) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _openProductLink(item),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      item.productUrl!,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openProductLink(item),
                      icon: const Icon(Icons.open_in_new_outlined),
                      label: const Text('Open Link'),
                    ),
                    TextButton.icon(
                      onPressed: () => _copyProductLink(item),
                      icon: const Icon(Icons.link_outlined),
                      label: const Text('Copy Link'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeBackground(
    BuildContext context, {
    required Color color,
    required Alignment alignment,
    required IconData icon,
    required String label,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacing4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: alignment == Alignment.centerLeft
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _openItemEditor(
    BuildContext context, {
    required String wishlistId,
    required AppUser? currentUser,
    WishlistItem? item,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WishlistItemEditorScreen(
          repository: widget.repository,
          wishlistId: wishlistId,
          item: item,
          preferredCurrencyCode: currentUser?.preferredCurrencyCode ?? 'USD',
          preferredCurrencySymbol: currentUser?.preferredCurrencySymbol ?? '\$',
        ),
      ),
    );
  }

  Future<void> _openInviteDialog(
    BuildContext context,
    Wishlist wishlist,
  ) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    var role = 'Editor';

    final collaborator = await showDialog<_InviteCollaboratorResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Invite collaborator'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please add a name.';
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty || !trimmed.contains('@')) {
                          return 'Please add a valid email.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppConstants.spacing3),
                    DropdownButtonFormField<String>(
                      value: role,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: const [
                        DropdownMenuItem(
                          value: 'Editor',
                          child: Text('Editor'),
                        ),
                        DropdownMenuItem(
                          value: 'Viewer',
                          child: Text('Viewer'),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          role = value ?? 'Editor';
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) {
                      return;
                    }

                    Navigator.of(context).pop(
                      _InviteCollaboratorResult(
                        name: nameController.text.trim(),
                        email: emailController.text.trim(),
                        role: role,
                      ),
                    );
                  },
                  child: const Text('Invite'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    emailController.dispose();

    if (collaborator == null) {
      return;
    }

    try {
      final previousCount = wishlist.sharedUsers.length;
      final updatedWishlist = await widget.repository.addSharedUser(
        wishlistId: wishlist.id,
        name: collaborator.name,
        email: collaborator.email,
        role: collaborator.role,
      );

      final nextCount = updatedWishlist?.sharedUsers.length ?? previousCount;
      _showFeedback(
        context,
        nextCount > previousCount
            ? 'Collaborator invited.'
            : 'That collaborator is already on this list.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(
        error,
        fallbackMessage: 'Could not update collaborators.',
      );
    }
  }

  Future<void> _removeCollaborator(
    BuildContext context,
    Wishlist wishlist,
    SharedUser user,
  ) async {
    try {
      final wasRemoved = await widget.repository.removeSharedUser(
        wishlistId: wishlist.id,
        userId: user.id,
      );

      if (wasRemoved) {
        _showFeedback(context, '${user.name} removed.');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(
        error,
        fallbackMessage: 'Could not update collaborators.',
      );
    }
  }

  Future<bool> _confirmDeleteItem(
    BuildContext context,
    Wishlist wishlist,
    WishlistItem item,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove "${item.title}" from this list?'),
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
      try {
        await widget.repository.deleteWishlistItem(
          wishlistId: wishlist.id,
          itemId: item.id,
        );
        _showFeedback(context, 'Item deleted.');
        return true;
      } catch (error) {
        if (!mounted) {
          return false;
        }
        _showError(
          error,
          fallbackMessage: 'Could not delete this item.',
        );
      }
    }

    return false;
  }

  Future<void> _shareWishlist(Wishlist wishlist, AppUser? currentUser) async {
    await Share.share(
      _buildWishlistShareText(wishlist, currentUser),
      subject: wishlist.title,
    );
  }

  Future<void> _shareItem(Wishlist wishlist, WishlistItem item) async {
    await Share.share(
      _buildShareText(wishlist, item, widget.authRepository.getCurrentUser()),
      subject: item.title,
    );
  }

  String _buildWishlistShareText(Wishlist wishlist, AppUser? currentUser) {
    final lines = <String>[
      'Join my Wishiz list "${wishlist.title}" for ${wishlist.year}: wishiz://lists/${wishlist.id}',
    ];

    for (final item in wishlist.activeItems.take(5)) {
      lines.add('- ${item.title}');
      final displayedPriceLabel =
          _formatPriceLabelForUser(item.priceLabel, currentUser);
      if (displayedPriceLabel != null) {
        lines.add('Price: $displayedPriceLabel');
      }
    }

    return lines.join('\n');
  }

  String _buildShareText(
    Wishlist wishlist,
    WishlistItem item,
    AppUser? currentUser,
  ) {
    final lines = <String>[
      '${item.title} from ${wishlist.title}',
      'Rank: #${item.rank}',
    ];

    final displayedPriceLabel =
        _formatPriceLabelForUser(item.priceLabel, currentUser);
    if (displayedPriceLabel != null) {
      lines.add('Price: $displayedPriceLabel');
    }
    if (item.notes != null && item.notes!.isNotEmpty) {
      lines.add(item.notes!);
    }
    if (item.productUrl != null && item.productUrl!.isNotEmpty) {
      lines.add(item.productUrl!);
    }

    return lines.join('\n');
  }

  String? _formatPriceLabelForUser(String? priceLabel, AppUser? currentUser) {
    return CurrencyUtils.convertPriceLabel(
      priceLabel,
      targetCurrencyCode: currentUser?.preferredCurrencyCode ?? 'USD',
    );
  }

  Future<void> _copyProductLink(WishlistItem item) async {
    final productUrl = item.productUrl;
    if (productUrl == null || productUrl.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: productUrl));
    _showFeedback(context, 'Product link copied.');
  }

  Future<void> _openProductLink(WishlistItem item) async {
    final productUrl = item.productUrl;
    if (productUrl == null || productUrl.isEmpty) {
      return;
    }

    final uri = Uri.tryParse(productUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      _showFeedback(context, 'This link is not valid.');
      return;
    }

    final didLaunch = await launchUrl(
      uri,
      mode:
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );

    if (!didLaunch && mounted) {
      _showFeedback(context, 'We could not open that link.');
    }
  }

  void _showFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  Widget _buildImage(
    BuildContext context, {
    required String imageSource,
    required double aspectRatio,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(imageSource);
    final isRemote = uri != null &&
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
      ),
    );

    final image = kIsWeb || isRemote
        ? Image.network(
            imageSource,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => fallback,
          )
        : Image.file(
            File(imageSource),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => fallback,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXl - 8),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: image,
      ),
    );
  }
}

enum _WishlistAction {
  delete,
}

enum _WishlistItemAction {
  edit,
  moveToActive,
  delete,
}

class _InviteCollaboratorResult {
  const _InviteCollaboratorResult({
    required this.name,
    required this.email,
    required this.role,
  });

  final String name;
  final String email;
  final String role;
}
