import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/theme/app_colors.dart';

class GlassmorphicBottomNav extends StatelessWidget {
  const GlassmorphicBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    const tabCount = 2;
    const navHeight = 64.0;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: SizedBox(
          height: navHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest.withValues(
                    alpha: 0.82,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.onSurface.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final selectorWidth =
                        (constraints.maxWidth - AppConstants.spacing2) /
                        tabCount;

                    return SizedBox(
                      height: 48,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          IgnorePointer(
                            child: AnimatedAlign(
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                              alignment: currentIndex == 0
                                  ? Alignment.centerLeft
                                  : Alignment.centerRight,
                              child: Container(
                                width: selectorWidth,
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusXl,
                                  ),
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.primary,
                                      AppColors.primaryContainer,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.24,
                                      ),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: _NavItem(
                                  label: 'Lists',
                                  icon: Icons.auto_awesome_mosaic_rounded,
                                  selected: currentIndex == 0,
                                  onTap: () => onTap(0),
                                ),
                              ),
                              const SizedBox(width: AppConstants.spacing2),
                              Expanded(
                                child: _NavItem(
                                  label: 'Shared',
                                  icon: Icons.favorite_outline_rounded,
                                  selected: currentIndex == 1,
                                  onTap: () => onTap(1),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            color: selected
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.36),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                scale: selected ? 1 : 0.96,
                child: Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? AppColors.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppConstants.spacing2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                style:
                    theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? AppColors.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ) ??
                    const TextStyle(),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
