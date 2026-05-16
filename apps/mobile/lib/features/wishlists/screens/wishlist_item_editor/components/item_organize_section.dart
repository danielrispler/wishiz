import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/shared/widgets/editor_section_card.dart';

class ItemOrganizeSection extends StatelessWidget {
  const ItemOrganizeSection({
    super.key,
    required this.selectedPriority,
    required this.selectedStatus,
    required this.onPriorityChanged,
    required this.onStatusChanged,
  });

  final WishlistItemPriority selectedPriority;
  final WishlistItemStatus selectedStatus;
  final ValueChanged<WishlistItemPriority> onPriorityChanged;
  final ValueChanged<WishlistItemStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return EditorSectionCard(
      title: 'Priority and status',
      description: 'Large tap targets make this easier to adjust quickly.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Priority', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppConstants.spacing2),
          Wrap(
            spacing: AppConstants.spacing2,
            runSpacing: AppConstants.spacing2,
            children: WishlistItem.priorities
                .map(
                  (priority) => ChoiceChip(
                    label: Text(priority.label),
                    selected: selectedPriority == priority,
                    onSelected: (_) => onPriorityChanged(priority),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: AppConstants.spacing4),
          Text('Status', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppConstants.spacing2),
          Wrap(
            spacing: AppConstants.spacing2,
            runSpacing: AppConstants.spacing2,
            children: WishlistItem.statuses
                .map(
                  (status) => ChoiceChip(
                    label: Text(status.label),
                    selected: selectedStatus == status,
                    onSelected: (_) => onStatusChanged(status),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}
