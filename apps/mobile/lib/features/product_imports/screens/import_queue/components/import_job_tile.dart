import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/theme/app_colors.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';
import 'package:wishiz/shared/widgets/gradient_progress_bar.dart';
import 'package:wishiz/shared/widgets/shimmer_box.dart';
import 'package:wishiz/shared/widgets/wishiz_image.dart';

class ImportJobTile extends StatelessWidget {
  const ImportJobTile({
    super.key,
    required this.job,
    required this.onOpenWishlist,
    required this.onAssign,
    required this.onReview,
    required this.onRetry,
    required this.onAcknowledge,
  });

  final ProductImportJob job;
  final ValueChanged<ProductImportJob> onOpenWishlist;
  final ValueChanged<ProductImportJob> onAssign;
  final ValueChanged<ProductImportJob> onReview;
  final ValueChanged<ProductImportJob> onRetry;
  final ValueChanged<ProductImportJob> onAcknowledge;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thumbnail + body cross-fade+scale between the waiting skeleton and
        // the settled item so the real content "pops" the moment a job lands.
        // Action buttons live OUTSIDE the switcher so taps stay unambiguous
        // even mid-transition (the switcher transiently mounts both children).
        _morph(_JobThumbnail(job: job)),
        const SizedBox(width: 12),
        Expanded(child: _morph(_JobBody(job: job))),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatePill(job: job),
            if (_jobActions().isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 0, children: _jobActions()),
            ],
          ],
        ),
      ],
    );
  }

  Widget _morph(Widget child) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(job.isActive ? 'active' : 'settled'),
        child: child,
      ),
    );
  }

  List<Widget> _jobActions() {
    if (job.isActive) {
      return const [];
    }
    if (job.isCompleted) {
      if (job.wishlistId == null) {
        return [
          IconButton(
            tooltip: 'Assign to list',
            onPressed: () => onAssign(job),
            icon: const Icon(Icons.playlist_add, size: 20),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: () => onReview(job),
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
        ];
      }
      return [
        IconButton(
          tooltip: 'Open list',
          onPressed: () => onOpenWishlist(job),
          icon: const Icon(Icons.open_in_new, size: 20),
        ),
        IconButton(
          tooltip: 'Hide',
          onPressed: () => onAcknowledge(job),
          icon: const Icon(Icons.close, size: 20),
        ),
      ];
    }
    if (job.needsReview) {
      return [
        if (job.retryable && job.attemptCount <= 1)
          IconButton(
            tooltip: 'Retry',
            onPressed: () => onRetry(job),
            icon: const Icon(Icons.refresh, size: 20),
          ),
        IconButton(
          tooltip: 'Review',
          onPressed: () => onReview(job),
          icon: const Icon(Icons.edit_outlined, size: 20),
        ),
        IconButton(
          tooltip: 'Hide',
          onPressed: () => onAcknowledge(job),
          icon: const Icon(Icons.close, size: 20),
        ),
      ];
    }
    return [
      if (job.retryable && job.attemptCount <= 1)
        IconButton(
          tooltip: 'Retry',
          onPressed: () => onRetry(job),
          icon: const Icon(Icons.refresh, size: 20),
        ),
      IconButton(
        tooltip: 'Edit manually',
        onPressed: () => onReview(job),
        icon: const Icon(Icons.edit_outlined, size: 20),
      ),
      IconButton(
        tooltip: 'Hide',
        onPressed: () => onAcknowledge(job),
        icon: const Icon(Icons.close, size: 20),
      ),
    ];
  }
}

/// 40×40 leading slot. Shimmer while importing; the real product image once
/// settled; a state-appropriate glyph when there is no image.
class _JobThumbnail extends StatelessWidget {
  const _JobThumbnail({required this.job});

