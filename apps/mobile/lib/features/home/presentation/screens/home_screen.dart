import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/navigation/wishiz_share_text.dart';
import 'package:wishiz/core/utils/error_utils.dart';
import 'package:wishiz/core/widgets/wishiz_app_bar.dart';

import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/auth/presentation/screens/account_screen.dart';
import 'package:wishiz/features/home/presentation/screens/reminders_screen.dart';
import 'package:wishiz/features/home/presentation/widgets/glassmorphic_bottom_nav.dart';
import 'package:wishiz/features/home/presentation/widgets/wishlist_summary_card.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';
import 'package:wishiz/features/product_imports/domain/product_import_repository.dart';
import 'package:wishiz/features/product_imports/presentation/widgets/import_queue_view.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_detail_screen.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_editor_screen.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_item_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.productImportRepository,
    required this.sharedProductRepository,
    required this.authRepository,
    required this.currentUser,
    this.initialWishlistId,
    this.initialInviteToken,
    this.initialSharedText,
    this.onInitialWishlistHandled,
    this.onInitialSharedTextHandled,
  });

  final WishlistRepository repository;
  final ProductImportRepository productImportRepository;
  final SharedProductRepository sharedProductRepository;
  final AuthRepository authRepository;
  final AppUser currentUser;
  final String? initialWishlistId;
  final String? initialInviteToken;
  final String? initialSharedText;
  final VoidCallback? onInitialWishlistHandled;
  final VoidCallback? onInitialSharedTextHandled;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _allYears = -1;
  static const Uuid _uuid = Uuid();

  int _currentIndex = 0;
  String _searchQuery = '';
  int _searchFieldVersion = 0;
  int _selectedYear = _allYears;
  String? _lastReminderSignature;
  String? _handledInitialWishlistId;
  String? _handledInitialSharedText;
  bool _isImportingSharedProduct = false;
  bool _isPolling = false;
  Timer? _pollTimer;
  late final ValueListenable<List<Wishlist>> _wishlistsListenable;

  @override
  void initState() {
    super.initState();
    _wishlistsListenable = widget.repository.watchWishlists();
    _wishlistsListenable.addListener(_onWishlistsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingEntryPoints();
      _onWishlistsChanged();
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
        oldWidget.initialInviteToken != widget.initialInviteToken ||
        oldWidget.initialSharedText != widget.initialSharedText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handlePendingEntryPoints();
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _wishlistsListenable.removeListener(_onWishlistsChanged);
    super.dispose();
  }

  bool _isShared(Wishlist wishlist) {
    final userId = widget.currentUser.id;
    if (wishlist.ownerUserId == userId) {
      return wishlist.members.isNotEmpty || wishlist.invites.isNotEmpty;
    }
    return wishlist.members.any((m) => m.userId == userId);
  }

  void _updateSharedTabPolling(int index) {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (index == 1) {
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    }
  }

  Future<void> _poll() async {
    if (_isPolling) return;
    _isPolling = true;
    try {
      await widget.repository.refresh();
    } catch (_) {
      // Ignore poll errors silently.
    } finally {
      _isPolling = false;
    }
  }

  void _onWishlistsChanged() {
    if (!mounted) return;
    final count = _reminderCount(
      _wishlistsListenable.value
          .where((w) => !w.isArchived)
          .toList(growable: false),
    );
    _scheduleReminderPrompt(count);
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

    var wishlist = widget.repository.findById(wishlistId);
    _handledInitialWishlistId = wishlistId;
    widget.onInitialWishlistHandled?.call();

    if (wishlist == null) {
      final inviteToken = widget.initialInviteToken?.trim();
      if (inviteToken == null || inviteToken.isEmpty) {
        _showFeedback('This invite link is missing an invite token.');
        return;
      }

      try {
        wishlist = await widget.repository.joinWishlist(
          id: wishlistId,
          token: inviteToken,
        );
      } catch (e, stackTrace) {
        debugPrint('Failed to join wishlist: $e\n$stackTrace');
        if (!mounted) return;
        _showFeedback('Failed to join list: $e');
        return;
      }
    }

    if (!mounted || wishlist == null) {
      if (mounted) {
        _showFeedback('That shared list is not available on this device yet.');
      }
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
      await widget.productImportRepository.enqueue(
        sharedText: sharedText,
        clientRequestId: _uuid.v4(),
        targetCurrencyCode: widget.currentUser.preferredCurrencyCode,
      );
      if (!mounted) {
        return true;
      }
      _showFeedback('Processing shared item. Check the queue to assign it.');
      return true;
    } catch (error) {
      if (mounted) {
        _showFeedback(
          formatErrorMessage(
            error,
            fallbackMessage: 'Could not queue that shared product yet.',
          ),
        );
      }
      return true;
    } finally {
      if (mounted) {
        setState(() {
          _isImportingSharedProduct = false;
        });
      }
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

  Future<bool?> _openSharedProductEditor({
    required String wishlistId,
    required SharedProductDraft draft,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
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

  Future<void> _openRemindersScreen() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RemindersScreen(authRepository: widget.authRepository),
      ),
    );
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

  List<Widget> _buildHeaderActions({required int reminderCount}) {
    final colorScheme = Theme.of(context).colorScheme;

    return [
      Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: 'Reminders',
            onPressed: _openRemindersScreen,
            visualDensity: VisualDensity.compact,
            color: colorScheme.onSurfaceVariant,
            icon: const Icon(Icons.notifications_outlined),
          ),
          if (reminderCount > 0)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
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
    ];
  }

  Widget _buildImportQueue() {
    return ImportQueueView(
      repository: widget.productImportRepository,
      isQueueing: _isImportingSharedProduct,
      onOpenWishlist: (job) {
        if (job.wishlistId != null) _openWishlistDetails(job.wishlistId!);
      },
      onAssign: _assignImportJobToWishlist,
      onReview: _openImportJobEditor,
      onRetry: _retryImportJob,
      onAcknowledge: _acknowledgeImportJob,
    );
  }

  Future<void> _retryImportJob(ProductImportJob job) async {
    try {
      await widget.productImportRepository.retry(job.id);
      _showFeedback('Import retry queued.');
    } catch (error) {
      if (!mounted) return;
      _showFeedback(
        formatErrorMessage(error, fallbackMessage: 'Could not retry import.'),
      );
    }
  }

  Future<void> _acknowledgeImportJob(ProductImportJob job) async {
    try {
      await widget.productImportRepository.acknowledge(job.id);
    } catch (error) {
      if (!mounted) return;
      _showFeedback(
        formatErrorMessage(error, fallbackMessage: 'Could not hide import.'),
      );
    }
  }

  Future<void> _assignImportJobToWishlist(ProductImportJob job) async {
    final wishlistId = await _selectWishlistForSharedImport();
    if (!mounted || wishlistId == null) return;
    try {
      await widget.productImportRepository.assign(job.id, wishlistId);
      final wishlist = widget.repository.findById(wishlistId);
      final name = wishlist?.title ?? 'list';
      if (mounted) _showFeedback('Added to $name.');
    } catch (error) {
      if (!mounted) return;
      _showFeedback(
        formatErrorMessage(error, fallbackMessage: 'Could not assign import.'),
      );
    }
  }

  Future<void> _openImportJobEditor(ProductImportJob job) async {
    String? wishlistId = job.wishlistId;
    if (wishlistId == null) {
      wishlistId = await _selectWishlistForSharedImport();
      if (!mounted || wishlistId == null) return;
    }
    final success = await _openSharedProductEditor(
      wishlistId: wishlistId,
      draft: SharedProductDraft(
        productUrl: job.normalizedUrl,
        title: job.title,
        priceLabel: job.priceLabel,
        imageUrl: job.imageUrl,
      ),
    );

    if (success == true) {
      await _acknowledgeImportJob(job);
    }
  }

  Widget _buildHomeTab({
    required List<Wishlist> activeWishlists,
    required List<int> availableYears,
    required int reminderCount,
    required int sharedCount,
  }) {
    return _buildScrollableTab(
      children: [
        _buildHomeHeader(
          activeCount: activeWishlists.length,
          sharedCount: sharedCount,
          reminderCount: reminderCount,
        ),
        _buildImportQueue(),
        _buildSearchAndFilters(
          hintText: 'Search your lists',
          availableYears: availableYears,
        ),
        if (activeWishlists.isEmpty)
          _buildEmptyState(
            title: _searchQuery.isEmpty && _selectedYear == _allYears
                ? 'No active lists yet'
                : 'No matching lists',
            description: _searchQuery.isEmpty && _selectedYear == _allYears
                ? 'Create your first list to start planning what comes next.'
                : 'Try another title, another year, or clear the filters.',
            actionLabel: _searchQuery.isEmpty && _selectedYear == _allYears
                ? 'Create a list'
                : 'Clear filters',
            onAction: _searchQuery.isEmpty && _selectedYear == _allYears
                ? () => _openWishlistEditor()
                : _clearFilters,
          )
        else
          ...activeWishlists.map(
            (wishlist) => _buildWishlistCard(
              wishlist,
              itemCount: wishlist.activeItemCount,
            ),
          ),
      ],
    );
  }

  Widget _buildCollectionTab({
    required String title,
    required String description,
    required List<Wishlist> wishlists,
    required String emptyTitle,
    required String emptyDescription,
    required List<int> availableYears,
    required String summaryLabel,
    bool showPurchasedOnly = false,
    bool isSharedView = false,
  }) {
    return _buildScrollableTab(
      children: [
        _buildCollectionHeader(
          title: title,
          description: description,
          summaryLabel: summaryLabel,
        ),
        _buildSearchAndFilters(
          hintText: 'Search $title',
          availableYears: availableYears,
        ),
        if (wishlists.isEmpty)
          _buildEmptyState(
            title: _searchQuery.isEmpty && _selectedYear == _allYears
                ? emptyTitle
                : 'No matching lists',
            description: _searchQuery.isEmpty && _selectedYear == _allYears
                ? emptyDescription
                : 'Try another title, another year, or clear the filters.',
            actionLabel:
                _searchQuery.isEmpty &&
                    _selectedYear == _allYears &&
                    isSharedView
                ? 'Create a list'
                : 'Clear filters',
            onAction:
                _searchQuery.isEmpty &&
                    _selectedYear == _allYears &&
                    isSharedView
                ? () => _openWishlistEditor()
                : _clearFilters,
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
            ),
          ),
      ],
    );
  }

  Widget _buildScrollableTab({required List<Widget> children}) {
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
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0) const SizedBox(height: AppConstants.spacing4),
                  children[index],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHomeHeader({
    required int activeCount,
    required int sharedCount,
    required int reminderCount,
  }) {
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
            onPressed: _openRemindersScreen,
            icon: const Icon(Icons.notifications_outlined),
            visualDensity: VisualDensity.compact,
            tooltip: 'Reminders',
          ),
        const SizedBox(width: AppConstants.spacing2),
        FilledButton(
          onPressed: () => _openWishlistEditor(),
          child: const Text('New'),
        ),
      ],
    );
  }

  Widget _buildCollectionHeader({
    required String title,
    required String description,
    required String summaryLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppConstants.spacing1),
        Text(summaryLabel, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }

  Widget _buildWishlistCard(
    Wishlist wishlist, {
    required int itemCount,
    bool openPurchasedOnly = false,
    bool isSharedView = false,
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
      actions: _buildWishlistActions(wishlist, isSharedView: isSharedView),
      onTap: () => _openWishlistDetails(
        wishlist.id,
        showPurchasedOnly: openPurchasedOnly,
      ),
    );
  }

  List<Widget> _buildWishlistActions(
    Wishlist wishlist, {
    required bool isSharedView,
  }) {
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

    if (!isSharedView) {
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
    }

    return actions;
  }

  Widget _buildSearchAndFilters({
    required String hintText,
    required List<int> availableYears,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasFilters = _searchQuery.isNotEmpty || _selectedYear != _allYears;

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: TextFormField(
              key: ValueKey('$hintText-$_searchFieldVersion'),
              initialValue: _searchQuery,
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
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchFieldVersion += 1;
                          });
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim();
                });
              },
            ),
          ),
        ),
        const SizedBox(width: AppConstants.spacing2),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacing3,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedYear,
              borderRadius: BorderRadius.circular(AppConstants.radiusXl),
              items: [
                const DropdownMenuItem(value: _allYears, child: Text('All')),
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
        ),
        if (hasFilters) ...[
          const SizedBox(width: AppConstants.spacing2),
          IconButton(
            onPressed: _clearFilters,
            tooltip: 'Clear filters',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ],
    );
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _selectedYear = _allYears;
      _searchFieldVersion += 1;
    });
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

  int _reminderCount(List<Wishlist> wishlists) {
    if (!widget.currentUser.notificationsEnabled) {
      return 0;
    }

    final now = DateTime.now();
    final minimumAge = Duration(days: widget.currentUser.reminderDays);
    var count = 0;

    for (final wishlist in wishlists) {
      for (final item in wishlist.activeItems) {
        if (now.difference(item.createdAt) >= minimumAge) {
          count += 1;
        }
      }
    }

    return count;
  }

  void _scheduleReminderPrompt(int reminderCount) {
    final signature = [
      widget.currentUser.id,
      widget.currentUser.notificationsEnabled,
      widget.currentUser.reminderDays,
      reminderCount,
    ].join('|');

    if (_lastReminderSignature == signature || reminderCount == 0) {
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
              'You have $reminderCount wishlist reminder${reminderCount == 1 ? '' : 's'} ready.',
            ),
            action: SnackBarAction(
              label: 'View',
              onPressed: _openRemindersScreen,
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
    } else if (wishlist.members.isNotEmpty) {
      segments.add('${wishlist.members.length} members');
    }

    return segments.join(' · ');
  }

  Widget _buildEmptyState({
    required String title,
    required String description,
    String? actionLabel,
    VoidCallback? onAction,
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
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppConstants.spacing3),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
          ],
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
        final reminderCount = _reminderCount(visibleWishlists);
        final sharedWishlists = _filterWishlists(
          visibleWishlists.where(_isShared).toList(growable: false),
        );
        final activeWishlists = _filterWishlists(
          visibleWishlists
              .where(
                (wishlist) =>
                    !_isShared(wishlist) &&
                    (wishlist.activeItemCount > 0 || wishlist.items.isEmpty),
              )
              .toList(growable: false),
        );
        return Stack(
          children: [
            Scaffold(
              extendBody: true,
              appBar: WishizAppBar(
                useWordmark: true,
                actions: _buildHeaderActions(reminderCount: reminderCount),
              ),
              body: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final isIncoming = child.key == ValueKey(_currentIndex);
                  final offsetTween = Tween<Offset>(
                    begin: Offset(isIncoming ? 0.08 : -0.04, 0),
                    end: Offset.zero,
                  );

                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: animation.drive(offsetTween),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(_currentIndex),
                  child: _currentIndex == 0
                      ? _buildHomeTab(
                          activeWishlists: activeWishlists,
                          availableYears: availableYears,
                          reminderCount: reminderCount,
                          sharedCount: sharedWishlists.length,
                        )
                      : _buildCollectionTab(
                          title: 'Shared',
                          description:
                              'Lists you collaborate on with others or have been invited to join.',
                          wishlists: sharedWishlists,
                          emptyTitle: 'Nothing shared yet',
                          emptyDescription:
                              'Invite collaborators to a list, or join one using a share link.',
                          availableYears: availableYears,
                          summaryLabel:
                              '${sharedWishlists.length} shared ${sharedWishlists.length == 1 ? 'list' : 'lists'}',
                          isSharedView: true,
                        ),
                ),
              ),
              bottomNavigationBar: GlassmorphicBottomNav(
                currentIndex: _currentIndex,
                onTap: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                  _updateSharedTabPolling(index);
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
