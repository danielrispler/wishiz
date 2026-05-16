import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wishiz/core/theme/app_colors.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/discover/domain/entities/brand_group.dart';
import 'package:wishiz/features/discover/domain/entities/discover_feed.dart';
import 'package:wishiz/features/discover/domain/repositories/discover_repository.dart';
import 'package:wishiz/features/discover/models/product.dart';
import 'package:wishiz/features/discover/models/starter_pack.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'components/product_carousel/product_carousel.dart';
import 'components/section_header.dart';
import 'components/starter_pack_carousel/starter_pack_carousel.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.authRepository,
    required this.currentUser,
    this.discoverRepository,
    this.wishlistRepository,
  });

  final AuthRepository authRepository;
  final WishlistRepository? wishlistRepository;
  final DiscoverRepository? discoverRepository;
  final AppUser currentUser;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late Set<String> _selectedBrandNames;

  DiscoverFeed? _feed;
  bool _isLoading = true;
  String? _loadError;

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

  Future<void> _loadFeed() async {
    if (widget.discoverRepository == null) {
      setState(() {
        _feed = DiscoverFeed(
          starterPacks: StarterPack.sample,
          trending: List.of(Product.sample.take(4)),
          forYou: List.of(Product.sample.skip(4).take(4)),
        );
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final feed = await widget.discoverRepository!.getFeed();
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load the feed. Pull to refresh.';
      });
    }
  }

  void _handleToggleSave(Product p, bool _) async {
    if (p.isSavedByUser) {
      _optimisticToggle(p);
      try {
        if (widget.discoverRepository != null) {
          await widget.discoverRepository!.toggleSave(p.id);
        }
      } catch (_) {
        if (!mounted) return;
        _optimisticToggle(p);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not remove that save right now.'),
            ),
          );
      }
      return;
    }

    final wishlistRepository = widget.wishlistRepository;
    if (wishlistRepository == null) {
      _optimisticToggle(p);
      return;
    }

    final wishlists = wishlistRepository
        .getWishlists()
        .where((w) => !w.isArchived)
        .toList(growable: false);

    if (wishlists.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Create a wishlist first.')),
        );
      return;
    }

    final wishlist = await _showWishlistPicker(wishlists);
    if (!mounted || wishlist == null) return;

    _optimisticToggle(p);

    try {
      if (widget.discoverRepository != null) {
        await widget.discoverRepository!.toggleSave(p.id);
      }
      await wishlistRepository.addWishlistItem(
        wishlistId: wishlist.id,
        title: p.title,
        imageUrl: p.imageUrl,
        priceLabel: p.priceLabel,
        productUrl: p.productUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Saved to "${wishlist.title}".')),
        );
    } catch (_) {
      if (!mounted) return;
      _optimisticToggle(p);
    }
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

  Future<void> _handleGrabPack(StarterPack pack) async {
    final wishlistRepository = widget.wishlistRepository;
    if (wishlistRepository == null) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.onSurface,
          behavior: SnackBarBehavior.floating,
          content: Text('Added "${pack.title}" to your lists'),
        ),
      );
      return;
    }

    final wishlists = wishlistRepository
        .getWishlists()
        .where((w) => !w.isArchived)
        .toList(growable: false);

    if (wishlists.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Create a wishlist first.')),
        );
      return;
    }

    final wishlist = await _showWishlistPicker(wishlists);
    if (!mounted || wishlist == null) return;

    HapticFeedback.mediumImpact();

    try {
      if (widget.discoverRepository != null) {
        await widget.discoverRepository!.grabStarterPack(pack.id, wishlist.id);
      } else {
        for (final item in pack.items) {
          await wishlistRepository.addWishlistItem(
            wishlistId: wishlist.id,
            title: item.title,
            imageUrl: item.imageUrl,
            priceLabel: item.priceLabel,
            productUrl: item.productUrl,
          );
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.onSurface,
          behavior: SnackBarBehavior.floating,
          content: Text('Added "${pack.title}" to "${wishlist.title}"'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not grab that pack right now.')),
        );
    }
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

    final result = await widget.authRepository.savePreferences(
      brandNames: draftBrands.toList(),
    );

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _selectedBrandNames = draftBrands;
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
    final packs = feed?.starterPacks ?? [];
    final trending = feed?.trending ?? [];
    final forYou = feed?.forYou ?? [];

    return ColoredBox(
      color: AppColors.surface,
      child: Stack(
        children: [
          const _AmbientBackdrop(),
          RefreshIndicator(
            onRefresh: _loadFeed,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _DisplayTitle()),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                const SliverToBoxAdapter(child: _SearchBar()),
                const SliverToBoxAdapter(child: SizedBox(height: 18)),
                SliverToBoxAdapter(
                  child: _PreferenceRow(
                    selectedBrandNames: _selectedBrandNames,
                    onEdit: _openPreferencesSheet,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
                if (_isLoading) ...[
                  SliverToBoxAdapter(child: _ShimmerCarousel(height: 440)),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  SliverToBoxAdapter(child: _ShimmerCarousel(height: 296)),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  SliverToBoxAdapter(child: _ShimmerCarousel(height: 296)),
                ] else if (_loadError != null) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _loadError!,
                        style: const TextStyle(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  const SliverToBoxAdapter(
                    child: SectionHeader(
                      label: 'Starter Packs',
                      eyebrow: 'Curated collections, ready to grab',
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 14)),
                  SliverToBoxAdapter(
                    child: StarterPackCarousel(
                      packs: packs,
                      onGrab: _handleGrabPack,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  const SliverToBoxAdapter(
                    child: SectionHeader(
                      label: 'Trending now',
                      eyebrow: 'What women are saving this week',
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 14)),
                  SliverToBoxAdapter(
                    child: ProductCarousel(
                      products: trending,
                      onToggleSave: _handleToggleSave,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      label: 'For you',
                      eyebrow: _selectedBrandNames.isEmpty
                          ? 'Set your preferences to tailor this mix'
                          : 'Shaped by the fashion brands you picked',
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 14)),
                  SliverToBoxAdapter(
                    child: ProductCarousel(
                      products: forYou,
                      onToggleSave: _handleToggleSave,
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
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

  @override
  void initState() {
    super.initState();
    _brands = Set<String>.of(widget.initialBrands);
  }

  void _notifyChanged() {
    widget.onChanged(_brands);
  }

  @override
  Widget build(BuildContext context) {
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
                const Text(
                  'Brands',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 10),
                for (final group in BrandGroup.all) ...[
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
                          final isSelected = _brands.contains(brand);
                          return _PreferenceChip(
                            label: brand,
                            isSelected: isSelected,
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _brands.remove(brand);
                                } else {
                                  _brands.add(brand);
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
  });

  final Set<String> selectedBrandNames;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final brandCount = selectedBrandNames.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useWideHeader = constraints.maxWidth >= 420;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'For you',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                  letterSpacing: -0.25,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Fine-tune what discovery should lean into.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          );

          final editButton = FilledButton.tonalIcon(
            onPressed: onEdit,
            style: FilledButton.styleFrom(
              foregroundColor: AppColors.primary,
              backgroundColor: AppColors.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text(
              'Edit',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          );

          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.92),
                  AppColors.surfaceContainerLow.withValues(alpha: 0.96),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: AppColors.surfaceVariant.withValues(alpha: 0.8),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (useWideHeader)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 16),
                      editButton,
                    ],
                  )
                else ...[
                  title,
                  const SizedBox(height: 14),
                  Align(alignment: Alignment.centerLeft, child: editButton),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: brandCount == 0
                      ? [
                          const _PreferencePill(
                            label: 'No preferences selected yet',
                            icon: Icons.auto_awesome_rounded,
                            isPlaceholder: true,
                          ),
                        ]
                      : [
                          _PreferencePill(
                            label:
                                '$brandCount brand${brandCount == 1 ? '' : 's'}',
                            icon: Icons.favorite_border_rounded,
                          ),
                        ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PreferencePill extends StatelessWidget {
  const _PreferencePill({
    required this.label,
    this.icon,
    this.isPlaceholder = false,
  });

  final String label;
  final IconData? icon;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isPlaceholder
            ? AppColors.surfaceContainerLow
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPlaceholder ? AppColors.primary : AppColors.surfaceVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isPlaceholder ? AppColors.primary : AppColors.onSurface,
            ),
          ),
        ],
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

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: const Row(
          children: [
            Icon(Icons.search_rounded, size: 20, color: AppColors.primary),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Search products or brands',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
