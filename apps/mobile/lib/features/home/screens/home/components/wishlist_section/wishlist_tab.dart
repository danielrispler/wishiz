import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/shared/widgets/wishlist_analytics_sheet.dart';
import 'package:wishiz/features/home/screens/home/components/wishlist_section/wishlist_summary_card.dart';
import '../empty_wishlist_state.dart';
import '../wishlist_filter_bar.dart';

class HomeTabContent extends StatelessWidget {
  const HomeTabContent({
    super.key,
    required this.activeWishlists,
    required this.availableYears,
    required this.reminderCount,
    required this.sharedCount,
    required this.searchQuery,
    required this.searchFieldVersion,
    required this.selectedYear,
    required this.allYearsValue,
    required this.isSearchEmpty,
    required this.onSearchChanged,
    required this.onYearSelected,
    required this.onClearFilters,
    required this.onNewList,
    required this.onOpenReminders,
    required this.onOpenWishlist,
    required this.importQueueWidget,
  });

  final List<Wishlist> activeWishlists;
  final List<int> availableYears;
  final int reminderCount;
  final int sharedCount;
  final String searchQuery;
  final int searchFieldVersion;
  final int selectedYear;
  final int allYearsValue;
  final bool isSearchEmpty;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int> onYearSelected;
  final VoidCallback onClearFilters;
  final VoidCallback onNewList;
  final VoidCallback onOpenReminders;
  final void Function(String wishlistId) onOpenWishlist;
  final Widget importQueueWidget;

  @override
  Widget build(BuildContext context) {
    return _ScrollableTab(
      children: [
        _HomeHeader(
          activeCount: activeWishlists.length,
          sharedCount: sharedCount,
          reminderCount: reminderCount,
          onNew: onNewList,
          onReminders: onOpenReminders,
        ),
        importQueueWidget,
        WishlistFilterBar(
          hintText: 'Search your lists',
          searchQuery: searchQuery,
          searchFieldVersion: searchFieldVersion,
          selectedYear: selectedYear,
          availableYears: availableYears,
          allYearsValue: allYearsValue,
          onSearchChanged: onSearchChanged,
          onYearSelected: onYearSelected,
          onClearFilters: onClearFilters,
        ),
        if (activeWishlists.isEmpty)
          EmptyWishlistState(
            title: isSearchEmpty ? 'No active lists yet' : 'No matching lists',
            description: isSearchEmpty
                ? 'Create your first list to start planning what comes next.'
                : 'Try another title, another year, or clear the filters.',
            actionLabel: isSearchEmpty ? 'Create a list' : 'Clear filters',
            onAction: isSearchEmpty ? onNewList : onClearFilters,
          )
        else
          ...activeWishlists.map(
            (wishlist) => _WishlistCard(
              wishlist: wishlist,
              itemCount: wishlist.activeItemCount,
              onTap: () => onOpenWishlist(wishlist.id),
            ),
          ),
      ],
    );
  }
}

class SharedTabContent extends StatelessWidget {
  const SharedTabContent({
    super.key,
    required this.wishlists,
    required this.availableYears,
    required this.searchQuery,
    required this.searchFieldVersion,
    required this.selectedYear,
    required this.allYearsValue,
    required this.isSearchEmpty,
    required this.summaryLabel,
    required this.onSearchChanged,
    required this.onYearSelected,
    required this.onClearFilters,
    required this.onNewList,
    required this.onOpenWishlist,
  });

  final List<Wishlist> wishlists;
  final List<int> availableYears;
  final String searchQuery;
  final int searchFieldVersion;
  final int selectedYear;
  final int allYearsValue;
  final bool isSearchEmpty;
  final String summaryLabel;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int> onYearSelected;
  final VoidCallback onClearFilters;
  final VoidCallback onNewList;
  final void Function(String wishlistId) onOpenWishlist;

  @override
  Widget build(BuildContext context) {
    return _ScrollableTab(
      children: [
        _CollectionHeader(
          title: 'Shared',
          summaryLabel: summaryLabel,
        ),
        WishlistFilterBar(
          hintText: 'Search Shared',
          searchQuery: searchQuery,
          searchFieldVersion: searchFieldVersion,
          selectedYear: selectedYear,
          availableYears: availableYears,
          allYearsValue: allYearsValue,
          onSearchChanged: onSearchChanged,
          onYearSelected: onYearSelected,
          onClearFilters: onClearFilters,
        ),
        if (wishlists.isEmpty)
          EmptyWishlistState(
            title: isSearchEmpty ? 'Nothing shared yet' : 'No matching lists',
            description: isSearchEmpty
                ? 'Invite collaborators to a list, or join one using a share link.'
                : 'Try another title, another year, or clear the filters.',
            actionLabel: isSearchEmpty ? 'Create a list' : 'Clear filters',
            onAction: isSearchEmpty ? onNewList : onClearFilters,
          )
        else
          ...wishlists.map(
            (wishlist) => _WishlistCard(
              wishlist: wishlist,
              itemCount: wishlist.activeItemCount,
              isSharedView: true,
              onTap: () => onOpenWishlist(wishlist.id),
            ),
          ),
      ],
    );
  }
}

class _ScrollableTab extends StatelessWidget {
  const _ScrollableTab({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final horizontalPadding = compact ? AppConstants.pagePadding : 32.0;

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                AppConstants.spacing2,
                horizontalPadding,
                120,
              ),
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppConstants.spacing4),
                  children[i],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.activeCount,
    required this.sharedCount,
    required this.reminderCount,
    required this.onNew,
    required this.onReminders,
  });

  final int activeCount;
  final int sharedCount;
  final int reminderCount;
  final VoidCallback onNew;
  final VoidCallback onReminders;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lists', style: textTheme.headlineSmall),
              const SizedBox(height: AppConstants.spacing1),
              Text(
                reminderCount > 0
                    ? '$activeCount active · $sharedCount shared · $reminderCount reminders'
                    : '$activeCount active · $sharedCount shared',
                style: textTheme.labelMedium,
              ),
            ],
          ),
        ),
        if (reminderCount > 0)
          IconButton(
            onPressed: onReminders,
            icon: const Icon(Icons.notifications_outlined),
            visualDensity: VisualDensity.compact,
            tooltip: 'Reminders',
          ),
        const SizedBox(width: AppConstants.spacing2),
        FilledButton(onPressed: onNew, child: const Text('New')),
      ],
    );
  }
}

class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({required this.title, required this.summaryLabel});

  final String title;
  final String summaryLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppConstants.spacing1),
        Text(summaryLabel, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _WishlistCard extends StatelessWidget {
  const _WishlistCard({
    required this.wishlist,
    required this.itemCount,
    required this.onTap,
    this.isSharedView = false,
  });

  final Wishlist wishlist;
  final int itemCount;
  final VoidCallback onTap;
  final bool isSharedView;

  @override
  Widget build(BuildContext context) {
    final analytics = WishlistAnalytics(wishlist);
    final segments = <String>[wishlist.year.toString()];
    if (isSharedView && wishlist.members.isNotEmpty) {
      segments.add('${wishlist.members.length} members');
    }

    return WishlistSummaryCard(
      title: wishlist.title,
      itemCount: itemCount,
      coverImageUrl: wishlist.coverImageUrl,
      supportingText: segments.join(' · '),
      totalValue: analytics.totalActiveValue,
      onTap: onTap,
    );
  }
}
