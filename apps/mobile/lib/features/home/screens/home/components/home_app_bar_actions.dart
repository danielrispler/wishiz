import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';

class HomeAppBarActions extends StatelessWidget {
  const HomeAppBarActions({
    super.key,
    required this.reminderCount,
    required this.onPurchaseHistory,
    required this.onReminders,
    required this.onAccount,
  });

  final int reminderCount;
  final VoidCallback onPurchaseHistory;
  final VoidCallback onReminders;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
              tooltip: 'Reminders',
              onPressed: onReminders,
              visualDensity: VisualDensity.compact,
              color: colorScheme.onSurfaceVariant,
              icon: const Icon(Icons.notifications_outlined),
            ),
            if (reminderCount > 0)
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
                    reminderCount > 9 ? '9+' : '$reminderCount',
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
