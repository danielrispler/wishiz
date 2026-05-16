import 'dart:async';
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

enum _ItemFilter { all, active, purchased }

class _WishlistDetailScreenState extends State<WishlistDetailScreen> {
  static const String _sortHighestRank = 'Highest Rank';
  static const String _sortLowestRank = 'Lowest Rank';
  static const String _sortNewestAdded = 'Newest Added';

  String _selectedSort = _sortHighestRank;
  late _ItemFilter _selectedFilter;
  final Set<String> _expandedItemIds = <String>{};
  List<WishlistItem>? _reorderOverride;
  Timer? _pollTimer;
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.showPurchasedOnly
        ? _ItemFilter.purchased
        : _ItemFilter.active;
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

            final capability = _resolveCapability(currentUser, wishlist);
            final sourceItems = switch (_selectedFilter) {
              _ItemFilter.all => wishlist.items,
              _ItemFilter.active => wishlist.activeItems,
              _ItemFilter.purchased => wishlist.purchasedItems,
            }.toList(growable: false);
            final visibleItems = _applyFilters(sourceItems);
            final canReorder =
                capability != _UserCapability.viewer &&
                _selectedFilter != _ItemFilter.purchased &&
                _selectedSort == _sortHighestRank &&
                visibleItems.length > 1;

