import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';

class HomeAppBarActions extends StatelessWidget {
  const HomeAppBarActions({
    super.key,
    required this.unreadCount,
    this.reminderCount = 0,
    required this.onPurchaseHistory,
    required this.onNotifications,
    required this.onAccount,
  });

  final int unreadCount;
  /// Aging-saved-items count surfaced in the inbox's Reminders section. The bell
  /// opens that inbox, so the badge reflects unread notifications AND reminders.
  final int reminderCount;
  final VoidCallback onPurchaseHistory;
  final VoidCallback onNotifications;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final badgeCount = unreadCount + reminderCount;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Purchase History',
          onPressed: onPurchaseHistory,
          visualDensity: VisualDensity.compact,
          color: colorScheme.onSurfaceVariant,
          icon: const Icon(Icons.shopping_bag_outlined),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: onNotifications,
              visualDensity: VisualDensity.compact,
              color: colorScheme.onSurfaceVariant,
              icon: const Icon(Icons.notifications_outlined),
            ),
            if (badgeCount > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(
                    badgeCount > 9 ? '9+' : '$badgeCount',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        IconButton(
          tooltip: 'Account',
          onPressed: onAccount,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.account_circle_outlined),
        ),
      ],
    );
  }
}
