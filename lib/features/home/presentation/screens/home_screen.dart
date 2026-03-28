import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/widgets/wishiz_wordmark.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/auth/presentation/screens/account_screen.dart';
import 'package:wishiz/features/home/presentation/widgets/glassmorphic_bottom_nav.dart';
import 'package:wishiz/features/home/presentation/widgets/wishlist_summary_card.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_detail_screen.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.authRepository,
    required this.currentUser,
    this.initialWishlistId,
    this.onInitialWishlistHandled,
  });

  final WishlistRepository repository;
  final AuthRepository authRepository;
  final AppUser currentUser;
  final String? initialWishlistId;
  final VoidCallback? onInitialWishlistHandled;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _allYears = -1;

  int _currentIndex = 0;
  String _searchQuery = '';
  int _searchFieldVersion = 0;
  int _selectedYear = _allYears;
  String? _lastReminderSignature;
  String? _handledInitialWishlistId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openInitialWishlistIfNeeded();
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialWishlistId == null) {
      _handledInitialWishlistId = null;
    }
    if (oldWidget.initialWishlistId != widget.initialWishlistId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInitialWishlistIfNeeded();
      });
    }
  }

  Future<void> _openWishlistEditor({Wishlist? wishlist}) async {
    final wishlistId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WishlistEditorScreen(
          repository: widget.repository,
          wishlist: wishlist,
        ),
      ),
    );

    if (!mounted || wishlistId == null || wishlist != null) {
      return;
    }

    await _openWishlistDetails(wishlistId);
  }

  Future<void> _openWishlistDetails(
    String wishlistId, {
    bool showPurchasedOnly = false,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WishlistDetailScreen(
          repository: widget.repository,
          authRepository: widget.authRepository,
          wishlistId: wishlistId,
          showPurchasedOnly: showPurchasedOnly,
        ),
      ),
    );
  }

  Future<void> _openInitialWishlistIfNeeded() async {
    final wishlistId = widget.initialWishlistId;
    if (!mounted ||
        wishlistId == null ||
        wishlistId.isEmpty ||
        _handledInitialWishlistId == wishlistId) {
      return;
    }

    final wishlist = widget.repository.findById(wishlistId);
    _handledInitialWishlistId = wishlistId;
    widget.onInitialWishlistHandled?.call();

    if (wishlist == null) {
      _showFeedback('That shared list is not available on this device yet.');
      return;
    }

    await _openWishlistDetails(wishlistId);
  }

  Future<void> _openAccountScreen() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountScreen(
          authRepository: widget.authRepository,
        ),
      ),
    );
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  Future<void> _confirmDeleteWishlist(Wishlist wishlist) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete list?'),
        content: Text(
          'Remove "${wishlist.title}" permanently from this device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || shouldDelete != true) {
      return;
    }

    widget.repository.deleteWishlist(wishlist.id);
    _showFeedback('List deleted.');
  }

  Future<void> _shareWishlist(Wishlist wishlist) async {
    final link = _buildWishlistLink(wishlist);
    await Share.share(
      'Join my Wishiz list "${wishlist.title}" for ${wishlist.year}: $link',
      subject: wishlist.title,
    );
  }

  String _buildWishlistLink(Wishlist wishlist) {
    return 'wishiz://lists/${wishlist.id}';
  }

  Widget _buildHeader({bool showName = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: showName
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const WishizWordmark(height: 44),
                    const SizedBox(height: 4),
                    Text(
                      widget.currentUser.fullName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                )
              : const WishizWordmark(height: 44),
        ),
        IconButton(
          tooltip: 'Account',
          onPressed: _openAccountScreen,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.account_circle_outlined),
        ),
      ],
    );
  }

  Widget _buildTopCreateSection() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create a New List',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Start the next wishlist first, then browse and filter everything else below.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppConstants.spacing4),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primary,
                colorScheme.primaryContainer,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          ),
          child: ElevatedButton(
            onPressed: () => _openWishlistEditor(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(
                vertical: AppConstants.spacing4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
            child: Text(
              'Create List',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHomeTab({
    required List<Wishlist> activeWishlists,
    required List<int> availableYears,
  }) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacing4,
          AppConstants.spacing6,
          AppConstants.spacing4,
          100,
        ),
        children: [
          _buildHeader(showName: true),
          const SizedBox(height: AppConstants.spacing8),
          _buildTopCreateSection(),
          const SizedBox(height: AppConstants.spacing8),
          Text(
            'My Lists',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Search by name, narrow by year, and open only the active items you still want.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppConstants.spacing4),
          _buildSearchAndFilters(
            hintText: 'Search your lists',
            availableYears: availableYears,
          ),
          const SizedBox(height: AppConstants.spacing4),
          if (activeWishlists.isEmpty)
            _buildEmptyState(
              title: _searchQuery.isEmpty && _selectedYear == _allYears
                  ? 'No active lists yet'
                  : 'No matching lists',
              description: _searchQuery.isEmpty && _selectedYear == _allYears
                  ? 'Create your first list to start planning what comes next.'
                  : 'Try another title, another year, or clear the filters.',
            )
          else
            ...activeWishlists.map(
              (wishlist) => _buildWishlistCard(
                wishlist,
                itemCount: wishlist.activeItemCount,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCollectionTab({
    required String title,
    required String description,
    required List<Wishlist> wishlists,
    required String emptyTitle,
    required String emptyDescription,
    required List<int> availableYears,
    bool showPurchasedOnly = false,
    bool isSharedView = false,
  }) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacing4,
          AppConstants.spacing6,
          AppConstants.spacing4,
          100,
        ),
        children: [
          _buildHeader(),
          const SizedBox(height: AppConstants.spacing8),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppConstants.spacing4),
          _buildSearchAndFilters(
            hintText: 'Search $title',
            availableYears: availableYears,
          ),
          const SizedBox(height: AppConstants.spacing4),
          if (wishlists.isEmpty)
            _buildEmptyState(
              title: _searchQuery.isEmpty && _selectedYear == _allYears
                  ? emptyTitle
                  : 'No matching lists',
              description: _searchQuery.isEmpty && _selectedYear == _allYears
                  ? emptyDescription
                  : 'Try another title, another year, or clear the filters.',
            )
          else
            ...wishlists.map(
              (wishlist) => _buildWishlistCard(
                wishlist,
                itemCount: showPurchasedOnly
                    ? wishlist.purchasedItemCount
                    : wishlist.activeItemCount,
                openPurchasedOnly: showPurchasedOnly,
                isSharedView: isSharedView,
                isPastView: showPurchasedOnly,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWishlistCard(
    Wishlist wishlist, {
    required int itemCount,
    bool openPurchasedOnly = false,
    bool isSharedView = false,
    bool isPastView = false,
  }) {
    return WishlistSummaryCard(
      title: wishlist.title,
      itemCount: itemCount,
      lastUpdated: _formatRelativeDate(wishlist.updatedAt),
      coverImageUrl: wishlist.coverImageUrl,
      supportingText: _supportingTextForWishlist(
        wishlist,
        showPurchasedOnly: openPurchasedOnly,
      ),
      actions: _buildWishlistActions(
        wishlist,
        isSharedView: isSharedView,
        isPastView: isPastView,
      ),
      onTap: () => _openWishlistDetails(
        wishlist.id,
        showPurchasedOnly: openPurchasedOnly,
      ),
    );
  }

  Widget _buildRemindersTab({
    required List<_ReminderEntry> reminders,
    required List<int> availableYears,
  }) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacing4,
          AppConstants.spacing6,
          AppConstants.spacing4,
          100,
        ),
        children: [
          _buildHeader(),
          const SizedBox(height: AppConstants.spacing8),
          Text(
            'Reminders',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            widget.currentUser.notificationsEnabled
                ? 'Items appear here once they have been waiting for ${widget.currentUser.reminderDays} days or longer.'
                : 'Turn reminders back on from your account settings whenever you want the app to nudge you again.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppConstants.spacing4),
          _buildSearchAndFilters(
            hintText: 'Search reminders',
            availableYears: availableYears,
          ),
          const SizedBox(height: AppConstants.spacing4),
          if (!widget.currentUser.notificationsEnabled)
            _buildEmptyState(
              title: 'Reminders are turned off',
              description:
                  'Open the account icon in the top-right corner to enable reminder notifications and set the number of days.',
            )
          else if (reminders.isEmpty)
            _buildEmptyState(
              title: _searchQuery.isEmpty && _selectedYear == _allYears
                  ? 'No reminders yet'
                  : 'No matching reminders',
              description: _searchQuery.isEmpty && _selectedYear == _allYears
                  ? 'When saved items sit on your wishlist longer than your chosen reminder window, they will show up here.'
                  : 'Try another search term or clear the year filter.',
            )
          else
            ...reminders.map(_buildReminderCard),
        ],
      ),
    );
  }

  Widget _buildReminderCard(_ReminderEntry reminder) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacing3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reminder.item.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '${reminder.wishlist.title} · ${reminder.wishlist.year}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Saved ${reminder.daysWaiting} day${reminder.daysWaiting == 1 ? '' : 's'} ago.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (reminder.item.priceLabel != null &&
              reminder.item.priceLabel!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reminder.item.priceLabel!,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
          const SizedBox(height: AppConstants.spacing3),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _openWishlistDetails(reminder.wishlist.id),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Open List'),
              ),
              if (reminder.item.productUrl != null &&
                  reminder.item.productUrl!.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _openWishlistDetails(reminder.wishlist.id),
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: const Text('View in List'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildWishlistActions(
    Wishlist wishlist, {
    required bool isSharedView,
    required bool isPastView,
  }) {
    if (isPastView) {
      return [
        Tooltip(
          message: 'Share list',
          child: TextButton.icon(
            onPressed: () => _shareWishlist(wishlist),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share'),
          ),
        ),
      ];
    }

    final actions = <Widget>[
      Tooltip(
        message: 'Edit list',
        child: TextButton.icon(
          onPressed: () => _openWishlistEditor(wishlist: wishlist),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit'),
        ),
      ),
      Tooltip(
        message: 'Share list',
        child: TextButton.icon(
          onPressed: () => _shareWishlist(wishlist),
          icon: const Icon(Icons.share_outlined),
          label: const Text('Share'),
        ),
      ),
    ];

    if (wishlist.isShared || isSharedView) {
      actions.add(
        Tooltip(
          message: 'Manage sharing',
          child: TextButton.icon(
            onPressed: () => _openWishlistDetails(wishlist.id),
            icon: const Icon(Icons.group_outlined),
            label: const Text('Manage Sharing'),
          ),
        ),
      );
    }

    actions.add(
      Tooltip(
        message: 'Delete list',
        child: TextButton.icon(
          onPressed: () => _confirmDeleteWishlist(wishlist),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete'),
        ),
      ),
    );

    return actions;
  }

  Widget _buildSearchAndFilters({
    required String hintText,
    required List<int> availableYears,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacing4,
            vertical: 2,
          ),
          child: TextFormField(
            key: ValueKey('$hintText-$_searchFieldVersion'),
            initialValue: _searchQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              icon: const Icon(Icons.search),
              hintText: hintText,
              border: InputBorder.none,
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _searchFieldVersion += 1;
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.trim();
              });
            },
          ),
        ),
        const SizedBox(height: AppConstants.spacing3),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacing4,
            vertical: 2,
          ),
          child: DropdownButtonFormField<int>(
            value: _selectedYear,
            decoration: const InputDecoration(
              labelText: 'Filter by year',
              border: InputBorder.none,
            ),
            items: [
              const DropdownMenuItem(
                value: _allYears,
                child: Text('All years'),
              ),
              ...availableYears.map(
                (year) => DropdownMenuItem(
                  value: year,
                  child: Text(year.toString()),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedYear = value ?? _allYears;
              });
            },
          ),
        ),
      ],
    );
  }

  List<Wishlist> _filterWishlists(List<Wishlist> wishlists) {
    final query = _searchQuery.toLowerCase();

    return wishlists.where((wishlist) {
      final matchesQuery =
          query.isEmpty || wishlist.title.toLowerCase().contains(query);
      final matchesYear =
          _selectedYear == _allYears || wishlist.year == _selectedYear;
      return matchesQuery && matchesYear;
    }).toList(growable: false);
  }

  List<_ReminderEntry> _buildReminderEntries(List<Wishlist> wishlists) {
    if (!widget.currentUser.notificationsEnabled) {
      return const [];
    }

    final now = DateTime.now();
    final minimumAge = Duration(days: widget.currentUser.reminderDays);
    final reminders = <_ReminderEntry>[];

    for (final wishlist in wishlists) {
      for (final item in wishlist.activeItems) {
        final age = now.difference(item.createdAt);
        if (age < minimumAge) {
          continue;
        }

        reminders.add(
          _ReminderEntry(
            wishlist: wishlist,
            item: item,
            daysWaiting: age.inDays,
          ),
        );
      }
    }

    reminders.sort((left, right) {
      final dayComparison = right.daysWaiting.compareTo(left.daysWaiting);
      if (dayComparison != 0) {
        return dayComparison;
      }
      return left.item.rank.compareTo(right.item.rank);
    });

    return reminders;
  }

  List<_ReminderEntry> _filterReminders(List<_ReminderEntry> reminders) {
    final query = _searchQuery.toLowerCase();

    return reminders.where((reminder) {
      final matchesQuery = query.isEmpty ||
          reminder.item.title.toLowerCase().contains(query) ||
          reminder.wishlist.title.toLowerCase().contains(query);
      final matchesYear =
          _selectedYear == _allYears || reminder.wishlist.year == _selectedYear;
      return matchesQuery && matchesYear;
    }).toList(growable: false);
  }

  void _scheduleReminderPrompt(List<_ReminderEntry> reminders) {
    final signature = [
      widget.currentUser.id,
      widget.currentUser.notificationsEnabled,
      widget.currentUser.reminderDays,
      reminders.length,
    ].join('|');

    if (_lastReminderSignature == signature || reminders.isEmpty) {
      _lastReminderSignature = signature;
      return;
    }

    _lastReminderSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'You have ${reminders.length} wishlist reminder${reminders.length == 1 ? '' : 's'} ready.',
            ),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                setState(() {
                  _currentIndex = 3;
                });
              },
            ),
          ),
        );
    });
  }

  List<int> _availableYears(List<Wishlist> wishlists) {
    final years = wishlists.map((wishlist) => wishlist.year).toSet().toList()
      ..sort((left, right) => right.compareTo(left));
    return years;
  }

  String _supportingTextForWishlist(
    Wishlist wishlist, {
    required bool showPurchasedOnly,
  }) {
    final segments = <String>[
      wishlist.year.toString(),
    ];

    if (showPurchasedOnly) {
      segments.add('${wishlist.purchasedItemCount} purchased');
    } else if (wishlist.isShared && wishlist.sharedUsers.isNotEmpty) {
      segments.add('${wishlist.sharedUsers.length} members');
    }

    return segments.join(' · ');
  }

  Widget _buildEmptyState({
    required String title,
    required String description,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _formatRelativeDate(DateTime updatedAt) {
    final difference = DateTime.now().difference(updatedAt);

    if (difference.inDays >= 2) {
      return '${difference.inDays} days ago';
    }
    if (difference.inDays == 1) {
      return 'yesterday';
    }
    if (difference.inHours >= 1) {
      return '${difference.inHours}h ago';
    }
    if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m ago';
    }
    return 'just now';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Wishlist>>(
      valueListenable: widget.repository.watchWishlists(),
      builder: (context, wishlists, _) {
        final visibleWishlists = wishlists
            .where((wishlist) => !wishlist.isArchived)
            .toList(growable: false);
        final availableYears = _availableYears(visibleWishlists);
        final reminderEntries = _buildReminderEntries(visibleWishlists);
        final filteredReminders = _filterReminders(reminderEntries);
        final activeWishlists = _filterWishlists(
          visibleWishlists
              .where(
                (wishlist) =>
                    wishlist.activeItemCount > 0 || wishlist.items.isEmpty,
              )
              .toList(growable: false),
        );
        final sharedWishlists = _filterWishlists(
          visibleWishlists
              .where(
                (wishlist) =>
                    wishlist.isShared &&
                    (wishlist.activeItemCount > 0 || wishlist.items.isEmpty),
              )
              .toList(growable: false),
        );
        final pastWishlists = _filterWishlists(
          visibleWishlists
              .where((wishlist) => wishlist.purchasedItemCount > 0)
              .toList(growable: false),
        );

        _scheduleReminderPrompt(reminderEntries);

        return Scaffold(
          extendBody: true,
          body: IndexedStack(
            index: _currentIndex,
            children: [
              _buildHomeTab(
                activeWishlists: activeWishlists,
                availableYears: availableYears,
              ),
              _buildCollectionTab(
                title: 'Shared',
                description:
                    'Lists that are ready to send to other members through a share link.',
                wishlists: sharedWishlists,
                emptyTitle: 'Nothing shared yet',
                emptyDescription:
                    'Turn on sharing in a list and it will appear here.',
                availableYears: availableYears,
                isSharedView: true,
              ),
              _buildCollectionTab(
                title: 'Past Lists',
                description:
                    'Purchased items are grouped here under the original list they came from.',
                wishlists: pastWishlists,
                emptyTitle: 'No purchased items yet',
                emptyDescription:
                    'Swipe right on an item in an active list to move it here.',
                availableYears: availableYears,
                showPurchasedOnly: true,
              ),
              _buildRemindersTab(
                reminders: filteredReminders,
                availableYears: availableYears,
              ),
            ],
          ),
          bottomNavigationBar: GlassmorphicBottomNav(
            currentIndex: _currentIndex,
            reminderCount: reminderEntries.length,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
        );
      },
    );
  }
}

class _ReminderEntry {
  const _ReminderEntry({
    required this.wishlist,
    required this.item,
    required this.daysWaiting,
  });

  final Wishlist wishlist;
  final WishlistItem item;
  final int daysWaiting;
}