  static const double _size = 40;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(10));

  final ProductImportJob job;

  @override
  Widget build(BuildContext context) {
    if (job.isActive) {
      return const ShimmerBox(width: _size, height: _size, borderRadius: _radius);
    }

    final colorScheme = Theme.of(context).colorScheme;
    final imageUrl = job.imageUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    if (hasImage) {
      return WishizImage(
        source: imageUrl,
        width: _size,
        height: _size,
        borderRadius: _radius,
        backgroundColor: colorScheme.surfaceContainerHigh,
        errorChild: _glyphTile(colorScheme),
      );
    }
    return _glyphTile(colorScheme);
  }

  Widget _glyphTile(ColorScheme colorScheme) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        borderRadius: _radius,
        color: colorScheme.surfaceContainerHigh,
      ),
      alignment: Alignment.center,
      child: _glyph(colorScheme),
    );
  }

  Widget _glyph(ColorScheme colorScheme) {
    final IconData icon;
    if (job.unsupported) {
      icon = Icons.block;
    } else if (job.failed) {
      icon = Icons.error_outline;
    } else {
      icon = Icons.shopping_bag_outlined;
    }
    return Icon(
      icon,
      size: 18,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
    );
  }
}

/// Title + price/progress region. Ghost shimmer lines while importing; the real
/// title and price (or a status subtitle) once the job settles.
class _JobBody extends StatelessWidget {
  const _JobBody({required this.job});

  final ProductImportJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (job.isActive) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerBox(width: 110, height: 10),
          const SizedBox(height: 8),
          GradientProgressBar(
            value: job.progressPercent <= 0 ? null : job.progressPercent / 100,
          ),
          const SizedBox(height: 5),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              _stageLabel(job),
              key: ValueKey(_stageLabel(job)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    final priceLabel = job.priceLabel?.trim();
    final showPrice =
        job.isCompleted && priceLabel != null && priceLabel.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _jobTitle(job),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        if (showPrice)
          Text(
            priceLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          )
        else
          Text(
            _jobSubtitle(job),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Colour-coded status pill. Brand gradient while importing; tonal semantic
/// tints once settled.
class _StatePill extends StatelessWidget {
  const _StatePill({required this.job});

  final ProductImportJob job;

  @override
  Widget build(BuildContext context) {
    final (String label, Color bg, Color fg, Gradient? gradient) = _style();
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? bg : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  (String, Color, Color, Gradient?) _style() {
    if (job.isActive) {
      return ('Importing', AppColors.primary, AppColors.onPrimary,
          AppColors.primaryGradient);
    }
    if (job.isCompleted) {
      final label = job.wishlistId == null ? 'Ready' : 'Added';
      return (label, AppColors.tertiary.withValues(alpha: 0.12),
          AppColors.tertiary, null);
    }
    if (job.needsReview) {
      return ('Needs review', AppColors.warningContainer, AppColors.warning,
          null);
    }
    return ("Couldn't import", AppColors.errorContainer.withValues(alpha: 0.16),
        AppColors.errorContainer, null);
  }
}

String _stageLabel(ProductImportJob job) {
  return switch (job.progressStage) {
    'validating' => 'Validating link…',
    'rendering' => 'Loading page…',
    'page_loaded' => 'Reading page…',
    'extracting' => 'Extracting details…',
    'cross_checking' => 'Cross-checking…',
    'done' => 'Finishing…',
    _ => job.status == 'pending' ? 'Waiting to process…' : 'Processing details…',
  };
}

String _jobTitle(ProductImportJob job) {
  final title = job.title?.trim();
  if (title != null && title.isNotEmpty) {
    return title;
  }
  if (job.domain.isNotEmpty) {
    return job.domain;
  }
  return job.normalizedUrl;
}

String _jobSubtitle(ProductImportJob job) {
  if (job.needsReview && job.priceConfidence != 'high') {
    return 'Price needs verification before saving';
  }
  return switch (job.status) {
    'pending' => 'Waiting to process',
    'processing' => 'Processing details',
    'completed' => job.wishlistId == null
        ? 'Ready to assign to a list'
        : 'Added to wishlist',
    'needs_review' => 'Needs review before saving',
    'failed' => _failedSubtitle(job),
    _ => job.status,
  };
}

String _failedSubtitle(ProductImportJob job) {
  if (job.unsupported) {
    return "This store doesn't support automatic import. Add it manually.";
  }
  final error = job.lastError?.trim();
  final prefix = error == null || error.isEmpty ? 'Import failed' : error;
  if (job.retryable && job.attemptCount <= 1) {
    return '$prefix. Retry is available.';
  }
  return '$prefix. Add it manually.';
}
