import 'package:flutter/material.dart';
import 'package:wishiz/core/theme/app_colors.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/discover/domain/entities/brand_group.dart';
import 'package:wishiz/features/discover/domain/entities/discover_feed.dart';
import 'package:wishiz/features/discover/domain/repositories/discover_repository.dart';
import 'package:wishiz/features/discover/models/product.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'components/product_carousel/product_carousel.dart';
import 'components/product_detail_sheet.dart';
import 'components/section_header.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.authRepository,
    required this.currentUser,
    this.discoverRepository,
    this.wishlistRepository,
    this.onNavigateToLists,
  });

  final AuthRepository authRepository;
  final WishlistRepository? wishlistRepository;
  final DiscoverRepository? discoverRepository;
  final AppUser currentUser;
  final VoidCallback? onNavigateToLists;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late Set<String> _selectedBrandNames;

  DiscoverFeed? _feed;
  bool _isLoading = true;
  String? _loadError;
  int _activeFeedRequestId = 0;

  /// Tracks which wishlist each saved product was added to (by product id).
  final Map<String, Wishlist> _savedProductWishlists = {};

  /// Tracks the wishlist item id for saved products (session-added or pre-loaded).
  final Map<String, String> _savedItemIds = {};

  /// Tracks wishlist id for products pre-loaded as saved from the feed.
  final Map<String, String> _savedWishlistIds = {};

  @override
  void initState() {
    super.initState();
    _selectedBrandNames = widget.currentUser.preferredBrands.toSet();
    _loadFeed();
  }

  @override
  void didUpdateWidget(covariant DiscoverScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameSet(
      oldWidget.currentUser.preferredBrands.toSet(),
      widget.currentUser.preferredBrands.toSet(),
    )) {
      _selectedBrandNames = widget.currentUser.preferredBrands.toSet();
    }
  }

  Future<void> _loadFeed({bool showShimmer = true}) async {
    final requestId = ++_activeFeedRequestId;

    if (widget.discoverRepository == null) {
      if (!mounted || requestId != _activeFeedRequestId) return;
      setState(() {
        _feed = DiscoverFeed(
          starterPacks: const [],
          trending: List.of(Product.sample.take(4)),
          forYou: List.of(Product.sample.skip(4).take(4)),
        );
        _isLoading = false;
      });
      return;
    }

    setState(() {
      if (showShimmer) _isLoading = true;
      _loadError = null;
    });

    try {
      final feed = await widget.discoverRepository!.getFeed();
      if (!mounted || requestId != _activeFeedRequestId) return;
      setState(() {
        _feed = feed;
        _isLoading = false;
        _hydrateSavedStateFromFeed(feed);
      });
    } catch (_) {
      if (!mounted || requestId != _activeFeedRequestId) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load the feed. Pull to refresh.';
      });
    }
  }

  void _handleToggleSave(Product p, bool _) async {
    if (p.isSavedByUser) {
      await _removeFromList(p);
    } else {
      await _addToList(p);
    }
  }

  /// Adds product to a user-chosen wishlist. Returns true on success.
  Future<bool> _addToList(Product p) async {
    final wishlistRepository = widget.wishlistRepository;
    if (wishlistRepository == null) {
      _optimisticToggle(p);
      return true;
    }

    final wishlists = wishlistRepository
        .getWishlists()
        .where((w) => !w.isArchived)
        .toList(growable: false);

    if (wishlists.isEmpty) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Create a wishlist first.')),
        );
      return false;
    }

    final wishlist = await _showWishlistPicker(wishlists);
    if (!mounted || wishlist == null) return false;

    _optimisticToggle(p);
    setState(() => _savedProductWishlists[p.id] = wishlist);

    try {
      if (widget.discoverRepository != null) {
        await widget.discoverRepository!.toggleSave(p.id);
      }
      final item = await wishlistRepository.addWishlistItem(
        wishlistId: wishlist.id,
        title: p.title,
        imageUrl: p.imageUrl,
        productUrl: p.productUrl,
        priceLabel: p.priceLabel,
      );
      if (!mounted) return true;
      setState(() => _savedItemIds[p.id] = item.id);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Saved to "${wishlist.title}".')),
        );
      return true;
    } catch (_) {
      if (!mounted) return false;
      _optimisticToggle(p);
      setState(() {
        _savedProductWishlists.remove(p.id);
        _savedItemIds.remove(p.id);
      });
      return false;
    }
  }

  /// Removes product from its saved list.
  Future<void> _removeFromList(Product p) async {
    final wishlist = _savedProductWishlists[p.id];
    final preloadedWishlistId = _savedWishlistIds[p.id];
    final wishlistId = wishlist?.id ?? preloadedWishlistId;
    final itemId = _savedItemIds[p.id];

    _optimisticToggle(p);
    setState(() {
      _savedProductWishlists.remove(p.id);
      _savedWishlistIds.remove(p.id);
      _savedItemIds.remove(p.id);
    });
    try {
      if (widget.discoverRepository != null) {
        await widget.discoverRepository!.toggleSave(p.id);
      }
      if (wishlistId != null &&
          itemId != null &&
          widget.wishlistRepository != null) {
        await widget.wishlistRepository!.deleteWishlistItem(
          wishlistId: wishlistId,
          itemId: itemId,
        );
      }
    } catch (_) {
      if (!mounted) return;
      _optimisticToggle(p);
      setState(() {
        if (wishlist != null) _savedProductWishlists[p.id] = wishlist;
        if (preloadedWishlistId != null) {
          _savedWishlistIds[p.id] = preloadedWishlistId;
        }
        if (itemId != null) _savedItemIds[p.id] = itemId;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not remove that save right now.'),
          ),
        );
    }
  }

  void _showProductDetail(Product p) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      isScrollControlled: true,
      builder: (_) {
        return ProductDetailSheet(
          product: p,
          savedToWishlist: _savedProductWishlists[p.id],
          onAddToList: () => _addToList(p),
          onRemove: () => _removeFromList(p),
          onGoToList: widget.onNavigateToLists,
        );
      },
    );
  }

  void _optimisticToggle(Product p) {
    if (_feed == null) return;
    setState(() {
      _feed = DiscoverFeed(
        starterPacks: _feed!.starterPacks,
        trending: _toggleInList(_feed!.trending, p),
        forYou: _toggleInList(_feed!.forYou, p),
      );
    });
  }

  void _hydrateSavedStateFromFeed(DiscoverFeed feed) {
    for (final product in feed.trending) {
      _hydrateSavedProduct(product);
    }
    for (final product in feed.forYou) {
      _hydrateSavedProduct(product);
    }
  }

  void _hydrateSavedProduct(Product product) {
    if (!product.isSavedByUser || _savedItemIds.containsKey(product.id)) {
      return;
    }

    if (product.savedItemId != null) {
      _savedItemIds[product.id] = product.savedItemId!;
    }
    if (product.savedWishlistId != null) {
      _savedWishlistIds[product.id] = product.savedWishlistId!;
    }
  }

  List<Product> _toggleInList(List<Product> list, Product target) {
    return list.map((x) {
      if (x.id != target.id) return x;
      final newSaved = !x.isSavedByUser;
      return x.copyWith(
        isSavedByUser: newSaved,
        saveCount: x.saveCount + (newSaved ? 1 : -1),
      );
    }).toList();
  }

  Future<Wishlist?> _showWishlistPicker(List<Wishlist> wishlists) {
    return showModalBottomSheet<Wishlist>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Add to list',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: wishlists.length,
                  itemBuilder: (_, i) {
                    final w = wishlists[i];
                    return ListTile(
                      title: Text(
                        w.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('${w.activeItemCount} items'),
                      onTap: () => Navigator.of(ctx).pop(w),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPreferencesSheet() async {
    var draftBrands = Set<String>.of(_selectedBrandNames);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) {
        return _PreferencesSheet(
          initialBrands: draftBrands,
          onChanged: (brands) => draftBrands = brands,
        );
      },
    );

    if (_sameSet(draftBrands, _selectedBrandNames)) return;

    await _savePreferences(draftBrands);
  }

  Future<void> _removeBrandPreference(String brand) async {
    final nextBrands = Set<String>.of(_selectedBrandNames)..remove(brand);
    await _savePreferences(nextBrands);
  }

  Future<void> _savePreferences(Set<String> brandNames) async {
    final result = await widget.authRepository.savePreferences(
      brandNames: brandNames.toList(),
    );

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _selectedBrandNames = brandNames;
      });
      _loadFeed();
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.errorMessage ??
                  'Unable to save your preferences right now.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    final trending = feed?.trending ?? [];
    final forYou = feed?.forYou ?? [];
    final isFeedEmpty =
        !_isLoading && _loadError == null && trending.isEmpty && forYou.isEmpty;
    final shouldShowForYouWarning =
        !_isLoading &&
        _loadError == null &&
        _selectedBrandNames.isNotEmpty &&
        forYou.isEmpty;

    return ColoredBox(
      color: AppColors.surface,
      child: Stack(
        children: [
          const RepaintBoundary(child: _AmbientBackdrop()),
          RefreshIndicator(
            onRefresh: () => _loadFeed(showShimmer: false),
            child: _DiscoverScrollView(
              isLoading: _isLoading,
              loadError: _loadError,
              isFeedEmpty: isFeedEmpty,
              shouldShowForYouWarning: shouldShowForYouWarning,
              selectedBrandNames: _selectedBrandNames,
              trending: trending,
              forYou: forYou,
              onEditPreferences: _openPreferencesSheet,
              onRemoveBrand: _removeBrandPreference,
              onRefresh: _loadFeed,
              onToggleSave: _handleToggleSave,
              onProductTap: _showProductDetail,
            ),
          ),
        ],
      ),
    );
  }

  bool _sameSet(Set<String> left, Set<String> right) {
    if (left.length != right.length) return false;
    for (final value in left) {
      if (!right.contains(value)) return false;
    }
    return true;
  }
}

