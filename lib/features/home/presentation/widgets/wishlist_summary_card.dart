import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';

class WishlistSummaryCard extends StatelessWidget {
  final String title;
  final int itemCount;
  final String lastUpdated;
  final VoidCallback? onTap;

  const WishlistSummaryCard({
    super.key,
    required this.title,
    required this.itemCount,
    required this.lastUpdated,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacing3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacing4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '$itemCount items · Updated $lastUpdated',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
