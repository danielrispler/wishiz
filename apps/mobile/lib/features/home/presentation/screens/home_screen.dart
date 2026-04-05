import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/navigation/wishiz_share_text.dart';
import 'package:wishiz/core/utils/currency_utils.dart';
import 'package:wishiz/core/utils/error_utils.dart';
import 'package:wishiz/core/widgets/wishiz_wordmark.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/auth/presentation/screens/account_screen.dart';
import 'package:wishiz/features/home/presentation/widgets/glassmorphic_bottom_nav.dart';
import 'package:wishiz/features/home/presentation/widgets/wishlist_summary_card.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_detail_screen.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_editor_screen.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_item_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.sharedProductRepository,
    required this.authRepository,
    required this.currentUser,
    this.initialWishlistId,
    this.initialSharedText,
    this.onInitialWishlistHandled,
    this.onInitialSharedTextHandled,
  });

  final WishlistRepository repository;
  final SharedProductRepository sharedProductRepository;
  final AuthRepository authRepository;
  final AppUser currentUser;
  final String? initialWishlistId;
  final String? initialSharedText;
  final VoidCallback? onInitialWishlistHandled;
  final VoidCallback? onInitialSharedTextHandled;

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
  String? _handledInitialSharedText;
  bool _isImportingSharedProduct = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingEntryPoints();
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialWishlistId == null) {
      _handledInitialWishlistId = null;
    }
    if (widget.initialSharedText == null) {
      _handledInitialSharedText = null;
    }
    if (oldWidget.initialWishlistId != widget.initialWishlistId ||
        oldWidget.initialSharedText != widget.initialSharedText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handlePendingEntryPoints();
      });
    }
  }

  Future<String?> _openWishlistEditor({
    Wishlist? wishlist,
    bool openDetailsOnCreate = true,
  }) async {
    final wishlistId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WishlistEditorScreen(
          repository: widget.repository,
          wishlist: wishlist,
        ),
      ),
    );

    if (!mounted || wishlistId == null) {
      return wishlistId;
    }

    if (wishlist == null && openDetailsOnCreate) {
      await _openWishlistDetails(wishlistId);
    }

    return wishlistId;
  }

  Future<void> _openWishlistDetails(
    String wishlistId, {
    bool showPurchasedOnly = false,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WishlistDetailScreen(
          repository: widget.repository,
          sharedProductRepository: widget.sharedProductRepository,
          authRepository: widget.authRepository,
          wishlistId: wishlistId,
          showPurchasedOnly: showPurchasedOnly,
        ),
      ),
    );
  }

  Future<void> _handlePendingEntryPoints() async {
    final handledSharedImport = await _openInitialSharedImportIfNeeded();
    if (handledSharedImport) {
      return;
    }

    await _openInitialWishlistIfNeeded();
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

  Future<bool> _openInitialSharedImportIfNeeded() async {
    final sharedText = widget.initialSharedText;
    if (!mounted ||
        sharedText == null ||
        sharedText.isEmpty ||
        _handledInitialSharedText == sharedText ||
        _isImportingSharedProduct) {
      return false;
    }

    setState(() {
      _handledInitialSharedText = sharedText;
      _isImportingSharedProduct = true;
    });
    widget.onInitialSharedTextHandled?.call();

    try {
      final draft = await _resolveSharedProductDraft(sharedText);
      if (!mounted) {
        return true;
      }

      if (draft == null) {
        _showFeedback('Wishiz could not find a product link in that share.');
        return true;
      }

      final wishlistId = await _selectWishlistForSharedImport();
      if (!mounted || wishlistId == null) {
        return true;
      }

      if (!draft.hasCompleteRequiredFields) {
        final missingFields = draft.missingFieldLabels.join(', ');
        _showFeedback(
          'Sorry, we could only fill part of this product. Please add the missing $missingFields before saving.',
        );
      }

      await _openSharedProductEditor(wishlistId: wishlistId, draft: draft);
      return true;
    } finally {
      if (mounted) {
        setState(() {
          _isImportingSharedProduct = false;
        });
      }
    }
  }

  Future<SharedProductDraft?> _resolveSharedProductDraft(
    String sharedText,
  ) async {
    try {
      return await widget.sharedProductRepository.createDraftFromSharedText(
        sharedText,
      );
    } catch (error) {
      if (mounted) {
        _showFeedback(
          formatErrorMessage(
            error,
            fallbackMessage: 'Could not import that shared product yet.',
          ),
        );
      }
      return null;
    }
  }

  Future<String?> _selectWishlistForSharedImport() async {
    final wishlists = widget.repository
        .getWishlists()
        .where((wishlist) => !wishlist.isArchived)
        .toList(growable: false);

    if (wishlists.isEmpty) {
      _showFeedback('Create a wishlist first so Wishiz can save this product.');
      return _openWishlistEditor(openDetailsOnCreate: false);
    }

    if (wishlists.length == 1) {
      return wishlists.single.id;
    }

    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a wishlist'),
        children: [
          for (final wishlist in wishlists)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(wishlist.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(wishlist.title),
                  const SizedBox(height: 4),
                  Text(
                    '${wishlist.year} · ${wishlist.activeItemCount} active items',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openSharedProductEditor({
    required String wishlistId,
    required SharedProductDraft draft,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WishlistItemEditorScreen(
          repository: widget.repository,
          wishlistId: wishlistId,
          sharedProductRepository: widget.sharedProductRepository,
          preferredCurrencyCode: widget.currentUser.preferredCurrencyCode,
          preferredCurrencySymbol: widget.currentUser.preferredCurrencySymbol,
          initialTitle: draft.title,
          initialNotes: draft.notes,
          initialPriceLabel: draft.priceLabel,
          initialImageUrl: draft.imageUrl,
          initialProductUrl: draft.productUrl,
          isSharedImport: true,
        ),
      ),
    );
  }

  Future<void> _openAccountScreen() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountScreen(authRepository: widget.authRepository),
      ),
    );
  }

  void _openRemindersTab() {
    setState(() {
      _currentIndex = 3;
    });
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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

    try {
      await widget.repository.deleteWishlist(wishlist.id);
      _showFeedback('List deleted.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showFeedback(
        formatErrorMessage(
          error,
          fallbackMessage: 'Could not delete this list.',
        ),
      );
    }
  }

  Future<void> _shareWishlist(Wishlist wishlist) async {
    await SharePlus.instance.share(
      ShareParams(
        text: WishizShareText.buildWishlistShareText(wishlist: wishlist),
        subject: wishlist.title,
      ),
    );
  }

  Widget _buildHeader({bool showName = false, required int reminderCount}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: showName
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Transform.translate(
                      offset: const Offset(-8, 0),
                      child: const WishizWordmark(height: 35),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.currentUser.fullName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                )
              : Transform.translate(
                  offset: const Offset(-8, 0),
                  child: const WishizWordmark(height: 44),
                ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Reminders',
              onPressed: _openRemindersTab,
              visualDensity: VisualDensity.compact,
              color: _currentIndex == 3
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              icon: const Icon(Icons.notifications_outlined),
            ),
            if (reminderCount > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
                  ),
                  child: Text(
                    reminderCount > 9 ? '9+' : '$reminderCount',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
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
        if (_isImportingSharedProduct)
          Container(
            margin: const EdgeInsets.only(bottom: AppConstants.itemGap),
            padding: const EdgeInsets.all(AppConstants.cardPadding),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Importing product details...',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        Text(
          'Create a New List',
          style: Theme.of(context).textTheme.titleLarge,
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
              colors: [colorScheme.primary, colorScheme.primaryContainer],
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
    required int reminderCount,
  }) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.pagePadding,
          AppConstants.pagePadding,
          AppConstants.pagePadding,
          120,
        ),
        children: [
          _buildHeader(showName: true, reminderCount: reminderCount),
          const SizedBox(height: AppConstants.spacing5),
          _buildTopCreateSection(),
          const SizedBox(height: AppConstants.spacing5),
          Text('My Lists', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Search by name, narrow by year, and open only the active items you still want.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppConstants.spacing3),
          _buildSearchAndFilters(
            hintText: 'Search your lists',
            availableYears: availableYears,
          ),
          const SizedBox(height: AppConstants.sectionGap),
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
    required int reminderCount,
    bool showPurchasedOnly = false,
    bool isSharedView = false,
  }) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.pagePadding,
          AppConstants.pagePadding,
          AppConstants.pagePadding,
          120,
        ),
        children: [
          _buildHeader(reminderCount: reminderCount),
          const SizedBox(height: AppConstants.sectionGap),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppConstants.spacing4),
          _buildSearchAndFilters(
            hintText: 'Search $title',
            availableYears: availableYears,
          ),
          const SizedBox(height: AppConstants.sectionGap),
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
    required int reminderCount,
  }) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.pagePadding,
          AppConstants.pagePadding,
          AppConstants.pagePadding,
          120,
        ),
        children: [
          _buildHeader(reminderCount: reminderCount),
          const SizedBox(height: AppConstants.sectionGap),
          Text('Reminders', style: Theme.of(context).textTheme.headlineSmall),
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
          const SizedBox(height: AppConstants.sectionGap),
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
      margin: const EdgeInsets.only(bottom: AppConstants.itemGap),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.cardPadding),
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
              CurrencyUtils.convertPriceLabel(
                    reminder.item.priceLabel,
                    targetCurrencyCode:
                        widget.currentUser.preferredCurrencyCode,
                  ) ??
                  reminder.item.priceLabel!,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
          const SizedBox(height: AppConstants.sectionGap),
          Wrap(
            spacing: AppConstants.spacing2,
            runSpacing: AppConstants.spacing2,
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
            horizontal: AppConstants.cardPadding,
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
        const SizedBox(height: AppConstants.itemGap),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.cardPadding,
            vertical: 2,
          ),
          child: DropdownButtonFormField<int>(
            initialValue: _selectedYear,
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
                (year) =>
                    DropdownMenuItem(value: year, child: Text(year.toString())),
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

    return wishlists
        .where((wishlist) {
          final matchesQuery =
              query.isEmpty || wishlist.title.toLowerCase().contains(query);
          final matchesYear =
              _selectedYear == _allYears || wishlist.year == _selectedYear;
          return matchesQuery && matchesYear;
        })
        .toList(growable: false);
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

    return reminders
        .where((reminder) {
          final matchesQuery =
              query.isEmpty ||
              reminder.item.title.toLowerCase().contains(query) ||
              reminder.wishlist.title.toLowerCase().contains(query);
          final matchesYear =
              _selectedYear == _allYears ||
              reminder.wishlist.year == _selectedYear;
          return matchesQuery && matchesYear;
        })
        .toList(growable: false);
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
    final segments = <String>[wishlist.year.toString()];

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
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppConstants.spacing2),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
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

        return Stack(
          children: [
            Scaffold(
              extendBody: true,
              body: IndexedStack(
                index: _currentIndex,
                children: [
                  _buildHomeTab(
                    activeWishlists: activeWishlists,
                    availableYears: availableYears,
                    reminderCount: reminderEntries.length,
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
                    reminderCount: reminderEntries.length,
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
                    reminderCount: reminderEntries.length,
                    showPurchasedOnly: true,
                  ),
                  _buildRemindersTab(
                    reminders: filteredReminders,
                    availableYears: availableYears,
                    reminderCount: reminderEntries.length,
                  ),
                ],
              ),
              bottomNavigationBar: GlassmorphicBottomNav(
                currentIndex: _currentIndex,
                onTap: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
              ),
            ),
            if (_isImportingSharedProduct) const _SharedImportLoader(),
          ],
        );
      },
    );
  }
}

class _SharedImportLoader extends StatelessWidget {
  const _SharedImportLoader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: Colors.black45,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(AppConstants.sectionGap),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppConstants.itemGap),
              Text(
                'Preparing shared item...',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
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
