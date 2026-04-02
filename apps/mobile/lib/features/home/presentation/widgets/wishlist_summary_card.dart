import 'dart:io';

import 'package:flutter/foundation.dart';
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
      margin: const EdgeInsets.only(bottom: AppConstants.itemGap),
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
                  padding: const EdgeInsets.all(AppConstants.cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (coverImageUrl != null &&
                          coverImageUrl!.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusXl - 8,
                          ),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: _buildCoverImage(
                              context,
                              colorScheme: colorScheme,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppConstants.itemGap),
                      ],
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppConstants.spacing1),
                      Text(
                        '$itemCount items · Updated $lastUpdated',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      if (supportingText != null &&
                          supportingText!.isNotEmpty) ...[
                        const SizedBox(height: AppConstants.spacing1),
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
                  AppConstants.cardPadding,
                  0,
                  AppConstants.cardPadding,
                  AppConstants.cardPadding,
                ),
                child: Wrap(
                  spacing: AppConstants.spacing2,
                  runSpacing: AppConstants.spacing2,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImage(
    BuildContext context, {
    required ColorScheme colorScheme,
  }) {
    final source = coverImageUrl!;
    final uri = Uri.tryParse(source);
    final isRemote = uri != null &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            uri.scheme == 'blob' ||
            uri.scheme == 'data');

    final fallback = Container(
      color: colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        color: colorScheme.onSurfaceVariant,
      ),
    );

    if (kIsWeb || isRemote) {
      return Image.network(
        source,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }

    return Image.file(
      File(source),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}
