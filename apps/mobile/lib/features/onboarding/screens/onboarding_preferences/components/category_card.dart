import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/theme/app_colors.dart';
import 'package:wishiz/features/onboarding/domain/entities/preference_category.dart';

class CategoryCard extends StatefulWidget {
  const CategoryCard({
    super.key,
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final PreferenceCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<CategoryCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.surfaceContainerLow
                : AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            border: Border.all(
              color: widget.isSelected
                  ? AppColors.primary
                  : AppColors.outlineVariant,
              width: widget.isSelected ? 2.0 : 1.0,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.category.emoji,
                  style: const TextStyle(fontSize: 36),
                ),
                const SizedBox(height: AppConstants.spacing2),
                Text(
                  widget.category.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: widget.isSelected
                        ? AppColors.primary
                        : AppColors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
