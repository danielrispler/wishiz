import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/wishlists/screens/wishlist_detail/wishlist_item_sort.dart';

export 'package:wishiz/features/wishlists/screens/wishlist_detail/wishlist_item_sort.dart'
    show SortField, SortCriterion;

enum WishlistItemFilter { all, active, purchased }

class WishlistItemControls extends StatelessWidget {
  const WishlistItemControls({
    super.key,
    required this.selectedFilter,
    required this.sortCriteria,
    required this.canEdit,
    required this.showRestore,
    required this.showAdd,
    required this.onFilterChanged,
    required this.onSortCriteriaChanged,
    required this.onAddItem,
    required this.onRestoreAll,
  });

  static const List<SortCriterion> defaultSortCriteria = [
    SortCriterion(SortField.rank),
  ];

  final WishlistItemFilter selectedFilter;
  final List<SortCriterion> sortCriteria;
  final bool canEdit;
  final bool showRestore;
  final bool showAdd;
  final ValueChanged<WishlistItemFilter> onFilterChanged;
  final ValueChanged<List<SortCriterion>> onSortCriteriaChanged;
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
                _SortChipsRow(
                  criteria: sortCriteria,
                  onChanged: onSortCriteriaChanged,
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

class _SortChipsRow extends StatelessWidget {
  const _SortChipsRow({required this.criteria, required this.onChanged});

  final List<SortCriterion> criteria;
  final ValueChanged<List<SortCriterion>> onChanged;

  static const _allFields = SortField.values;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppConstants.spacing2,
      runSpacing: AppConstants.spacing2,
      children: _allFields.map((field) {
        final index = criteria.indexWhere((c) => c.field == field);
        final isSelected = index >= 0;
        final criterion = isSelected ? criteria[index] : null;
        final badge = isSelected && criteria.length > 1 ? '${index + 1}' : null;

        return GestureDetector(
          onLongPress: isSelected
              ? () {
                  final next = List<SortCriterion>.from(criteria)..removeAt(index);
                  onChanged(next.isEmpty ? WishlistItemControls.defaultSortCriteria : next);
                }
              : null,
          child: _SortChip(
            field: field,
            isSelected: isSelected,
            ascending: criterion?.ascending ?? true,
            badge: badge,
            onTap: () => _handleTap(field, index, isSelected, criterion),
          ),
        );
      }).toList(),
    );
  }

  void _handleTap(SortField field, int index, bool isSelected, SortCriterion? criterion) {
    if (isSelected) {
      final next = List<SortCriterion>.from(criteria);
      next[index] = criterion!.toggleDirection();
      onChanged(next);
    } else {
      onChanged([...criteria, SortCriterion(field)]);
    }
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.field,
    required this.isSelected,
    required this.ascending,
    required this.onTap,
    this.badge,
  });

  final SortField field;
  final bool isSelected;
  final bool ascending;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = switch (field) {
      SortField.rank => 'Rank',
      SortField.price => 'Price',
      SortField.dateAdded => 'Date',
    };
    final directionIcon = ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;

    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (isSelected) ...[
            const SizedBox(width: 4),
            Icon(directionIcon, size: 14, color: colorScheme.primary),
          ],
          if (badge != null) ...[
            const SizedBox(width: 4),
            Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
      onSelected: (_) => onTap(),
      showCheckmark: false,
    );
  }
}
