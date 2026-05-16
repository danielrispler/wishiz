import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';

enum _MetadataPillStyle { standard, value }

class _MetadataPillData {
  const _MetadataPillData({
    required this.label,
    this.style = _MetadataPillStyle.standard,
  });

  final String label;
  final _MetadataPillStyle style;
}

class WishlistSummaryCard extends StatelessWidget {
  final String title;
  final int itemCount;
  final String? coverImageUrl;
  final String? supportingText;
  final String? totalValue;
  final VoidCallback? onTap;

  const WishlistSummaryCard({
    super.key,
    required this.title,
    required this.itemCount,
    this.coverImageUrl,
    this.supportingText,
    this.totalValue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final metadata = <_MetadataPillData>[
      _MetadataPillData(
        label: '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
      ),
    ];
    if (supportingText != null && supportingText!.isNotEmpty) {
      metadata.add(_MetadataPillData(label: supportingText!));
    }
    if (totalValue != null) {
      metadata.add(
        _MetadataPillData(
          label: 'Value $totalValue',
          style: _MetadataPillStyle.value,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        child: Material(
          color: Colors.transparent,
          child: Semantics(
            button: true,
            label: 'Open wishlist $title with $itemCount items.',
            child: InkWell(
              onTap: onTap,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPreviewPanel(context, colorScheme: colorScheme),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.cardPadding,
                        AppConstants.spacing3,
                        AppConstants.cardPadding,
                        10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 20,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: AppConstants.spacing2),
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  color: colorScheme.onSurfaceVariant,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppConstants.spacing1),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final pills = [
                                for (final item in metadata)
                                  _buildPillFromData(context, item),
                              ];
                              final fitsSingleLine = _metadataFitsSingleLine(
                                context,
                                metadata,
                                constraints.maxWidth,
                              );

                              if (fitsSingleLine) {
                                return Row(
                                  children: [
                                    for (var i = 0; i < pills.length; i++) ...[
                                      if (i > 0)
                                        const SizedBox(
                                          width: AppConstants.spacing1,
                                        ),
                                      pills[i],
                                    ],
                                  ],
                                );
                              }

                              return Wrap(
                                spacing: AppConstants.spacing1,
                                runSpacing: 6,
                                children: pills,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPillFromData(BuildContext context, _MetadataPillData pill) {
    return switch (pill.style) {
      _MetadataPillStyle.standard => _buildMetadataPill(context, pill.label),
      _MetadataPillStyle.value => _buildValuePill(context, pill.label),
    };
  }

  bool _metadataFitsSingleLine(
    BuildContext context,
    List<_MetadataPillData> metadata,
    double maxWidth,
  ) {
    if (metadata.isEmpty) {
      return true;
    }

    final textTheme = Theme.of(context).textTheme;
    final textDirection = Directionality.of(context);
    final gapWidth = AppConstants.spacing1 * (metadata.length - 1);
    var totalWidth = 0.0;
    for (final pill in metadata) {
      totalWidth += _measurePillWidth(
        pill,
        textTheme: textTheme,
        textDirection: textDirection,
      );
    }
    totalWidth += gapWidth;

    return totalWidth <= maxWidth;
  }

  double _measurePillWidth(
    _MetadataPillData pill, {
    required TextTheme textTheme,
    required TextDirection textDirection,
  }) {
    final textStyle = textTheme.labelMedium?.copyWith(
      fontWeight:
          pill.style == _MetadataPillStyle.value
              ? FontWeight.w700
              : FontWeight.w600,
      fontSize: 11.5,
    );
    final painter = TextPainter(
      text: TextSpan(text: pill.label, style: textStyle),
      textDirection: textDirection,
      maxLines: 1,
    )..layout();

    const horizontalPadding = 20.0;
    if (pill.style == _MetadataPillStyle.value) {
      return painter.width + horizontalPadding + 15;
    }

    return painter.width + horizontalPadding;
  }

  Widget _buildPreviewPanel(
    BuildContext context, {
    required ColorScheme colorScheme,
  }) {
    final hasImage = coverImageUrl != null && coverImageUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
      child: SizedBox(
        width: 112,
        height: 112,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child:
              hasImage
                  ? _buildCoverImage(context, colorScheme: colorScheme)
                  : Container(
                    color: colorScheme.surfaceContainerHigh,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.auto_awesome_mosaic_rounded,
                      color: colorScheme.primary,
                      size: 24,
                    ),
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
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }

    return Image.file(
      File(source),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }

  Widget _buildMetadataPill(BuildContext context, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        value,
        style: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
        ),
      ),
    );
  }

  Widget _buildValuePill(BuildContext context, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.diamond_outlined, size: 12, color: colorScheme.primary),
          const SizedBox(width: 3),
          Text(
            value,
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
