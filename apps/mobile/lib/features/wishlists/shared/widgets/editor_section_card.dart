import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';

class EditorSectionCard extends StatelessWidget {
  const EditorSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacing5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (description != null) ...[
                      const SizedBox(height: AppConstants.spacing2),
                      Text(
                        description!,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppConstants.spacing3),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: AppConstants.spacing4),
          child,
        ],
      ),
    );
  }
}
