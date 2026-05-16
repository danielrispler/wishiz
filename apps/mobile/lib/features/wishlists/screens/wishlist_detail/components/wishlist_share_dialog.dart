import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_member.dart';
import 'wishlist_detail_chips.dart';

void showWishlistShareDialog({
  required BuildContext context,
  required Wishlist wishlist,
  required AppUser? currentUser,
  required Future<void> Function(BuildContext, Wishlist, WishlistMember) onRemoveCollaborator,
  required VoidCallback onShareList,
}) {
  final isOwner = currentUser?.id == wishlist.ownerUserId;

  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
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
                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppConstants.spacing4),
              if (isOwner && currentUser != null)
                WishlistMemberRow(
                  member: WishlistMember(
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
                  showRemoveButton: false,
                  onRemove: null,
                )
              else
                WishlistMemberRow(
                  member: WishlistMember(
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
                  showRemoveButton: false,
                  onRemove: null,
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
                    style: Theme.of(dialogContext).textTheme.labelLarge?.copyWith(
                      color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                ...wishlist.members.map(
                  (member) => WishlistMemberRow(
                    member: member,
                    currentUser: currentUser,
                    isOwner: isOwner,
                    showRemoveButton: isOwner,
                    onRemove: isOwner
                        ? () => onRemoveCollaborator(dialogContext, wishlist, member)
                        : null,
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
            onShareList();
          },
          child: const Text('Share list'),
        ),
      ],
    ),
  );
}

class WishlistMemberRow extends StatelessWidget {
  const WishlistMemberRow({
    super.key,
    required this.member,
    required this.currentUser,
    required this.isOwner,
    this.isOwnerRow = false,
    this.roleLabel,
    required this.showRemoveButton,
    required this.onRemove,
  });

  final WishlistMember member;
  final AppUser? currentUser;
  final bool isOwner;
  final bool isOwnerRow;
  final String? roleLabel;
  final bool showRemoveButton;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = member.fullName.isEmpty ? member.email : member.fullName;
    final subtitle = member.email.isEmpty ? 'Access already granted' : member.email;
    final isCurrentUser = currentUser?.id == member.userId;

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
              member.fullName.isEmpty ? '?' : member.fullName[0].toUpperCase(),
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
                    Text(displayName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (isCurrentUser)
                      WishlistInfoPill(
                        label: '(me)',
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        textColor: colorScheme.primary,
                      ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacing1),
                Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                const SizedBox(height: AppConstants.spacing2),
                Wrap(
                  spacing: AppConstants.spacing2,
                  runSpacing: AppConstants.spacing2,
                  children: [
                    WishlistInfoPill(
                      label: roleLabel ?? member.role.label,
                      icon: isOwnerRow ? Icons.workspace_premium_rounded : Icons.person_outline_rounded,
                    ),
                    if (isOwnerRow)
                      WishlistInfoPill(
                        label: 'Full access',
                        color: colorScheme.primaryContainer.withValues(alpha: 0.22),
                        textColor: colorScheme.onSurface,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (showRemoveButton && onRemove != null)
            IconButton(
              tooltip: 'Remove collaborator',
              onPressed: onRemove,
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.12),
                foregroundColor: colorScheme.error,
              ),
              icon: const Icon(Icons.person_remove_outlined, size: 20),
            ),
        ],
      ),
    );
  }
}
