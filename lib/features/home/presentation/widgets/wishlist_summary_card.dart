import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';

class WishlistSummaryCard extends StatelessWidget {
  final String title;
  final int itemCount;
  final String lastUpdated;
  final String? coverImageUrl;
  final String? supportingText;
  final List<Widget> actions;
  final VoidCallback? onTap;

  const WishlistSummaryCard({
    super.key,
    required this.title,
    required this.itemCount,
    required this.lastUpdated,
    this.coverImageUrl,
    this.supportingText,
    this.actions = const [],
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              label: 'Open wishlist $title with $itemCount items.',
              child: InkWell(
                borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spacing4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (coverImageUrl != null && coverImageUrl!.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusXl - 8,
                          ),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.network(
                              coverImageUrl!,
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
                        ),
                        const SizedBox(height: AppConstants.spacing4),
                      ],
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$itemCount items · Updated $lastUpdated',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      if (supportingText != null && supportingText!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          supportingText!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacing4,
                  0,
                  AppConstants.spacing4,
                  AppConstants.spacing4,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
