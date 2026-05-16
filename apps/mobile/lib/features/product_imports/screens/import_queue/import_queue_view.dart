import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';
import 'package:wishiz/features/product_imports/domain/product_import_repository.dart';
import 'package:wishiz/features/product_imports/screens/import_queue/components/import_job_tile.dart';

class ImportQueueView extends StatelessWidget {
  const ImportQueueView({
    super.key,
    required this.repository,
    required this.isQueueing,
    required this.onOpenWishlist,
    required this.onAssign,
    required this.onReview,
    required this.onRetry,
    required this.onAcknowledge,
  });

  final ProductImportRepository repository;
  final bool isQueueing;
  final ValueChanged<ProductImportJob> onOpenWishlist;
  final ValueChanged<ProductImportJob> onAssign;
  final ValueChanged<ProductImportJob> onReview;
  final ValueChanged<ProductImportJob> onRetry;
  final ValueChanged<ProductImportJob> onAcknowledge;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ProductImportJob>>(
      valueListenable: repository.watchJobs(),
      builder: (context, jobs, _) {
        final visibleJobs = jobs
            .where(
              (job) =>
                  job.acknowledgedAt == null &&
                  !(job.isCompleted && job.wishlistId != null) &&
                  (job.isActive ||
                      job.isCompleted ||
                      job.needsReview ||
                      job.failed),
            )
            .take(5)
            .toList(growable: false);
        if (!isQueueing && visibleJobs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(bottom: AppConstants.itemGap),
          padding: const EdgeInsets.all(AppConstants.cardPadding),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (isQueueing)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.cloud_sync_outlined, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isQueueing
                          ? 'Queueing shared item...'
                          : 'Shared item imports',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              for (final job in visibleJobs) ...[
                const SizedBox(height: AppConstants.itemGap),
                ImportJobTile(
                  job: job,
                  onOpenWishlist: onOpenWishlist,
                  onAssign: onAssign,
                  onReview: onReview,
                  onRetry: onRetry,
                  onAcknowledge: onAcknowledge,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
