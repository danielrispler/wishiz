import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/wishlists/shared/widgets/editor_utils.dart';

class ItemPreviewCard extends StatelessWidget {
  const ItemPreviewCard({
    super.key,
    required this.title,
    required this.notes,
    required this.price,
    required this.imageUrl,
    required this.isLinkPreview,
  });

  final String title;
  final String notes;
  final String price;
  final String imageUrl;
  final bool isLinkPreview;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayTitle = title.isEmpty ? 'Your item title' : title;
    final displayNotes = notes.isEmpty
        ? 'A short preview of how this item will look before saving.'
        : notes;
    final displayPrice = price.isEmpty ? 'No price yet' : price;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacing5),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: imageUrl.isEmpty
                ? Icon(
                    Icons.shopping_bag_outlined,
                    color: colorScheme.primary,
                    size: 28,
                  )
                : _PreviewImage(imageUrl: imageUrl, colorScheme: colorScheme),
          ),
          const SizedBox(width: AppConstants.spacing4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayTitle, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppConstants.spacing1),
                Text(
                  displayPrice,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: colorScheme.primary),
                ),
                const SizedBox(height: AppConstants.spacing2),
                Text(
                  displayNotes,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (isLinkPreview) ...[
                  const SizedBox(height: AppConstants.spacing3),
                  _MetaPill(label: 'Imported'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.imageUrl, required this.colorScheme});

  final String imageUrl;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(imageUrl);
    final isRemote = isRemoteUri(uri);
    final fallback = Container(
      color: colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: colorScheme.onSurfaceVariant),
    );

    return kIsWeb || isRemote
        ? Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          )
        : Image.file(
            File(imageUrl),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing3,
        vertical: AppConstants.spacing2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
