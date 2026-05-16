import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';

enum WishlistItemFilter { all, active, purchased }

class WishlistItemControls extends StatelessWidget {
  const WishlistItemControls({
    super.key,
    required this.selectedFilter,
    required this.selectedSort,
    required this.canEdit,
    required this.showRestore,
    required this.showAdd,
    required this.onFilterChanged,
    required this.onSortChanged,
    required this.onAddItem,
    required this.onRestoreAll,
  });

  static const String sortHighestRank = 'Highest Rank';
  static const String sortLowestRank = 'Lowest Rank';
  static const String sortNewestAdded = 'Newest Added';

  final WishlistItemFilter selectedFilter;
  final String selectedSort;
  final bool canEdit;
  final bool showRestore;
  final bool showAdd;
  final ValueChanged<WishlistItemFilter> onFilterChanged;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onAddItem;
  final VoidCallback onRestoreAll;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final addButtonMinWidth = constraints.maxWidth >= 420 ? 160.0 : constraints.maxWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<WishlistItemFilter>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return colorScheme.primary.withOpacity(0.14);
                    return colorScheme.surfaceContainerLow;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return colorScheme.primary;
                    return colorScheme.onSurfaceVariant;
                  }),
                  side: WidgetStateProperty.resolveWith(
                    (states) => BorderSide(
                      color: states.contains(WidgetState.selected)
                          ? colorScheme.primary.withOpacity(0.35)
                          : colorScheme.outlineVariant,
                    ),
                  ),
                ),
                segments: const [
                  ButtonSegment(value: WishlistItemFilter.all, label: Text('All')),
                  ButtonSegment(value: WishlistItemFilter.active, label: Text('Active')),
                  ButtonSegment(value: WishlistItemFilter.purchased, label: Text('Purchased')),
                ],
                selected: {selectedFilter},
                onSelectionChanged: (selection) => onFilterChanged(selection.first),
              ),
            ),
            const SizedBox(height: AppConstants.spacing3),
            Wrap(
              spacing: AppConstants.spacing2,
              runSpacing: AppConstants.spacing2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: DropdownButton<String>(
                    value: selectedSort,
                    underline: const SizedBox.shrink(),
                    icon: Icon(Icons.sort_rounded, size: 16, color: colorScheme.primary),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    items: const [
                      DropdownMenuItem(value: sortHighestRank, child: Text('Rank')),
                      DropdownMenuItem(value: sortLowestRank, child: Text('Low Rank')),
                      DropdownMenuItem(value: sortNewestAdded, child: Text('Newest')),
                    ],
                    onChanged: (value) => onSortChanged(value ?? sortHighestRank),
                  ),
                ),
                if (showRestore)
                  FilledButton.tonalIcon(
                    onPressed: onRestoreAll,
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('Restore all'),
                  ),
                if (showAdd)
                  ConstrainedBox(
                    constraints: BoxConstraints(minWidth: addButtonMinWidth),
                    child: FilledButton.icon(
                      onPressed: onAddItem,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add item'),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
