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
    required this.sortCriterion,
    required this.canEdit,
    required this.showRestore,
    required this.showAdd,
    required this.onFilterChanged,
    required this.onSortChanged,
    required this.onAddItem,
    required this.onRestoreAll,
  });

  final WishlistItemFilter selectedFilter;
  final SortCriterion sortCriterion;
  final bool canEdit;
  final bool showRestore;
  final bool showAdd;
  final ValueChanged<WishlistItemFilter> onFilterChanged;
  final ValueChanged<SortCriterion> onSortChanged;
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
            Row(
              children: [
                Expanded(
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
                const SizedBox(width: AppConstants.spacing2),
                _SortButton(
                  criterion: sortCriterion,
                  onSortChanged: onSortChanged,
                ),
              ],
            ),
            if (showRestore || showAdd) ...[
              const SizedBox(height: AppConstants.spacing3),
              Wrap(
                spacing: AppConstants.spacing2,
                runSpacing: AppConstants.spacing2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
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
          ],
        );
      },
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.criterion, required this.onSortChanged});

  final SortCriterion criterion;
  final ValueChanged<SortCriterion> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDefault = criterion.isDefault;

    return OutlinedButton.icon(
      onPressed: () => _showSortSheet(context),
      icon: Icon(
        Icons.sort_rounded,
        size: 16,
        color: isDefault ? colorScheme.onSurfaceVariant : colorScheme.primary,
      ),
      label: Text(criterion.label),
      style: OutlinedButton.styleFrom(
        foregroundColor: isDefault ? colorScheme.onSurfaceVariant : colorScheme.primary,
        side: BorderSide(
          color: isDefault
              ? colorScheme.outlineVariant
              : colorScheme.primary.withOpacity(0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusXl)),
      ),
      builder: (_) => _SortSheet(
        current: criterion,
        onSortChanged: (c) {
          onSortChanged(c);
          Navigator.of(context).pop();
        },
        onDirectionToggled: onSortChanged,
      ),
    );
  }
}

class _SortSheet extends StatefulWidget {
  const _SortSheet({
    required this.current,
    required this.onSortChanged,
    required this.onDirectionToggled,
  });

  final SortCriterion current;
  final ValueChanged<SortCriterion> onSortChanged;
  final ValueChanged<SortCriterion> onDirectionToggled;

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late SortCriterion _current;

  @override
  void initState() {
    super.initState();
    _current = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.pagePadding,
          AppConstants.spacing2,
          AppConstants.pagePadding,
          AppConstants.pagePadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppConstants.spacing4),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Sort by', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppConstants.spacing3),
            ...SortField.values.map((field) {
              final isSelected = _current.field == field;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                title: Text(_fieldLabel(field)),
                trailing: isSelected
                    ? _DirectionToggle(
                        field: field,
                        ascending: _current.ascending,
                        onToggle: () {
                          final next = _current.copyWith(ascending: !_current.ascending);
                          setState(() => _current = next);
                          widget.onDirectionToggled(next);
                        },
                      )
                    : null,
                onTap: () => _selectField(field),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _selectField(SortField field) {
    final next = _current.field == field
        ? _current
        : SortCriterion.defaultFor(field);
    setState(() => _current = next);
    widget.onSortChanged(next);
  }

  String _fieldLabel(SortField field) => switch (field) {
    SortField.rank => 'Rank',
    SortField.price => 'Price',
    SortField.dateAdded => 'Date Added',
  };
}

class _DirectionToggle extends StatelessWidget {
  const _DirectionToggle({
    required this.field,
    required this.ascending,
    required this.onToggle,
  });

  final SortField field;
  final bool ascending;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dirLabel = switch (field) {
      SortField.dateAdded => ascending ? 'Oldest first' : 'Newest first',
      _ => ascending ? 'Low → High' : 'High → Low',
    };

    return TextButton.icon(
      onPressed: onToggle,
      icon: Icon(
        ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
        size: 16,
        color: colorScheme.primary,
      ),
      label: Text(
        dirLabel,
        style: TextStyle(color: colorScheme.primary, fontSize: 13),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
