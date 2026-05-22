import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/wishlists/wishlist_share_text.dart';
import 'package:wishiz/core/utils/currency_utils.dart';
import 'package:wishiz/core/utils/error_utils.dart';
import 'package:wishiz/shared/widgets/wishiz_app_bar.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_member.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/wishlists/screens/wishlist_editor/wishlist_editor_screen.dart';
import 'package:wishiz/features/wishlists/screens/wishlist_item_editor/wishlist_item_editor_screen.dart';
import 'components/wishlist_header.dart';
import 'components/wishlist_item_card.dart';
import 'components/wishlist_item_controls.dart';
import 'components/wishlist_share_dialog.dart';

enum _UserCapability { owner, editor, viewer }

_UserCapability _resolveCapability(AppUser? user, Wishlist wishlist) {
  if (user == null) return _UserCapability.viewer;
  if (user.id == wishlist.ownerUserId) return _UserCapability.owner;
  for (final member in wishlist.members) {
    if (member.userId == user.id) {
      return member.role == WishlistMemberRole.editor
          ? _UserCapability.editor
          : _UserCapability.viewer;
    }
  }
  return _UserCapability.viewer;
}

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
  String _selectedSort = WishlistItemControls.sortHighestRank;
  late WishlistItemFilter _selectedFilter;
  List<WishlistItem>? _reorderOverride;
  Timer? _pollTimer;
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.showPurchasedOnly ? WishlistItemFilter.purchased : WishlistItemFilter.active;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_isPolling) return;
    _isPolling = true;
    try {
      await widget.repository.refresh();
    } catch (_) {
      // Ignore poll errors silently.
    } finally {
      _isPolling = false;
    }
  }

  void _showFeedback(BuildContext ctx, String message) {
    ScaffoldMessenger.of(ctx)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(Object error, {required String fallbackMessage}) {
    _showFeedback(context, formatErrorMessage(error, fallbackMessage: fallbackMessage));
  }

  List<WishlistItem> _applyFilters(List<WishlistItem> items) {
    final sorted = List<WishlistItem>.from(items);
    sorted.sort((a, b) {
      switch (_selectedSort) {
        case WishlistItemControls.sortLowestRank: return b.rank.compareTo(a.rank);
        case WishlistItemControls.sortNewestAdded: return b.createdAt.compareTo(a.createdAt);
        default: return a.rank.compareTo(b.rank);
      }
    });
    return sorted;
  }

  void _reorderItems({
    required Wishlist wishlist,
    required List<WishlistItem> visibleItems,
    required int oldIndex,
    required int newIndex,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (newIndex > oldIndex) newIndex -= 1;
    final nextItems = List<WishlistItem>.from(visibleItems);
    nextItems.insert(newIndex, nextItems.removeAt(oldIndex));
    try {
      await widget.repository.reorderWishlistItems(
        wishlistId: wishlist.id,
        orderedItemIds: nextItems.map((item) => item.id).toList(growable: false),
      );
      if (!mounted) return;
      setState(() => _reorderOverride = null);
      messenger..hideCurrentSnackBar()..showSnackBar(const SnackBar(content: Text('List reordered.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _reorderOverride = null);
      messenger..hideCurrentSnackBar()..showSnackBar(
        SnackBar(content: Text(formatErrorMessage(error, fallbackMessage: 'Could not save the new order.'))),
      );
    }
  }

  Future<void> _openItemEditor(BuildContext ctx, {required String wishlistId, required AppUser? currentUser, WishlistItem? item}) {
    return Navigator.of(ctx).push(
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

  Future<void> _removeCollaborator(BuildContext ctx, Wishlist wishlist, WishlistMember user) async {
    try {
      final wasRemoved = await widget.repository.removeMember(wishlistId: wishlist.id, userId: user.userId);
      if (wasRemoved && mounted) _showFeedback(context, '${user.fullName} removed.');
    } catch (error) {
      if (!mounted) return;
      _showError(error, fallbackMessage: 'Could not update collaborators.');
    }
  }

  Future<void> _moveItemToPastList({required Wishlist wishlist, required WishlistItem item}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.updateWishlistItemStatus(
        wishlistId: wishlist.id, itemId: item.id, status: WishlistItemStatus.purchased,
      );
      if (!mounted) return;
      messenger..hideCurrentSnackBar()..showSnackBar(const SnackBar(content: Text('Moved to Past Lists.')));
    } catch (error) {
      if (!mounted) return;
      messenger..hideCurrentSnackBar()..showSnackBar(SnackBar(
        content: Text(formatErrorMessage(error, fallbackMessage: 'Could not update this item.')),
      ));
    }
  }

  Future<void> _restoreItemToActive({required Wishlist wishlist, required WishlistItem item}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.updateWishlistItemStatus(
        wishlistId: wishlist.id, itemId: item.id, status: WishlistItemStatus.saved,
      );
      if (!mounted) return;
      messenger..hideCurrentSnackBar()..showSnackBar(const SnackBar(content: Text('Moved back to active items.')));
    } catch (error) {
      if (!mounted) return;
      messenger..hideCurrentSnackBar()..showSnackBar(SnackBar(
        content: Text(formatErrorMessage(error, fallbackMessage: 'Could not update this item.')),
      ));
    }
  }

  Future<void> _restoreAllItems(Wishlist wishlist) async {
    final purchasedItems = wishlist.purchasedItems;
    if (purchasedItems.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Future.wait(purchasedItems.map((item) => widget.repository.updateWishlistItemStatus(
        wishlistId: wishlist.id, itemId: item.id, status: WishlistItemStatus.saved,
      )));
      if (!mounted) return;
      messenger..hideCurrentSnackBar()..showSnackBar(const SnackBar(content: Text('All items moved back to active items.')));
    } catch (error) {
      if (!mounted) return;
      messenger..hideCurrentSnackBar()..showSnackBar(SnackBar(
        content: Text(formatErrorMessage(error, fallbackMessage: 'Could not restore this list.')),
      ));
    }
  }

  Future<bool> _confirmDeleteItem(BuildContext ctx, Wishlist wishlist, WishlistItem item) async {
    final shouldDelete = await showDialog<bool>(
      context: ctx,
      builder: (context) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove "${item.title}" from this list?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (shouldDelete == true) {
      try {
        await widget.repository.deleteWishlistItem(wishlistId: wishlist.id, itemId: item.id);
        if (!ctx.mounted) return false;
        _showFeedback(ctx, 'Item deleted.');
        return true;
      } catch (error) {
        if (!mounted) return false;
        _showError(error, fallbackMessage: 'Could not delete this item.');
      }
    }
    return false;
  }

  Future<void> _shareWishlist(Wishlist wishlist, AppUser? currentUser) async {
    try {
      final invite = await widget.repository.createInvite(
        wishlistId: wishlist.id,
        role: WishlistMemberRole.editor,
      );
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        text: WishizShareText.buildWishlistInviteShareText(
          wishlist: wishlist,
          inviteToken: invite.token!,
        ),
        subject: wishlist.title,
      ));
    } catch (e) {
      if (!mounted) return;
      _showFeedback(context, 'Could not create invite link: $e');
    }
  }

  Future<void> _shareItem(Wishlist wishlist, WishlistItem item) async {
    await SharePlus.instance.share(ShareParams(
      text: WishizShareText.buildWishlistItemShareText(wishlist: wishlist, item: item),
      subject: item.title,
    ));
  }

  Future<void> _openProductLink(WishlistItem item) async {
    final productUrl = item.productUrl;
    if (productUrl == null || productUrl.isEmpty) return;
    final uri = Uri.tryParse(productUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      _showFeedback(context, 'This link is not valid.');
      return;
    }
    final didLaunch = await launchUrl(uri, mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
    if (!didLaunch && mounted) _showFeedback(context, 'We could not open that link.');
  }

  String? _formatPriceLabelForUser(String? priceLabel, AppUser? currentUser) {
    return CurrencyUtils.convertPriceLabel(priceLabel, targetCurrencyCode: currentUser?.preferredCurrencyCode ?? 'USD');
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
                body: Center(child: Text('This list no longer exists.', style: Theme.of(context).textTheme.headlineSmall)),
              );
            }

            final capability = _resolveCapability(currentUser, wishlist);
            final canEdit = capability != _UserCapability.viewer;
            final sourceItems = switch (_selectedFilter) {
              WishlistItemFilter.all => wishlist.items,
              WishlistItemFilter.active => wishlist.activeItems,
              WishlistItemFilter.purchased => wishlist.purchasedItems,
            }.toList(growable: false);
            final visibleItems = _applyFilters(sourceItems);
            final canReorder = canEdit &&
                _selectedFilter != WishlistItemFilter.purchased &&
                _selectedSort == WishlistItemControls.sortHighestRank &&
                visibleItems.length > 1;

            return Scaffold(
              appBar: WishizAppBar(
                titleText: widget.showPurchasedOnly ? 'Purchased List' : 'List Details',
                actions: [
                  if (canEdit)
                    IconButton(
                      tooltip: 'Share list',
                      onPressed: () => showWishlistShareDialog(
                        context: context,
                        wishlist: wishlist,
                        currentUser: currentUser,
                        onRemoveCollaborator: _removeCollaborator,
                        onShareList: () => _shareWishlist(wishlist, currentUser),
                      ),
                      icon: const Icon(Icons.share_outlined),
                    ),
                  if (!widget.showPurchasedOnly && capability == _UserCapability.owner)
                    IconButton(
                      tooltip: 'Edit list',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => WishlistEditorScreen(repository: widget.repository, wishlist: wishlist)),
                      ),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  if (capability == _UserCapability.owner)
                    PopupMenuButton<_WishlistAction>(
                      onSelected: (action) async {
                        if (action == _WishlistAction.delete) {
                          final shouldDelete = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete list?'),
                              content: Text('Remove "${wishlist.title}" permanently from this device?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                                TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
                              ],
                            ),
                          );
                          if (shouldDelete == true) {
                            try {
                              await widget.repository.deleteWishlist(wishlist.id);
                              if (!context.mounted) return;
                              _showFeedback(context, 'List deleted.');
                              Navigator.of(context).pop();
                            } catch (error) {
                              if (!context.mounted) return;
                              _showError(error, fallbackMessage: 'Could not delete this list.');
                            }
                          }
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: _WishlistAction.delete, child: Text('Delete list')),
                      ],
                    ),
                ],
              ),
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.pagePadding, AppConstants.pagePadding, AppConstants.pagePadding, 120,
                  ),
                  children: [
                    WishlistHeader(wishlist: wishlist),
                    const SizedBox(height: AppConstants.spacing2),
                    WishlistItemControls(
                      selectedFilter: _selectedFilter,
                      selectedSort: _selectedSort,
                      canEdit: canEdit,
                      showRestore: _selectedFilter == WishlistItemFilter.purchased && wishlist.purchasedItems.isNotEmpty,
                      showAdd: _selectedFilter != WishlistItemFilter.purchased && canEdit,
                      onFilterChanged: (f) => setState(() => _selectedFilter = f),
                      onSortChanged: (s) => setState(() => _selectedSort = s),
                      onAddItem: () => _openItemEditor(context, wishlistId: wishlist.id, currentUser: currentUser),
                      onRestoreAll: () => _restoreAllItems(wishlist),
                    ),
                    const SizedBox(height: AppConstants.sectionGap),
                    if (sourceItems.isEmpty)
                      _EmptyState(filter: _selectedFilter)
                    else if (visibleItems.isEmpty)
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                        ),
                        padding: const EdgeInsets.all(AppConstants.cardPadding),
                        child: Text('No items match the current view.', style: Theme.of(context).textTheme.titleMedium),
                      )
                    else if (canReorder)
                      Builder(
                        builder: (context) {
                          final reorderItems = _reorderOverride ?? visibleItems;
                          return ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            proxyDecorator: (child, index, animation) => Material(color: Colors.transparent, child: child),
                            itemCount: reorderItems.length,
                            onReorder: (oldIndex, newIndex) {
                              final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
                              final next = List<WishlistItem>.from(reorderItems);
                              next.insert(adjustedNew, next.removeAt(oldIndex));
                              setState(() => _reorderOverride = next);
                              _reorderItems(wishlist: wishlist, visibleItems: reorderItems, oldIndex: oldIndex, newIndex: newIndex);
                            },
                            itemBuilder: (context, index) {
                              final item = reorderItems[index];
                              return WishlistItemCard(
                                key: ValueKey('reorder-${item.id}'),
                                item: item,
                                displayedPriceLabel: _formatPriceLabelForUser(item.priceLabel, currentUser),
                                canEdit: canEdit,
                                showDragHandle: true,
                                dragIndex: index,
                                onSwipeTogglePurchased: () => item.status == WishlistItemStatus.purchased
                                    ? _restoreItemToActive(wishlist: wishlist, item: item)
                                    : _moveItemToPastList(wishlist: wishlist, item: item),
                                onSwipeDelete: () => _confirmDeleteItem(context, wishlist, item),
                                onEdit: () => _openItemEditor(context, wishlistId: wishlist.id, item: item, currentUser: currentUser),
                                onShare: () => _shareItem(wishlist, item),
                                onOpenLink: item.productUrl?.isNotEmpty == true ? () => _openProductLink(item) : null,
                              );
                            },
                          );
                        },
                      )
                    else
                      ...visibleItems.map((item) => WishlistItemCard(
                        key: ValueKey('item-${item.id}'),
                        item: item,
                        displayedPriceLabel: _formatPriceLabelForUser(item.priceLabel, currentUser),
                        canEdit: canEdit,
                        showDragHandle: false,
                        onSwipeTogglePurchased: () => item.status == WishlistItemStatus.purchased
                            ? _restoreItemToActive(wishlist: wishlist, item: item)
                            : _moveItemToPastList(wishlist: wishlist, item: item),
                        onSwipeDelete: () => _confirmDeleteItem(context, wishlist, item),
                        onEdit: () => _openItemEditor(context, wishlistId: wishlist.id, item: item, currentUser: currentUser),
                        onShare: () => _shareItem(wishlist, item),
                        onOpenLink: item.productUrl?.isNotEmpty == true ? () => _openProductLink(item) : null,
                      )),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

enum _WishlistAction { delete }

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final WishlistItemFilter filter;

  @override
  Widget build(BuildContext context) {
    final message = filter == WishlistItemFilter.purchased
        ? 'No purchased items yet. Swipe right on an active item to mark it as purchased.'
        : filter == WishlistItemFilter.active
        ? 'No active items yet. Add the first item to start ranking this list.'
        : 'No items yet. Add the first item to start this list.';

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
