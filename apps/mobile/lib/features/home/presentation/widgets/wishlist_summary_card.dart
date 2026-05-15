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
    final textTheme = Theme.of(context).textTheme;
    final details = <String>[
      '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
      'Updated $lastUpdated',
    ];
    if (supportingText != null && supportingText!.isNotEmpty) {
      details.add(supportingText!);
    }

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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPreview(context, colorScheme: colorScheme),
                      const SizedBox(width: AppConstants.spacing4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: textTheme.titleMedium),
                            const SizedBox(height: AppConstants.spacing2),
                            Wrap(
                              spacing: AppConstants.spacing2,
                              runSpacing: AppConstants.spacing2,
                              children: details
                                  .map(
                                    (detail) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppConstants.spacing3,
                                        vertical: AppConstants.spacing2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(
                                          AppConstants.radiusFull,
                                        ),
                                      ),
                                      child: Text(
                                        detail,
                                        style: textTheme.labelMedium,
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacing2),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
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

  Widget _buildPreview(
    BuildContext context, {
    required ColorScheme colorScheme,
  }) {
    final hasImage = coverImageUrl != null && coverImageUrl!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXl - 6),
      child: SizedBox(
        width: 88,
        height: 88,
        child: hasImage
            ? _buildCoverImage(context, colorScheme: colorScheme)
            : Container(
                color: colorScheme.surfaceContainerHigh,
                padding: const EdgeInsets.all(AppConstants.spacing3),
                child: Icon(
                  Icons.auto_awesome_mosaic_rounded,
                  color: colorScheme.primary,
                  size: 28,
                ),
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
    final isRemote =
        uri != null &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            uri.scheme == 'blob' ||
            uri.scheme == 'data');

    final fallback = Container(
      color: colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: colorScheme.onSurfaceVariant),
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
