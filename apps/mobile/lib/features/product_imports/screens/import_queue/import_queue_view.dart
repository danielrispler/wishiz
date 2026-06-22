import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/theme/app_colors.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';
import 'package:wishiz/features/product_imports/domain/product_import_repository.dart';
import 'package:wishiz/features/product_imports/screens/import_queue/components/import_job_tile.dart';

/// Number of import tiles shown before the "Show N more" toggle.
const int _collapsedCount = 2;

class ImportQueueView extends StatefulWidget {
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
  State<ImportQueueView> createState() => _ImportQueueViewState();
}

class _ImportQueueViewState extends State<ImportQueueView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isQueueing = widget.isQueueing;
    return ValueListenableBuilder<List<ProductImportJob>>(
      valueListenable: widget.repository.watchJobs(),
      builder: (context, jobs, _) {
        final allVisible = jobs
            .where(
              (job) =>
                  job.acknowledgedAt == null &&
                  !(job.isCompleted && job.wishlistId != null) &&
                  (job.isActive ||
                      job.isCompleted ||
                      job.needsReview ||
                      job.failed),
            )
            .toList(growable: false);
        if (!isQueueing && allVisible.isEmpty) {
          return const SizedBox.shrink();
        }

        final hasOverflow = allVisible.length > _collapsedCount;
        final visibleJobs = _expanded || !hasOverflow
            ? allVisible
            : allVisible.sublist(0, _collapsedCount);

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
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: isQueueing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.onPrimary,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.cloud_sync_outlined,
                            size: 18,
                            color: AppColors.onPrimary,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isQueueing
                          ? 'Queueing shared item...'
                          : 'Shared item imports',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              for (final job in visibleJobs) ...[
                const SizedBox(height: AppConstants.spacing2),
                ImportJobTile(
                  job: job,
                  onOpenWishlist: widget.onOpenWishlist,
                  onAssign: widget.onAssign,
                  onReview: widget.onReview,
                  onRetry: widget.onRetry,
                  onAcknowledge: widget.onAcknowledge,
                ),
              ],
              if (hasOverflow)
                _MoreToggle(
                  hiddenCount: allVisible.length - _collapsedCount,
                  expanded: _expanded,
                  onTap: () => setState(() => _expanded = !_expanded),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MoreToggle extends StatelessWidget {
  const _MoreToggle({
    required this.hiddenCount,
    required this.expanded,
    required this.onTap,
  });

  final int hiddenCount;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = expanded ? 'Show less' : 'Show $hiddenCount more';
    return Padding(
      padding: const EdgeInsets.only(top: AppConstants.spacing2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
