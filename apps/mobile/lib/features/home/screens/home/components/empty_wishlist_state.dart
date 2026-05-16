import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';

class EmptyWishlistState extends StatelessWidget {
  const EmptyWishlistState({
    super.key,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppConstants.spacing2),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppConstants.spacing3),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
