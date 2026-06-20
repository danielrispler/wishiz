import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:wishiz/core/utils/error_utils.dart';
import 'package:wishiz/shared/widgets/wishiz_app_bar.dart';

import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/auth/screens/account/account_screen.dart';
import 'package:wishiz/features/wishlists/screens/reminders/reminders_screen.dart';
import 'package:wishiz/features/home/screens/home/components/bottom_nav/glassmorphic_bottom_nav.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';
import 'package:wishiz/features/product_imports/domain/product_import_repository.dart';
import 'package:wishiz/features/product_imports/screens/import_queue/import_queue_view.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/wishlists/screens/purchase_history/purchase_history_screen.dart';
import 'package:wishiz/features/wishlists/screens/wishlist_detail/wishlist_detail_screen.dart';
import 'package:wishiz/features/wishlists/screens/wishlist_editor/wishlist_editor_screen.dart';
import 'package:wishiz/features/wishlists/screens/wishlist_item_editor/wishlist_item_editor_screen.dart';
import 'package:wishiz/features/discover/domain/repositories/discover_repository.dart';
import 'package:wishiz/features/discover/screens/discover/discover_screen.dart';
import 'components/home_app_bar_actions.dart';
import 'components/shared_import_loader.dart';
import 'components/wishlist_section/wishlist_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.productImportRepository,
    required this.sharedProductRepository,
    required this.authRepository,
    required this.currentUser,
    this.discoverRepository,
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
  final DiscoverRepository? discoverRepository;
  final AppUser currentUser;
  final String? initialWishlistId;
  final String? initialInviteToken;
  final String? initialSharedText;
  final VoidCallback? onInitialWishlistHandled;
  final ValueChanged<String>? onInitialSharedTextHandled;

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
    if (widget.initialWishlistId == null) _handledInitialWishlistId = null;
    if (widget.initialSharedText == null) _handledInitialSharedText = null;
    if (oldWidget.initialWishlistId != widget.initialWishlistId ||
        oldWidget.initialInviteToken != widget.initialInviteToken ||
        oldWidget.initialSharedText != widget.initialSharedText) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handlePendingEntryPoints());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _wishlistsListenable.removeListener(_onWishlistsChanged);
    super.dispose();
  }

  bool _isShared(Wishlist wishlist) {
    return wishlist.ownerUserId != widget.currentUser.id;
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
      _wishlistsListenable.value.where((w) => !w.isArchived).toList(growable: false),
    );
    _scheduleReminderPrompt(count);
  }

  Future<String?> _openWishlistEditor({Wishlist? wishlist, bool openDetailsOnCreate = true}) async {
    final wishlistId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => WishlistEditorScreen(repository: widget.repository, wishlist: wishlist)),
    );
    if (!mounted || wishlistId == null) return wishlistId;
    if (wishlist == null && openDetailsOnCreate) await _openWishlistDetails(wishlistId);
    return wishlistId;
  }

  Future<void> _openWishlistDetails(String wishlistId, {bool showPurchasedOnly = false}) {
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
    if (handledSharedImport) return;
    await _openInitialWishlistIfNeeded();
  }

  Future<void> _openInitialWishlistIfNeeded() async {
    final wishlistId = widget.initialWishlistId;
    if (!mounted || wishlistId == null || wishlistId.isEmpty || _handledInitialWishlistId == wishlistId) return;

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
        wishlist = await widget.repository.joinWishlist(id: wishlistId, token: inviteToken);
      } catch (e, stackTrace) {
        debugPrint('Failed to join wishlist: $e\n$stackTrace');
        if (!mounted) return;
        _showFeedback('Failed to join list: $e');
        return;
      }
    }

    if (!mounted || wishlist == null) {
      if (mounted) _showFeedback('That shared list is not available on this device yet.');
      return;
    }
    await _openWishlistDetails(wishlistId);
  }

  Future<bool> _openInitialSharedImportIfNeeded() async {
    final sharedText = widget.initialSharedText;
    if (!mounted || sharedText == null || sharedText.isEmpty ||
        _handledInitialSharedText == sharedText || _isImportingSharedProduct) {
      return false;
    }

    setState(() {
      _handledInitialSharedText = sharedText;
      _isImportingSharedProduct = true;
    });

    try {
      await widget.productImportRepository.enqueue(
        sharedText: sharedText,
        clientRequestId: _uuid.v4(),
        targetCurrencyCode: widget.currentUser.preferredCurrencyCode,
      );
      if (!mounted) return true;
      _showFeedback('Processing shared item. Check the queue to assign it.');
      return true;
    } catch (error) {
      if (mounted) _showFeedback(formatErrorMessage(error, fallbackMessage: 'Could not queue that shared product yet.'));
      return true;
    } finally {
      if (mounted) setState(() => _isImportingSharedProduct = false);
      // Advance the buffer head only after the in-flight-import guard clears,
      // so the next queued item isn't skipped by _isImportingSharedProduct.
      widget.onInitialSharedTextHandled?.call(sharedText);
    }
  }

  Future<String?> _selectWishlistForSharedImport() async {
    final wishlists = widget.repository.getWishlists().where((w) => !w.isArchived).toList(growable: false);
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
                  Text('${wishlist.year} · ${wishlist.activeItemCount} active items',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<bool?> _openSharedProductEditor({String? wishlistId, required SharedProductDraft draft}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => WishlistItemEditorScreen(
          repository: widget.repository,
          wishlistId: wishlistId,
          onSelectWishlist: wishlistId == null ? _selectWishlistForSharedImport : null,
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

  Future<void> _openAccountScreen() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => AccountScreen(authRepository: widget.authRepository)),
  );

  Future<void> _openRemindersScreen() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => RemindersScreen(authRepository: widget.authRepository)),
  );

  Future<void> _openPurchaseHistoryScreen() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PurchaseHistoryScreen(
        repository: widget.repository,
        onWishlistTap: (id) => _openWishlistDetails(id, showPurchasedOnly: true),
      ),
    ),
  );

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _retryImportJob(ProductImportJob job) async {
    try {
      await widget.productImportRepository.retry(job.id);
      _showFeedback('Import retry queued.');
    } catch (error) {
      if (!mounted) return;
      _showFeedback(formatErrorMessage(error, fallbackMessage: 'Could not retry import.'));
    }
  }

  Future<void> _acknowledgeImportJob(ProductImportJob job) async {
    try {
      await widget.productImportRepository.acknowledge(job.id);
    } catch (error) {
      if (!mounted) return;
      _showFeedback(formatErrorMessage(error, fallbackMessage: 'Could not hide import.'));
    }
  }

  Future<void> _assignImportJobToWishlist(ProductImportJob job) async {
    final wishlistId = await _selectWishlistForSharedImport();
    if (!mounted || wishlistId == null) return;
    try {
      await widget.productImportRepository.assign(job.id, wishlistId);
      final name = widget.repository.findById(wishlistId)?.title ?? 'list';
      if (mounted) _showFeedback('Added to $name.');
    } catch (error) {
      if (!mounted) return;
      _showFeedback(formatErrorMessage(error, fallbackMessage: 'Could not assign import.'));
    }
  }

  Future<void> _openImportJobEditor(ProductImportJob job) async {
    final success = await _openSharedProductEditor(
      wishlistId: job.wishlistId,
      draft: SharedProductDraft(productUrl: job.normalizedUrl, title: job.title, priceLabel: job.priceLabel, imageUrl: job.imageUrl),
    );
    if (success == true) await _acknowledgeImportJob(job);
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
    return wishlists.where((w) {
      final matchesQuery = query.isEmpty || w.title.toLowerCase().contains(query);
      final matchesYear = _selectedYear == _allYears || w.year == _selectedYear;
      return matchesQuery && matchesYear;
    }).toList(growable: false);
  }

  int _reminderCount(List<Wishlist> wishlists) {
    if (!widget.currentUser.notificationsEnabled) return 0;
    final now = DateTime.now();
    final minimumAge = Duration(days: widget.currentUser.reminderDays);
    var count = 0;
    for (final wishlist in wishlists) {
      for (final item in wishlist.activeItems) {
        if (now.difference(item.createdAt) >= minimumAge) count += 1;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('You have $reminderCount wishlist reminder${reminderCount == 1 ? '' : 's'} ready.'),
            action: SnackBarAction(label: 'View', onPressed: _openRemindersScreen),
          ),
        );
    });
  }

  List<int> _availableYears(List<Wishlist> wishlists) {
    return wishlists.map((w) => w.year).toSet().toList()..sort((a, b) => b.compareTo(a));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Wishlist>>(
      valueListenable: widget.repository.watchWishlists(),
      builder: (context, wishlists, _) {
        final visibleWishlists = wishlists.where((w) => !w.isArchived).toList(growable: false);
        final availableYears = _availableYears(visibleWishlists);
        final reminderCount = _reminderCount(visibleWishlists);
        final sharedWishlists = _filterWishlists(visibleWishlists.where(_isShared).toList(growable: false));
        final activeWishlists = _filterWishlists(visibleWishlists.where((w) => !_isShared(w)).toList(growable: false));
        final isSearchEmpty = _searchQuery.isEmpty && _selectedYear == _allYears;

        final importQueue = ImportQueueView(
          repository: widget.productImportRepository,
          isQueueing: _isImportingSharedProduct,
          onOpenWishlist: (job) { if (job.wishlistId != null) _openWishlistDetails(job.wishlistId!); },
          onAssign: _assignImportJobToWishlist,
          onReview: _openImportJobEditor,
          onRetry: _retryImportJob,
          onAcknowledge: _acknowledgeImportJob,
        );

        return Stack(
          children: [
            Scaffold(
              extendBody: true,
              appBar: WishizAppBar(
                useWordmark: true,
                actions: [
                  HomeAppBarActions(
                    reminderCount: reminderCount,
                    onPurchaseHistory: _openPurchaseHistoryScreen,
                    onReminders: _openRemindersScreen,
                    onAccount: _openAccountScreen,
                  ),
                ],
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
                    child: SlideTransition(position: animation.drive(offsetTween), child: child),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(_currentIndex),
                  child: switch (_currentIndex) {
                    0 => HomeTabContent(
                        activeWishlists: activeWishlists,
                        availableYears: availableYears,
                        reminderCount: reminderCount,
                        sharedCount: sharedWishlists.length,
                        searchQuery: _searchQuery,
                        searchFieldVersion: _searchFieldVersion,
                        selectedYear: _selectedYear,
                        allYearsValue: _allYears,
                        isSearchEmpty: isSearchEmpty,
                        onSearchChanged: (v) => setState(() => _searchQuery = v),
                        onYearSelected: (v) => setState(() => _selectedYear = v),
                        onClearFilters: _clearFilters,
                        onNewList: () => _openWishlistEditor(),
                        onOpenReminders: _openRemindersScreen,
                        onOpenWishlist: _openWishlistDetails,
                        importQueueWidget: importQueue,
                      ),
                    2 => SafeArea(
                        child: DiscoverScreen(
                          authRepository: widget.authRepository,
                          wishlistRepository: widget.repository,
                          discoverRepository: widget.discoverRepository,
                          currentUser: widget.currentUser,
                          onNavigateToLists: () =>
                              setState(() => _currentIndex = 0),
                        ),
                      ),
                    _ => SharedTabContent(
                        wishlists: sharedWishlists,
                        availableYears: availableYears,
                        searchQuery: _searchQuery,
                        searchFieldVersion: _searchFieldVersion,
                        selectedYear: _selectedYear,
                        allYearsValue: _allYears,
                        isSearchEmpty: isSearchEmpty,
                        summaryLabel: '${sharedWishlists.length} shared ${sharedWishlists.length == 1 ? 'list' : 'lists'}',
                        onSearchChanged: (v) => setState(() => _searchQuery = v),
                        onYearSelected: (v) => setState(() => _selectedYear = v),
                        onClearFilters: _clearFilters,
                        onNewList: () => _openWishlistEditor(),
                        onOpenWishlist: _openWishlistDetails,
                      ),
                  },
                ),
              ),
              bottomNavigationBar: GlassmorphicBottomNav(
                currentIndex: _currentIndex,
                onTap: (index) {
                  setState(() => _currentIndex = index);
                  _updateSharedTabPolling(index);
                },
              ),
            ),
            if (_isImportingSharedProduct) const SharedImportLoader(),
          ],
        );
      },
    );
  }
}
