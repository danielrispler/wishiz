import 'package:flutter/material.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';

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
        _JobStatusIcon(job: job),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _jobTitle(job),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              if (job.isActive)
                _ImportProgress(job: job)
              else
                Text(
                  _jobSubtitle(job),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Wrap(spacing: 4, children: _jobActions()),
      ],
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

class _JobStatusIcon extends StatelessWidget {
  const _JobStatusIcon({required this.job});

  final ProductImportJob job;

  @override
  Widget build(BuildContext context) {
    if (job.isActive) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (job.isCompleted) {
      return const Icon(Icons.check_circle_outline, size: 20);
    }
    if (job.needsReview) {
      return const Icon(Icons.rate_review_outlined, size: 20);
    }
    if (job.unsupported) {
      return const Icon(Icons.block, size: 20);
    }
    return const Icon(Icons.error_outline, size: 20);
  }
}

class _ImportProgress extends StatelessWidget {
  const _ImportProgress({required this.job});

  final ProductImportJob job;

  @override
  Widget build(BuildContext context) {
    final percent = job.progressPercent.clamp(0, 100);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _stageLabel(job),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          // percent == 0 → indeterminate (just claimed). Otherwise animate
          // smoothly between polled values so the bar glides rather than jumps.
          child: percent == 0
              ? const LinearProgressIndicator(minHeight: 4)
              : TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: percent / 100),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOut,
                  builder: (context, value, _) =>
                      LinearProgressIndicator(value: value, minHeight: 4),
                ),
        ),
      ],
    );
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