            return Scaffold(
              appBar: WishizAppBar(
                titleText: widget.showPurchasedOnly
                    ? 'Purchased List'
                    : 'List Details',
                actions: [
                  if (capability != _UserCapability.viewer)
                    IconButton(
                      tooltip: 'Share list',
                      onPressed: () => _showShareDialog(wishlist, currentUser),
                      icon: const Icon(Icons.share_outlined),
                    ),
                  if (!widget.showPurchasedOnly &&
                      capability == _UserCapability.owner)
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
                  if (capability == _UserCapability.owner)
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
                              await widget.repository.deleteWishlist(
                                wishlist.id,
                              );
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
                    const SizedBox(height: AppConstants.spacing2),
                    _buildItemControls(context),
                    const SizedBox(height: AppConstants.sectionGap),
                    if (sourceItems.isEmpty)
                      _buildEmptyItemsState(context)
                    else if (visibleItems.isEmpty)
                      _buildFilteredItemsEmptyState(context)
                    else if (canReorder)
                      Builder(
                        builder: (context) {
                          final reorderItems = _reorderOverride ?? visibleItems;
                          return ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            proxyDecorator: (child, index, animation) {
                              return Material(
                                color: Colors.transparent,
                                child: child,
                              );
                            },
                            itemCount: reorderItems.length,
                            onReorder: (oldIndex, newIndex) {
                              final adjustedNew = newIndex > oldIndex
                                  ? newIndex - 1
                                  : newIndex;
                              final next = List<WishlistItem>.from(
                                reorderItems,
                              );
                              next.insert(adjustedNew, next.removeAt(oldIndex));
                              setState(() => _reorderOverride = next);
                              _reorderItems(
                                wishlist: wishlist,
                                visibleItems: reorderItems,
                                oldIndex: oldIndex,
                                newIndex: newIndex,
                              );
                            },
                            itemBuilder: (context, index) {
                              final item = reorderItems[index];
                              return _buildItemCard(
                                context,
                                wishlist: wishlist,
                                item: item,
                                key: ValueKey('reorder-${item.id}'),
                                showDragHandle: true,
                                dragIndex: index,
                                currentUser: currentUser,
                                capability: capability,
                              );
                            },
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
                          capability: capability,
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
    final hasImage =
        wishlist.coverImageUrl != null && wishlist.coverImageUrl!.isNotEmpty;

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
                _buildSmallLogo(context, wishlist.coverImageUrl!),
                const SizedBox(width: AppConstants.spacing4),
              ] else ...[
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.list_alt_rounded,
                    color: colorScheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: AppConstants.spacing4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wishlist.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
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
              _buildMetadataChip(
                context,
                label: '${wishlist.year}',
                icon: Icons.calendar_today_outlined,
              ),
              _buildMetadataChip(
                context,
                label: '${wishlist.activeItemCount} active',
                icon: Icons.checklist_rtl_rounded,
              ),
              _buildMetadataChip(
                context,
                label: '${wishlist.purchasedItemCount} purchased',
                icon: Icons.shopping_bag_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallLogo(BuildContext context, String imageUrl) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _buildImage(context, imageSource: imageUrl, aspectRatio: 1),
      ),
    );
  }

  Widget _buildMetadataChip(
    BuildContext context, {
    required String label,
    IconData? icon,
    Key? key,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: key,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing2,
        vertical: 4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 12,
              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill(
    BuildContext context, {
    required String label,
    IconData? icon,
    Color? color,
    Color? textColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedTextColor = textColor ?? colorScheme.onSurfaceVariant;

    return Container(
      decoration: BoxDecoration(
        color: color ?? colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing2,
        vertical: 6,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: resolvedTextColor),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: resolvedTextColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  void _showShareDialog(Wishlist wishlist, AppUser? currentUser) {
    final isOwner = currentUser?.id == wishlist.ownerUserId;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Shared people'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacing4,
            vertical: AppConstants.spacing5,
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Everyone with access to this list.',
                    style: Theme.of(dialogContext).textTheme.bodyMedium
                        ?.copyWith(
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppConstants.spacing4),
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
                      currentUser: currentUser,
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
                        fullName: wishlist.ownerFullName,
                        email: '',
                        role: WishlistMemberRole.editor,
                        createdAt: wishlist.createdAt,
                        updatedAt: wishlist.updatedAt,
                      ),
                      currentUser: currentUser,
                      isOwner: isOwner,
                      isOwnerRow: true,
                      roleLabel: 'Owner',
                    ),
                  if (wishlist.members.isNotEmpty) ...[
                    const SizedBox(height: AppConstants.spacing2),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: AppConstants.spacing1,
                        bottom: AppConstants.spacing2,
                      ),
                      child: Text(
                        'Collaborators',
                        style: Theme.of(dialogContext).textTheme.labelLarge
                            ?.copyWith(
                              color: Theme.of(
                                dialogContext,
                              ).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                      ),
                    ),
                    ...wishlist.members.map(
                      (member) => _buildSharedUserRow(
                        dialogContext,
                        wishlist,
                        member,
                        currentUser: currentUser,
                        isOwner: isOwner,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
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

  Widget _buildExpandedActionButton(
    BuildContext context, {
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    bool isPrimary = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isPrimary
                ? colorScheme.primary
                : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isPrimary ? colorScheme.onPrimary : colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: isPrimary
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSharedUserRow(
    BuildContext context,
    Wishlist wishlist,
    WishlistMember user, {
    AppUser? currentUser,
    bool isOwner = false,
    bool isOwnerRow = false,
    String? roleLabel,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = user.fullName.isEmpty ? user.email : user.fullName;
    final subtitle = user.email.isEmpty ? 'Access already granted' : user.email;
    final isCurrentUser = currentUser?.id == user.userId;

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.itemGap),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.92),
        border: Border.all(
          color: isCurrentUser
              ? colorScheme.primary.withValues(alpha: 0.16)
              : colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary.withValues(alpha: 0.18),
                  colorScheme.primaryContainer.withValues(alpha: 0.28),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: Text(
              user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase(),
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spacing4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppConstants.spacing2,
                  runSpacing: AppConstants.spacing2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isCurrentUser)
                      _buildInfoPill(
                        context,
                        label: '(me)',
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        textColor: colorScheme.primary,
                      ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacing1),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppConstants.spacing2),
                Wrap(
                  spacing: AppConstants.spacing2,
                  runSpacing: AppConstants.spacing2,
                  children: [
                    _buildInfoPill(
                      context,
                      label: roleLabel ?? user.role.label,
                      icon: isOwnerRow
                          ? Icons.workspace_premium_rounded
                          : Icons.person_outline_rounded,
                    ),
                    if (isOwnerRow)
                      _buildInfoPill(
                        context,
                        label: 'Full access',
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.22,
                        ),
                        textColor: colorScheme.onSurface,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (!widget.showPurchasedOnly && isOwner && !isOwnerRow)
            IconButton(
              tooltip: 'Remove collaborator',
              onPressed: () => _removeCollaborator(context, wishlist, user),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.errorContainer.withValues(
                  alpha: 0.12,
                ),
                foregroundColor: colorScheme.error,
              ),
              icon: const Icon(Icons.person_remove_outlined, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildItemControls(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final wishlist = widget.repository.findById(widget.wishlistId);
    final currentUser = widget.authRepository.watchCurrentUser().value;
    final capability = wishlist != null
        ? _resolveCapability(currentUser, wishlist)
        : _UserCapability.viewer;
    final showRestore =
        _selectedFilter == _ItemFilter.purchased &&
        wishlist != null &&
        wishlist.purchasedItems.isNotEmpty;
    final showAdd =
        wishlist != null &&
        _selectedFilter != _ItemFilter.purchased &&
        capability != _UserCapability.viewer;

    return LayoutBuilder(
      builder: (context, constraints) {
        final addButtonMinWidth = constraints.maxWidth >= 420
            ? 160.0
            : constraints.maxWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_ItemFilter>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return colorScheme.primary.withOpacity(0.14);
                    }
                    return colorScheme.surfaceContainerLow;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return colorScheme.primary;
                    }
                    return colorScheme.onSurfaceVariant;
                  }),
                  side: WidgetStateProperty.resolveWith(
                    (states) => BorderSide(
                      color: states.contains(WidgetState.selected)
                          ? colorScheme.primary.withOpacity(0.35)
                          : colorScheme.outlineVariant,
                    ),
                  ),
                ),
                segments: const [
                  ButtonSegment(value: _ItemFilter.all, label: Text('All')),
                  ButtonSegment(
                    value: _ItemFilter.active,
                    label: Text('Active'),
                  ),
                  ButtonSegment(
                    value: _ItemFilter.purchased,
                    label: Text('Purchased'),
                  ),
                ],
                selected: {_selectedFilter},
                onSelectionChanged: (selection) {
                  setState(() {
                    _selectedFilter = selection.first;
                  });
                },
              ),
            ),
            const SizedBox(height: AppConstants.spacing3),
            Wrap(
              spacing: AppConstants.spacing2,
              runSpacing: AppConstants.spacing2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedSort,
                    underline: const SizedBox.shrink(),
                    icon: Icon(
                      Icons.sort_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _sortHighestRank,
                        child: Text('Rank'),
                      ),
                      DropdownMenuItem(
                        value: _sortLowestRank,
                        child: Text('Low Rank'),
                      ),
                      DropdownMenuItem(
                        value: _sortNewestAdded,
                        child: Text('Newest'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedSort = value ?? _sortHighestRank;
                      });
                    },
                  ),
                ),
                if (showRestore)
                  FilledButton.tonalIcon(
                    onPressed: () => _restoreAllItems(wishlist),
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('Restore all'),
                  ),
                if (showAdd)
                  ConstrainedBox(
                    constraints: BoxConstraints(minWidth: addButtonMinWidth),
                    child: FilledButton.icon(
                      onPressed: () => _openItemEditor(
                        context,
                        wishlistId: wishlist.id,
                        currentUser: currentUser,
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add item'),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
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
        _selectedFilter == _ItemFilter.purchased
            ? 'No purchased items yet. Swipe right on an active item to mark it as purchased.'
            : _selectedFilter == _ItemFilter.active
            ? 'No active items yet. Add the first item to start ranking this list.'
            : 'No items yet. Add the first item to start this list.',
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

  List<WishlistItem> _applyFilters(List<WishlistItem>? items) {
    final filteredItems = List<WishlistItem>.from(
      items ?? const <WishlistItem>[],
    );

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
      setState(() => _reorderOverride = null);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Item rank updated.')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      setState(() => _reorderOverride = null);
      _showError(error, fallbackMessage: 'Could not reorder items.');
    }
  }

  Widget _buildItemCard(
    BuildContext context, {
    required Wishlist wishlist,
    required WishlistItem item,
    required Key key,
    required AppUser? currentUser,
    required _UserCapability capability,
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
        direction: capability == _UserCapability.viewer
            ? DismissDirection.none
            : DismissDirection.horizontal,
        background: _buildSwipeBackground(
          context,
          color: item.status == WishlistItemStatus.purchased
              ? Colors.blue.shade600
              : Colors.green.shade600,
          alignment: Alignment.centerLeft,
          icon: item.status == WishlistItemStatus.purchased
              ? Icons.restore_outlined
              : Icons.check_circle_outline,
          label: item.status == WishlistItemStatus.purchased
              ? 'Restore'
              : 'Purchased',
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
            if (item.status == WishlistItemStatus.purchased) {
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
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 84),
                      child: Row(
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
                          _buildItemThumbnail(context, item),
                          const SizedBox(width: AppConstants.spacing3),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(height: 1.2),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 20,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: displayedPriceLabel == null
                                        ? const SizedBox.shrink()
                                        : Text(
                                            displayedPriceLabel,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
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
                          _buildMetadataChip(context, label: '#${item.rank}'),
                          const SizedBox(width: AppConstants.spacing2),
                          Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 20,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant.withOpacity(0.5),
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
                    AppConstants.cardPadding,
                    0,
                    AppConstants.cardPadding,
                    AppConstants.spacing3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.notes != null && item.notes!.isNotEmpty) ...[
                        Text(
                          item.notes!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: AppConstants.spacing4),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildMetadataChip(
                            context,
                            label: 'Rank #${item.rank}',
                          ),
                          _buildMetadataChip(
                            context,
                            label:
                                '${item.daysOnList} day${item.daysOnList == 1 ? '' : 's'} on list',
                            key: ValueKey('days-on-list-${item.id}'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppConstants.spacing4),
                      Row(
                        children: [
                          _buildExpandedActionButton(
                            context,
                            onPressed: () => _shareItem(wishlist, item),
                            icon: Icons.share_outlined,
                            label: 'Share',
                          ),
                          if (capability != _UserCapability.viewer) ...[
                            const SizedBox(width: AppConstants.spacing2),
                            _buildExpandedActionButton(
                              context,
                              onPressed: () => _openItemEditor(
                                context,
                                wishlistId: wishlist.id,
                                item: item,
                                currentUser: currentUser,
                              ),
                              icon: Icons.edit_outlined,
                              label: 'Edit',
                            ),
                          ],
                          if (item.productUrl != null &&
                              item.productUrl!.isNotEmpty) ...[
                            const SizedBox(width: AppConstants.spacing2),
                            _buildExpandedActionButton(
                              context,
                              onPressed: () => _openProductLink(item),
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

  Widget _buildItemThumbnail(BuildContext context, WishlistItem item) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surfaceContainerHigh,
      ),
      clipBehavior: Clip.antiAlias,
      child: item.imageUrl != null && item.imageUrl!.isNotEmpty
          ? _buildImage(context, imageSource: item.imageUrl!, aspectRatio: 1)
          : Icon(
              Icons.shopping_bag_outlined,
              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
              size: 22,
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
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => fallback,
          )
        : Image.file(
            File(imageSource),
            fit: BoxFit.cover,
            gaplessPlayback: true,
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
