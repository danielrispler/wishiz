import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';

class GlassmorphicBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const GlassmorphicBottomNav({
    super.key,
    required this.currentIndex,
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
              _buildNavItem(context, icon: Icons.format_list_bulleted, label: 'My lists', index: 0),
              _buildNavItem(context, icon: Icons.group_outlined, label: 'Shared', index: 1),
              _buildNavItem(context, icon: Icons.history, label: 'Past lists', index: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, {required IconData icon, required String label, required int index}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = currentIndex == index;
    final color = isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    
    return InkWell(
      onTap: () => onTap(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppConstants.spacing4, horizontal: AppConstants.spacing3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
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