class _ForYouEmptyWarning extends StatelessWidget {
  const _ForYouEmptyWarning({required this.onEditPreferences});

  final VoidCallback onEditPreferences;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No items match your current filters yet.',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Try adding more brands or loosening your preferences to get a fuller mix.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: onEditPreferences,
                      behavior: HitTestBehavior.opaque,
                      child: const Text(
                        'Edit preferences',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Preferences Sheet ----

class _PreferencesSheet extends StatefulWidget {
  const _PreferencesSheet({
    required this.initialBrands,
    required this.onChanged,
  });

  final Set<String> initialBrands;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<_PreferencesSheet> createState() => _PreferencesSheetState();
}

class _PreferencesSheetState extends State<_PreferencesSheet> {
  late Set<String> _brands;
  late final List<_PreparedBrandGroup> _preparedGroups;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _brands = Set<String>.of(widget.initialBrands);
    _preparedGroups = BrandGroup.all
        .map(
          (group) => _PreparedBrandGroup(
            label: group.label,
            brands: group.brands
                .map(
                  (brand) => _PreparedBrandOption(
                    label: brand,
                    normalizedLabel: brand.toLowerCase(),
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  void _notifyChanged() {
    widget.onChanged(_brands);
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final filteredGroups = _preparedGroups
        .map((group) {
          final brands = group.brands
              .where(
                (brand) => normalizedQuery.isEmpty
                    ? true
                    : brand.normalizedLabel.contains(normalizedQuery),
              )
              .toList(growable: false);
          return (label: group.label, brands: brands);
        })
        .where((group) => group.brands.isNotEmpty)
        .toList(growable: false);
    final selectedBrands = _brands.toList()..sort();

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, AppColors.surfaceContainerLow],
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit preferences',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSurface,
                          letterSpacing: -0.4,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Choose the brands that shape your feed.',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text(
                      'Brands',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurfaceVariant,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _brands.isEmpty
                          ? null
                          : () {
                              setState(_brands.clear);
                              _notifyChanged();
                            },
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Clear all',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search brands',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.9),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: AppColors.surfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (selectedBrands.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final brand in selectedBrands)
                        InputChip(
                          label: Text(brand),
                          onDeleted: () {
                            setState(() {
                              _brands.remove(brand);
                            });
                            _notifyChanged();
                          },
                          deleteIcon: const Icon(Icons.close_rounded, size: 16),
                          deleteIconColor: AppColors.primary,
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.08,
                          ),
                          side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.2),
                          ),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                          ),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (filteredGroups.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.surfaceVariant),
                    ),
                    child: const Text(
                      'No brands match your search.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                for (final group in filteredGroups) ...[
                  Text(
                    group.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: group.brands
                        .map((brand) {
                          final isSelected = _brands.contains(brand.label);
                          return _PreferenceChip(
                            label: brand.label,
                            isSelected: isSelected,
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _brands.remove(brand.label);
                                } else {
                                  _brands.add(brand.label);
                                }
                              });
                              _notifyChanged();
                            },
                          );
                        })
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreferenceChip extends StatelessWidget {
  const _PreferenceChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withValues(alpha: 0.12),
      checkmarkColor: AppColors.primary,
      side: BorderSide(
        color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
      ),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: isSelected ? AppColors.primary : AppColors.onSurface,
      ),
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
    );
  }
}

