import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_user.dart';
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
                    _showFeedback(context, 'List archived.');
                    return;
                  }

                  if (action == _WishlistAction.restore) {
                    repository.restoreWishlist(wishlist.id);
                    _showFeedback(context, 'List restored.');
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
                    _showFeedback(context, 'List deleted.');
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
                _buildSharingSection(context, wishlist),
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

  Widget _buildSharingSection(BuildContext context, Wishlist wishlist) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sharing',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (!wishlist.isArchived)
                TextButton.icon(
                  onPressed: () => _openInviteDialog(context, wishlist),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Invite'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            wishlist.sharedUsers.isEmpty
                ? 'No collaborators yet. Invite someone to make this list shared.'
                : 'Owner and collaborators for this list.',
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
    final canRemove = !wishlist.isArchived && user.role.toLowerCase() != 'owner';
    final trimmedName = user.name.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacing3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.spacing4),
      child: Row(
        children: [
          CircleAvatar(
            child: Text(
              trimmedName.isEmpty ? '?' : trimmedName[0].toUpperCase(),
            ),
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
                const SizedBox(height: 4),
                Text(
                  '${user.role} · ${user.email}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (canRemove)
            IconButton(
              tooltip: 'Remove collaborator',
              onPressed: () => _removeCollaborator(context, wishlist, user),
              icon: const Icon(Icons.person_remove_outlined),
            ),
        ],
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
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                      ),
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
                      decoration: const InputDecoration(
                        labelText: 'Email',
                      ),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        final uri = Uri.tryParse('mailto:$trimmed');
                        if (trimmed.isEmpty) {
                          return 'Please add an email.';
                        }
                        if (uri == null || !trimmed.contains('@')) {
                          return 'Please add a valid email.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppConstants.spacing3),
                    DropdownButtonFormField<String>(
                      value: role,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                      ),
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

    repository.addSharedUser(
      wishlistId: wishlist.id,
      name: collaborator.name,
      email: collaborator.email,
      role: collaborator.role,
    );
    _showFeedback(context, 'Collaborator invited.');
  }

  void _removeCollaborator(
    BuildContext context,
    Wishlist wishlist,
    SharedUser user,
  ) {
    final wasRemoved = repository.removeSharedUser(
      wishlistId: wishlist.id,
      userId: user.id,
    );

    if (wasRemoved) {
      _showFeedback(context, '${user.name} removed.');
    }
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacing3),
      child: Slidable(
        key: ValueKey(item.id),
        startActionPane: ActionPane(
          motion: const StretchMotion(),
          extentRatio: 0.28,
          children: [
            SlidableAction(
              onPressed: (_) => _shareItem(context, wishlist, item),
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              icon: Icons.share_outlined,
              label: 'Share',
              borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            ),
          ],
        ),
        endActionPane: wishlist.isArchived
            ? null
            : ActionPane(
                motion: const StretchMotion(),
                extentRatio: 0.28,
                children: [
                  SlidableAction(
                    onPressed: (_) => _confirmDeleteItem(context, wishlist, item),
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                  ),
                ],
              ),
        child: Container(
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
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: _WishlistItemAction.edit,
                          child: Text('Edit item'),
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
        ),
      ),
    );
  }

  Future<void> _confirmDeleteItem(
    BuildContext context,
    Wishlist wishlist,
    WishlistItem item,
  ) async {
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
      _showFeedback(context, 'Item deleted.');
    }
  }

  Future<void> _shareItem(
    BuildContext context,
    Wishlist wishlist,
    WishlistItem item,
  ) async {
    await Clipboard.setData(
      ClipboardData(text: _buildShareText(wishlist, item)),
    );
    _showFeedback(context, 'Share details copied.');
  }

  String _buildShareText(Wishlist wishlist, WishlistItem item) {
    final lines = <String>[
      '${item.title} from ${wishlist.title}',
    ];

    if (item.priceLabel != null && item.priceLabel!.isNotEmpty) {
      lines.add('Price: ${item.priceLabel!}');
    }
    if (item.notes != null && item.notes!.isNotEmpty) {
      lines.add(item.notes!);
    }
    if (item.productUrl != null && item.productUrl!.isNotEmpty) {
      lines.add(item.productUrl!);
    }

    return lines.join('\n');
  }

  void _showFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
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
