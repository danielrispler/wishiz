import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';

class GlassmorphicBottomNav extends StatelessWidget {
  final int currentIndex;
  final int reminderCount;
  final ValueChanged<int> onTap;

  const GlassmorphicBottomNav({
    super.key,
    required this.currentIndex,
    this.reminderCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
        child: Container(
          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(context,
                  icon: Icons.format_list_bulleted,
                  label: 'My lists',
                  index: 0),
              _buildNavItem(context,
                  icon: Icons.group_outlined, label: 'Shared', index: 1),
              _buildNavItem(context,
                  icon: Icons.history, label: 'Past lists', index: 2),
              _buildNavItem(
                context,
                icon: Icons.notifications_outlined,
                label: 'Reminders',
                index: 3,
                badgeCount: reminderCount,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int index,
    int badgeCount = 0,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = currentIndex == index;
    final color =
        isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: () => onTap(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppConstants.spacing4,
          horizontal: AppConstants.spacing3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color),
                if (badgeCount > 0)
                  Positioned(
                    right: -8,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull,
                        ),
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
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
