import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';

class WishlistFilterBar extends StatelessWidget {
  const WishlistFilterBar({
    super.key,
    required this.hintText,
    required this.searchQuery,
    required this.searchFieldVersion,
    required this.selectedYear,
    required this.availableYears,
    required this.allYearsValue,
    required this.onSearchChanged,
    required this.onYearSelected,
    required this.onClearFilters,
  });

  final String hintText;
  final String searchQuery;
  final int searchFieldVersion;
  final int selectedYear;
  final List<int> availableYears;
  final int allYearsValue;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int> onYearSelected;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasFilters = searchQuery.isNotEmpty || selectedYear != allYearsValue;

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: TextFormField(
              key: ValueKey('$hintText-$searchFieldVersion'),
              initialValue: searchQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: colorScheme.surfaceContainerLowest,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: hintText,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacing3,
                  vertical: AppConstants.spacing3,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        visualDensity: VisualDensity.compact,
                        onPressed: onClearFilters,
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
              onChanged: onSearchChanged,
            ),
          ),
        ),
        const SizedBox(width: AppConstants.spacing2),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacing3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          ),
          child: PopupMenuButton<int>(
            tooltip: 'Filter by year',
            elevation: 0,
            padding: EdgeInsets.zero,
            menuPadding: EdgeInsets.zero,
            position: PopupMenuPosition.under,
            color: colorScheme.surfaceContainerLowest,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            ),
            onSelected: onYearSelected,
            itemBuilder: (context) => [
              PopupMenuItem<int>(
                value: allYearsValue,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacing2,
                  vertical: AppConstants.spacing1,
                ),
                child: _YearMenuItem(
                  label: 'All',
                  selected: selectedYear == allYearsValue,
                ),
              ),
              ...availableYears.map(
                (year) => PopupMenuItem<int>(
                  value: year,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacing2,
                    vertical: AppConstants.spacing1,
                  ),
                  child: _YearMenuItem(
                    label: year.toString(),
                    selected: selectedYear == year,
                  ),
                ),
              ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(selectedYear == allYearsValue ? 'All' : '$selectedYear'),
                const SizedBox(width: AppConstants.spacing2),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              ],
            ),
          ),
        ),
        if (hasFilters) ...[
          const SizedBox(width: AppConstants.spacing2),
          IconButton(
            onPressed: onClearFilters,
            tooltip: 'Clear filters',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ],
    );
  }
}

class _YearMenuItem extends StatelessWidget {
  const _YearMenuItem({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing3,
        vertical: AppConstants.spacing2,
      ),
      decoration: BoxDecoration(
        color: selected ? colorScheme.primary.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: selected ? colorScheme.primary : null,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
