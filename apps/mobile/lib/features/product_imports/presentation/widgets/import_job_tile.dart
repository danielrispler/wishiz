import 'package:flutter/material.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';

class ImportJobTile extends StatelessWidget {
  const ImportJobTile({
    super.key,
    required this.job,
    required this.onOpenWishlist,
    required this.onReview,
    required this.onRetry,
    required this.onAcknowledge,
  });

  final ProductImportJob job;
  final ValueChanged<ProductImportJob> onOpenWishlist;
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
        if (job.retryable)
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
      if (job.retryable)
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
    return const Icon(Icons.error_outline, size: 20);
  }
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
    'completed' => 'Added to wishlist',
    'needs_review' => 'Needs review before saving',
    'failed' => _failedSubtitle(job),
    _ => job.status,
  };
}

String _failedSubtitle(ProductImportJob job) {
  final error = job.lastError?.trim();
  final prefix = error == null || error.isEmpty ? 'Import failed' : error;
  if (job.retryable) {
    return '$prefix. Retry is available.';
  }
  return '$prefix. Add it manually.';
}
