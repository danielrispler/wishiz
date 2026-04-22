import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/navigation/wishiz_share_text.dart';
import 'package:wishiz/core/utils/currency_utils.dart';
import 'package:wishiz/core/utils/error_utils.dart';
import 'package:wishiz/core/widgets/wishiz_app_bar.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_member.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_editor_screen.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_item_editor_screen.dart';

class WishlistDetailScreen extends StatefulWidget {
  const WishlistDetailScreen({
    super.key,
    required this.repository,
    required this.authRepository,
    required this.sharedProductRepository,
    required this.wishlistId,
    this.showPurchasedOnly = false,
  });

  final WishlistRepository repository;
  final AuthRepository authRepository;
  final SharedProductRepository sharedProductRepository;
  final String wishlistId;
  final bool showPurchasedOnly;

  @override
  State<WishlistDetailScreen> createState() => _WishlistDetailScreenState();
}

class _WishlistDetailScreenState extends State<WishlistDetailScreen> {
  static const String _sortHighestRank = 'Highest Rank';
  static const String _sortLowestRank = 'Lowest Rank';
  static const String _sortNewestAdded = 'Newest Added';

  String _selectedSort = _sortHighestRank;
  final Set<String> _expandedItemIds = <String>{};

  void _showError(Object error, {required String fallbackMessage}) {
    _showFeedback(
      context,
      formatErrorMessage(error, fallbackMessage: fallbackMessage),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: widget.authRepository.watchCurrentUser(),
      builder: (context, currentUser, _) {
        return ValueListenableBuilder<List<Wishlist>>(
          valueListenable: widget.repository.watchWishlists(),
          builder: (context, _, child) {
            final wishlist = widget.repository.findById(widget.wishlistId);

            if (wishlist == null) {
              return Scaffold(
                appBar: const WishizAppBar(titleText: 'List Details'),
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
            final canReorder =
                !widget.showPurchasedOnly &&
                _selectedSort == _sortHighestRank &&
                visibleItems.length > 1;

            return Scaffold(
              appBar: WishizAppBar(
                titleText: widget.showPurchasedOnly
                    ? 'Past List'
                    : 'List Details',
                actions: [
                  IconButton(
                    tooltip: 'Share list',
                    onPressed: () =>
                        _showShareDialog(context, wishlist, currentUser),
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
                            if (!context.mounted) {
                              return;
                            }
                            _showFeedback(context, 'List deleted.');
                            Navigator.of(context).pop();
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
                    if (widget.showPurchasedOnly &&
                        wishlist.purchasedItems.isNotEmpty) ...[
                      const SizedBox(height: AppConstants.spacing2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: () => _restoreAllItems(wishlist),
                          icon: const Icon(Icons.restore_outlined),
                          label: const Text('Restore All'),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppConstants.spacing2),
                    Text(
                      widget.showPurchasedOnly
                          ? 'Swipe right to restore an item to the active list, or swipe left to delete it.'
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataChip(
    BuildContext context, {
    required String label,
    Key? key,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: key,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing3,
        vertical: 10,
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }

  void _showShareDialog(
    BuildContext context,
    Wishlist wishlist,
    AppUser? currentUser,
  ) {
    final isOwner = currentUser?.id == wishlist.ownerUserId;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Sharing'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isOwner && currentUser != null)
                  _buildSharedUserRow(
                    dialogContext,
                    wishlist,
                    WishlistMember(
                      userId: currentUser.id,
                      fullName: currentUser.fullName,
                      email: currentUser.email,
                      role: WishlistMemberRole.editor,
                      createdAt: wishlist.createdAt,
                      updatedAt: wishlist.updatedAt,
                    ),
                    isOwner: isOwner,
                    isOwnerRow: true,
                    roleLabel: 'Owner',
                  )
                else
                  _buildSharedUserRow(
                    dialogContext,
                    wishlist,
                    WishlistMember(
                      userId: wishlist.ownerUserId,
                      fullName: 'List Owner',
                      email: '',
                      role: WishlistMemberRole.editor,
                      createdAt: wishlist.createdAt,
                      updatedAt: wishlist.updatedAt,
                    ),
                    isOwner: isOwner,
                    isOwnerRow: true,
                    roleLabel: 'Owner',
                  ),
                if (wishlist.members.isNotEmpty) ...[
                  ...wishlist.members.map(
                    (member) => _buildSharedUserRow(
                      dialogContext,
                      wishlist,
                      member,
                      isOwner: isOwner,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (isOwner)
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _openInviteDialog(context, wishlist);
                },
                child: const Text('Invite'),
              ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _shareWishlist(wishlist, currentUser);
              },
              child: const Text('Share list'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSharedUserRow(
    BuildContext context,
    Wishlist wishlist,
    WishlistMember user, {
    bool isOwner = false,
    bool isOwnerRow = false,
    String? roleLabel,
  }) {
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
            child: Text(
              user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase(),
            ),
          ),
          const SizedBox(width: AppConstants.spacing4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName.isEmpty ? user.email : user.fullName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppConstants.spacing1),
                Text(
                  roleLabel ?? user.role.label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (!widget.showPurchasedOnly && isOwner && !isOwnerRow)
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
        Text('Sort by rank', style: Theme.of(context).textTheme.labelLarge),
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
            initialValue: _selectedSort,
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
      ],
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
            'No items match the current view.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  List<WishlistItem> _applyFilters(List<WishlistItem> items) {
    final filteredItems = List<WishlistItem>.from(items);

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
    final messenger = ScaffoldMessenger.of(context);

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final nextItems = List<WishlistItem>.from(visibleItems);
    final movedItem = nextItems.removeAt(oldIndex);
    nextItems.insert(newIndex, movedItem);

    try {
      await widget.repository.reorderWishlistItems(
        wishlistId: wishlist.id,
        orderedItemIds: nextItems
            .map((item) => item.id)
            .toList(growable: false),
      );
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Item rank updated.')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showError(error, fallbackMessage: 'Could not reorder items.');
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
    final displayedPriceLabel = _formatPriceLabelForUser(
      item.priceLabel,
      currentUser,
    );
    final isExpanded = _expandedItemIds.contains(item.id);

    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: AppConstants.itemGap),
      child: Dismissible(
        key: ValueKey('dismiss-${item.id}'),
        direction: DismissDirection.horizontal,
        background: _buildSwipeBackground(
          context,
          color: widget.showPurchasedOnly
              ? Colors.blue.shade600
              : Colors.green.shade600,
          alignment: Alignment.centerLeft,
          icon: widget.showPurchasedOnly
              ? Icons.restore_outlined
              : Icons.check_circle_outline,
          label: widget.showPurchasedOnly ? 'Restore' : 'Purchased',
        ),
        secondaryBackground: _buildSwipeBackground(
          context,
          color: Colors.red.shade600,
          alignment: Alignment.centerRight,
          icon: Icons.delete_outline,
          label: 'Delete',
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            if (widget.showPurchasedOnly) {
              await _restoreItemToActive(wishlist: wishlist, item: item);
            } else {
              await _moveItemToPastList(wishlist: wishlist, item: item);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedItemIds.remove(item.id);
                      } else {
                        _expandedItemIds.add(item.id);
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.cardPadding,
                      vertical: AppConstants.spacing3,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (showDragHandle && dragIndex != null)
                              ReorderableDragStartListener(
                                index: dragIndex,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: AppConstants.spacing2,
                                  ),
                                  child: Icon(
                                    Icons.drag_indicator,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (displayedPriceLabel != null) ...[
                                    const SizedBox(
                                      height: AppConstants.spacing1,
                                    ),
                                    Text(
                                      displayedPriceLabel,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelMedium,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (item.imageUrl != null &&
                                item.imageUrl!.isNotEmpty) ...[
                              const SizedBox(width: AppConstants.spacing2),
                              SizedBox(
                                width: 72,
                                child: _buildImage(
                                  context,
                                  imageSource: item.imageUrl!,
                                  aspectRatio: 1,
                                ),
                              ),
                            ],
                            const SizedBox(width: AppConstants.spacing1),
                            Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppConstants.spacing2),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton.icon(
                                onPressed: () => _shareItem(wishlist, item),
                                icon: const Icon(Icons.share_outlined),
                                label: const Text('Share'),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppConstants.spacing3,
                                    vertical: AppConstants.spacing2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppConstants.spacing2),
                            Expanded(
                              child: TextButton.icon(
                                onPressed: () => _openItemEditor(
                                  context,
                                  wishlistId: wishlist.id,
                                  item: item,
                                  currentUser: currentUser,
                                ),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Edit'),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppConstants.spacing3,
                                    vertical: AppConstants.spacing2,
                                  ),
                                ),
                              ),
                            ),
                            if (item.productUrl != null &&
                                item.productUrl!.isNotEmpty) ...[
                              const SizedBox(width: AppConstants.spacing2),
                              Expanded(
                                child: TextButton.icon(
                                  onPressed: () => _openProductLink(item),
                                  icon: const Icon(Icons.open_in_new_outlined),
                                  label: const Text('Open Link'),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppConstants.spacing3,
                                      vertical: AppConstants.spacing2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.cardPadding,
                    0,
                    AppConstants.cardPadding,
                    AppConstants.spacing3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildMetadataChip(
                            context,
                            label: 'Rank #${item.rank}',
                          ),
                          _buildMetadataChip(context, label: item.status.label),
                          _buildMetadataChip(
                            context,
                            label: '${item.priority.label} priority',
                          ),
                          _buildMetadataChip(
                            context,
                            label:
                                '${item.daysOnList} day${item.daysOnList == 1 ? '' : 's'} on list',
                            key: ValueKey('days-on-list-${item.id}'),
                          ),
                        ],
                      ),
                      if (item.notes != null && item.notes!.isNotEmpty) ...[
                        const SizedBox(height: AppConstants.spacing2),
                        Text(
                          item.notes!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
                crossFadeState: isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 180),
              ),
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
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: Colors.white),
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
          sharedProductRepository: widget.sharedProductRepository,
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
    var email = '';
    var role = WishlistMemberRole.editor;

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
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      onChanged: (value) {
                        email = value;
                      },
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty || !trimmed.contains('@')) {
                          return 'Please add a valid email.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppConstants.spacing3),
                    DropdownButtonFormField<WishlistMemberRole>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: const [
                        DropdownMenuItem(
                          value: WishlistMemberRole.editor,
                          child: Text('Editor'),
                        ),
                        DropdownMenuItem(
                          value: WishlistMemberRole.viewer,
                          child: Text('Viewer'),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          role = value ?? WishlistMemberRole.editor;
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
                        email: email.trim(),
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

    if (collaborator == null) {
      return;
    }

    try {
      final invite = await widget.repository.createInvite(
        wishlistId: wishlist.id,
        email: collaborator.email,
        role: collaborator.role,
      );
      if (!context.mounted) {
        return;
      }
      final inviteToken = invite.token?.trim();
      if (inviteToken == null || inviteToken.isEmpty) {
        _showFeedback(context, 'Collaborator invited.');
        return;
      }

      await SharePlus.instance.share(
        ShareParams(
          text: WishizShareText.buildWishlistInviteShareText(
            wishlist: wishlist,
            inviteToken: inviteToken,
          ),
          subject: wishlist.title,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error, fallbackMessage: 'Could not update collaborators.');
    }
  }

  Future<void> _removeCollaborator(
    BuildContext context,
    Wishlist wishlist,
    WishlistMember user,
  ) async {
    try {
      final wasRemoved = await widget.repository.removeMember(
        wishlistId: wishlist.id,
        userId: user.userId,
      );

      if (wasRemoved) {
        if (!mounted) {
          return;
        }
        _showFeedback(this.context, '${user.fullName} removed.');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error, fallbackMessage: 'Could not update collaborators.');
    }
  }

  Future<void> _moveItemToPastList({
    required Wishlist wishlist,
    required WishlistItem item,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await widget.repository.updateWishlistItemStatus(
        wishlistId: wishlist.id,
        itemId: item.id,
        status: WishlistItemStatus.purchased,
      );
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Moved to Past Lists.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              formatErrorMessage(
                error,
                fallbackMessage: 'Could not update this item.',
              ),
            ),
          ),
        );
    }
  }

  Future<void> _restoreItemToActive({
    required Wishlist wishlist,
    required WishlistItem item,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await widget.repository.updateWishlistItemStatus(
        wishlistId: wishlist.id,
        itemId: item.id,
        status: WishlistItemStatus.saved,
      );
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Moved back to active items.')),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              formatErrorMessage(
                error,
                fallbackMessage: 'Could not update this item.',
              ),
            ),
          ),
        );
    }
  }

  Future<void> _restoreAllItems(Wishlist wishlist) async {
    final purchasedItems = wishlist.purchasedItems;
    final messenger = ScaffoldMessenger.of(context);
    if (purchasedItems.isEmpty) {
      return;
    }

    try {
      await Future.wait(
        purchasedItems.map(
          (item) => widget.repository.updateWishlistItemStatus(
            wishlistId: wishlist.id,
            itemId: item.id,
            status: WishlistItemStatus.saved,
          ),
        ),
      );
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('All items moved back to active items.'),
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              formatErrorMessage(
                error,
                fallbackMessage: 'Could not restore this list.',
              ),
            ),
          ),
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
        if (!context.mounted) {
          return false;
        }
        _showFeedback(context, 'Item deleted.');
        return true;
      } catch (error) {
        if (!mounted) {
          return false;
        }
        _showError(error, fallbackMessage: 'Could not delete this item.');
      }
    }

    return false;
  }

  Future<void> _shareWishlist(Wishlist wishlist, AppUser? currentUser) async {
    await SharePlus.instance.share(
      ShareParams(
        text: WishizShareText.buildWishlistShareText(wishlist: wishlist),
        subject: wishlist.title,
      ),
    );
  }

  Future<void> _shareItem(Wishlist wishlist, WishlistItem item) async {
    await SharePlus.instance.share(
      ShareParams(
        text: WishizShareText.buildWishlistItemShareText(
          wishlist: wishlist,
          item: item,
        ),
        subject: item.title,
      ),
    );
  }

  String? _formatPriceLabelForUser(String? priceLabel, AppUser? currentUser) {
    return CurrencyUtils.convertPriceLabel(
      priceLabel,
      targetCurrencyCode: currentUser?.preferredCurrencyCode ?? 'USD',
    );
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
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );

    if (!didLaunch && mounted) {
      _showFeedback(context, 'We could not open that link.');
    }
  }

  void _showFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildImage(
    BuildContext context, {
    required String imageSource,
    required double aspectRatio,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(imageSource);
    final isRemote =
        uri != null &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            uri.scheme == 'blob' ||
            uri.scheme == 'data');

    final fallback = Container(
      color: colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: colorScheme.onSurfaceVariant),
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

    return InkWell(
      onTap: () => _openImageViewer(context, imageSource),
      borderRadius: BorderRadius.circular(AppConstants.radiusXl - 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusXl - 8),
        child: AspectRatio(aspectRatio: aspectRatio, child: image),
      ),
    );
  }

  Future<void> _openImageViewer(BuildContext context, String imageSource) {
    final uri = Uri.tryParse(imageSource);
    final isRemote =
        uri != null &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            uri.scheme == 'blob' ||
            uri.scheme == 'data');

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
                      ? Image.network(imageSource, fit: BoxFit.contain)
                      : Image.file(File(imageSource), fit: BoxFit.contain),
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

enum _WishlistAction { delete }

class _InviteCollaboratorResult {
  const _InviteCollaboratorResult({required this.email, required this.role});

  final String email;
  final WishlistMemberRole role;
}