// ---- Preference Row ----

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.selectedBrandNames,
    required this.onEdit,
    required this.onRemoveBrand,
  });

  final Set<String> selectedBrandNames;
  final VoidCallback onEdit;
  final ValueChanged<String> onRemoveBrand;

  @override
  Widget build(BuildContext context) {
    final previewData = _PreferencePreviewData.fromBrands(selectedBrandNames);
    final brandCount = previewData.brandCount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useWideHeader = constraints.maxWidth >= 430;
          final summary = brandCount == 0
              ? 'Add brands to tailor this mix.'
              : '$brandCount brand${brandCount == 1 ? '' : 's'} selected';
          final title = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PreferencePill(
                label: summary,
                icon: brandCount == 0
                    ? Icons.auto_awesome_rounded
                    : Icons.favorite_border_rounded,
                isPlaceholder: brandCount == 0,
                compact: true,
              ),
            ],
          );

          final editButton = FilledButton.tonalIcon(
            onPressed: onEdit,
            style: FilledButton.styleFrom(
              foregroundColor: AppColors.primary,
              backgroundColor: AppColors.surfaceContainerLow,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: const Text(
              'Edit',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          );

          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.surfaceVariant.withValues(alpha: 0.85),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (useWideHeader)
                  Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 10),
                      editButton,
                    ],
                  )
                else ...[
                  title,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: editButton),
                ],
                if (brandCount > 0) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final brand in previewData.previewBrands)
                        _PreferencePill(
                          label: brand,
                          compact: true,
                          onDeleted: () => onRemoveBrand(brand),
                        ),
                      if (previewData.remainingBrands > 0)
                        _PreferencePill(
                          label: '+${previewData.remainingBrands}',
                          compact: true,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DiscoverScrollView extends StatelessWidget {
  const _DiscoverScrollView({
    required this.isLoading,
    required this.loadError,
    required this.isFeedEmpty,
    required this.shouldShowForYouWarning,
    required this.selectedBrandNames,
    required this.trending,
    required this.forYou,
    required this.onEditPreferences,
    required this.onRemoveBrand,
    required this.onRefresh,
    required this.onToggleSave,
    required this.onProductTap,
  });

  final bool isLoading;
  final String? loadError;
  final bool isFeedEmpty;
  final bool shouldShowForYouWarning;
  final Set<String> selectedBrandNames;
  final List<Product> trending;
  final List<Product> forYou;
  final VoidCallback onEditPreferences;
  final ValueChanged<String> onRemoveBrand;
  final Future<void> Function() onRefresh;
  final void Function(Product product, bool isSaved) onToggleSave;
  final void Function(Product product) onProductTap;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        const SliverToBoxAdapter(
          child: RepaintBoundary(child: _DisplayTitle()),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        SliverToBoxAdapter(
          child: RepaintBoundary(
            child: _PreferenceRow(
              selectedBrandNames: selectedBrandNames,
              onEdit: onEditPreferences,
              onRemoveBrand: onRemoveBrand,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
        if (isLoading) ...[
          const SliverToBoxAdapter(
            child: RepaintBoundary(child: _ShimmerCarousel(height: 296)),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          const SliverToBoxAdapter(
            child: RepaintBoundary(child: _ShimmerCarousel(height: 296)),
          ),
        ] else if (loadError != null) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                loadError!,
                style: const TextStyle(color: AppColors.onSurfaceVariant),
              ),
            ),
          ),
        ] else if (isFeedEmpty) ...[
          SliverToBoxAdapter(
            child: RepaintBoundary(
              child: _DiscoverEmptyState(
                hasPreferences: selectedBrandNames.isNotEmpty,
                onEditPreferences: onEditPreferences,
                onRefresh: onRefresh,
              ),
            ),
          ),
        ] else ...[
          SliverToBoxAdapter(
            child: RepaintBoundary(
              child: SectionHeader(
                label: 'For you',
                eyebrow: selectedBrandNames.isEmpty
                    ? 'Set your preferences to tailor this mix'
                    : 'Shaped by the fashion brands you picked',
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 14)),
          if (shouldShowForYouWarning) ...[
            SliverToBoxAdapter(
              child: RepaintBoundary(
                child: _ForYouEmptyWarning(
                  onEditPreferences: onEditPreferences,
                ),
              ),
            ),
          ] else ...[
            SliverToBoxAdapter(
              child: RepaintBoundary(
                child: ProductCarousel(
                  products: forYou,
                  onToggleSave: onToggleSave,
                  onProductTap: onProductTap,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          const SliverToBoxAdapter(
            child: RepaintBoundary(
              child: SectionHeader(
                label: 'Trending now',
                eyebrow: 'What women are saving this week',
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 14)),
          SliverToBoxAdapter(
            child: RepaintBoundary(
              child: ProductCarousel(
                products: trending,
                onToggleSave: onToggleSave,
                onProductTap: onProductTap,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ],
    );
  }
}

class _PreparedBrandGroup {
  const _PreparedBrandGroup({required this.label, required this.brands});

  final String label;
  final List<_PreparedBrandOption> brands;
}

class _PreparedBrandOption {
  const _PreparedBrandOption({
    required this.label,
    required this.normalizedLabel,
  });

  final String label;
  final String normalizedLabel;
}

class _PreferencePreviewData {
  const _PreferencePreviewData({
    required this.brandCount,
    required this.previewBrands,
    required this.remainingBrands,
  });

  final int brandCount;
  final List<String> previewBrands;
  final int remainingBrands;

  factory _PreferencePreviewData.fromBrands(Set<String> brands) {
    final sortedBrands = brands.toList()..sort();
    final previewBrands = sortedBrands.take(4).toList(growable: false);
    return _PreferencePreviewData(
      brandCount: sortedBrands.length,
      previewBrands: previewBrands,
      remainingBrands: sortedBrands.length - previewBrands.length,
    );
  }
}

class _PreferencePill extends StatelessWidget {
  const _PreferencePill({
    required this.label,
    this.icon,
    this.isPlaceholder = false,
    this.compact = false,
    this.onDeleted,
  });

  final String label;
  final IconData? icon;
  final bool isPlaceholder;
  final bool compact;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 10,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: isPlaceholder
            ? AppColors.surfaceContainerLow
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(
          color: isPlaceholder ? AppColors.primary : AppColors.surfaceVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 13 : 14, color: AppColors.primary),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: isPlaceholder ? AppColors.primary : AppColors.onSurface,
            ),
          ),
          if (onDeleted != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onDeleted,
              behavior: HitTestBehavior.opaque,
              child: Icon(
                Icons.close_rounded,
                size: compact ? 14 : 16,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiscoverEmptyState extends StatelessWidget {
  const _DiscoverEmptyState({
    required this.hasPreferences,
    required this.onEditPreferences,
    required this.onRefresh,
  });

  final bool hasPreferences;
  final Future<void> Function() onRefresh;
  final VoidCallback onEditPreferences;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.94),
              AppColors.surfaceContainerLow.withValues(alpha: 0.98),
            ],
          ),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppColors.surfaceVariant),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Fresh picks are on the way',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasPreferences
                  ? 'We do not have live product cards for your selected brands yet. The daily sitemap worker will fill this in automatically.'
                  : 'Discover needs a first batch of live products before it can render cards. You can set a few favorite brands now and refresh after the worker runs.',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    onRefresh();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh feed'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onEditPreferences,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Edit brands'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Shimmer placeholder ----

class _ShimmerCarousel extends StatefulWidget {
  const _ShimmerCarousel({required this.height});
  final double height;

  @override
  State<_ShimmerCarousel> createState() => _ShimmerCarouselState();
}

class _ShimmerCarouselState extends State<_ShimmerCarousel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.3, end: 0.7).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) => Opacity(
        opacity: _opacity.value,
        child: SizedBox(
          height: widget.height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: 4,
            separatorBuilder: (context, _) => const SizedBox(width: 12),
            itemBuilder: (context, _) => Container(
              width: widget.height < 400 ? 158 : 244,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Static UI pieces (unchanged) ----

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -120,
            child: _Blob(
              size: 320,
              color: const Color(0xFF9396FF).withValues(alpha: 0.32),
            ),
          ),
          Positioned(
            top: 280,
            left: -140,
            child: _Blob(
              size: 280,
              color: const Color(0xFFE1D8FF).withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0, 0.7],
        ),
      ),
    );
  }
}

class _DisplayTitle extends StatelessWidget {
  const _DisplayTitle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FOR YOU · CURATED DAILY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
                letterSpacing: -0.7,
                height: 1.02,
              ),
              children: [
                TextSpan(text: 'Discover\n'),
                TextSpan(
                  text: 'your boutique.',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w400,
                    fontSize: 38,
                    letterSpacing: -1,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
