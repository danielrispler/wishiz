import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wishiz/core/theme/app_colors.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/onboarding/domain/entities/preference_category.dart';
import 'package:wishiz/features/discover/models/product.dart';
import 'package:wishiz/features/discover/models/starter_pack.dart';
import 'components/product_carousel/product_carousel.dart';
import 'components/section_header.dart';
import 'components/starter_pack_carousel/starter_pack_carousel.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.authRepository,
    required this.currentUser,
  });

  final AuthRepository authRepository;
  final AppUser currentUser;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late List<StarterPack> _packs;
  late List<Product> _trending;
  late List<Product> _forYou;
  late Set<String> _selectedCategoryIds;
  final Set<String> _removingCategoryIds = <String>{};

  @override
  void initState() {
    super.initState();
    _packs = StarterPack.sample;
    _trending = List.of(Product.sample.take(4));
    _forYou = List.of(Product.sample.skip(4).take(4));
    _selectedCategoryIds = widget.currentUser.onboardingCategories.toSet();
  }

  @override
  void didUpdateWidget(covariant DiscoverScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameSet(
      oldWidget.currentUser.onboardingCategories.toSet(),
      widget.currentUser.onboardingCategories.toSet(),
    )) {
      _selectedCategoryIds = widget.currentUser.onboardingCategories.toSet();
    }
  }

  void _handleToggleSave(Product p, bool isSaved) {
    setState(() {
      _trending = _trending
          .map((x) => x.id == p.id
              ? x.copyWith(
                  isSavedByUser: isSaved,
                  saves: x.saves + (isSaved ? 1 : -1),
                )
              : x)
          .toList();
      _forYou = _forYou
          .map((x) => x.id == p.id
              ? x.copyWith(
                  isSavedByUser: isSaved,
                  saves: x.saves + (isSaved ? 1 : -1),
                )
              : x)
          .toList();
    });
  }

  void _handleGrabPack(StarterPack pack) {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.onSurface,
        behavior: SnackBarBehavior.floating,
        content: Text('Added "${pack.title}" to your lists'),
      ),
    );
  }

  Future<void> _openPreferencesSheet() async {
    final draftSelection = Set<String>.of(_selectedCategoryIds);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) {
        var localSelection = Set<String>.of(draftSelection);
        var localIsSaving = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> savePreferences() async {
              if (localIsSaving) {
                return;
              }

              setModalState(() {
                localIsSaving = true;
              });

              final result = await widget.authRepository.saveOnboardingCategories(
                _orderedCategoryIds(localSelection),
              );

              if (!mounted) {
                return;
              }

              setModalState(() {
                localIsSaving = false;
              });

              if (!result.isSuccess) {
                ScaffoldMessenger.of(this.context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        result.errorMessage ??
                            'Unable to save your preferences right now.',
                      ),
                    ),
                  );
                return;
              }

              setState(() {
                _selectedCategoryIds = localSelection;
              });

              if (!sheetContext.mounted) {
                return;
              }

              Navigator.of(sheetContext).pop();
              ScaffoldMessenger.of(this.context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Preferences updated.')),
                );
            }

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
                              colors: [
                                Colors.white,
                                AppColors.surfaceContainerLow,
                              ],
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
                                'Choose the categories you want shaping your discovery feed.',
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
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: PreferenceCategory.all.map((category) {
                            final isSelected =
                                localSelection.contains(category.id);
                            return FilterChip(
                              label: Text('${category.emoji} ${category.label}'),
                              selected: isSelected,
                              onSelected: localIsSaving
                                  ? null
                                  : (_) {
                                      setModalState(() {
                                        if (isSelected) {
                                          localSelection.remove(category.id);
                                        } else {
                                          localSelection.add(category.id);
                                        }
                                      });
                                    },
                              selectedColor: AppColors.primary.withValues(
                                alpha: 0.12,
                              ),
                              checkmarkColor: AppColors.primary,
                              side: BorderSide(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.surfaceVariant,
                              ),
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.onSurface,
                              ),
                              backgroundColor:
                                  AppColors.surfaceContainerLowest,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 10,
                              ),
                            );
                          }).toList(growable: false),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: localIsSaving ? null : savePreferences,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Text(
                              localIsSaving
                                  ? 'Saving...'
                                  : 'Save preferences',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _removeCategory(String categoryId) async {
    if (_removingCategoryIds.contains(categoryId)) {
      return;
    }

    final updatedSelection = Set<String>.of(_selectedCategoryIds)
      ..remove(categoryId);

    setState(() {
      _removingCategoryIds.add(categoryId);
    });

    final result = await widget.authRepository.saveOnboardingCategories(
      _orderedCategoryIds(updatedSelection),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _removingCategoryIds.remove(categoryId);
      if (result.isSuccess) {
        _selectedCategoryIds = updatedSelection;
      }
    });

    if (result.isSuccess) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage ?? 'Unable to update your preferences.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Stack(
        children: [
          const _AmbientBackdrop(),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _DisplayTitle()),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              const SliverToBoxAdapter(child: _SearchBar()),
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              SliverToBoxAdapter(
                child: _PreferenceRow(
                  selectedCategoryIds: _selectedCategoryIds,
                  removingCategoryIds: _removingCategoryIds,
                  onEdit: _openPreferencesSheet,
                  onRemove: _removeCategory,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
              const SliverToBoxAdapter(
                child: SectionHeader(
                  label: 'Starter Packs',
                  eyebrow: 'Curated collections, ready to grab',
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(
                child: StarterPackCarousel(
                  packs: _packs,
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
                  products: _trending,
                  onToggleSave: _handleToggleSave,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: SectionHeader(
                  label: 'For you',
                  eyebrow: _selectedCategoryIds.isEmpty
                      ? 'Set your preferences to tailor this mix'
                      : 'Shaped by the categories you picked',
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(
                child: ProductCarousel(
                  products: _forYou,
                  onToggleSave: _handleToggleSave,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _orderedCategoryIds(Set<String> selectedIds) {
    return PreferenceCategory.all
        .where((category) => selectedIds.contains(category.id))
        .map((category) => category.id)
        .toList(growable: false);
  }

  bool _sameSet(Set<String> left, Set<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final value in left) {
      if (!right.contains(value)) {
        return false;
      }
    }
    return true;
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.selectedCategoryIds,
    required this.removingCategoryIds,
    required this.onEdit,
    required this.onRemove,
  });

  final Set<String> selectedCategoryIds;
  final Set<String> removingCategoryIds;
  final VoidCallback onEdit;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final selectedCategories = PreferenceCategory.all
        .where((category) => selectedCategoryIds.contains(category.id))
        .toList(growable: false);
    final visibleCategories = selectedCategories.take(4).toList(growable: false);
    final hiddenCount = selectedCategories.length - visibleCategories.length;

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
                  children: selectedCategories.isEmpty
                      ? [
                          const _PreferencePill(
                            label: 'No categories selected yet',
                            icon: Icons.auto_awesome_rounded,
                            isPlaceholder: true,
                          ),
                        ]
                      : [
                          ...visibleCategories.map(
                            (category) => _PreferencePill(
                              label: '${category.emoji} ${category.label}',
                              trailingIcon: removingCategoryIds.contains(
                                category.id,
                              )
                                  ? null
                                  : Icons.close_rounded,
                              onTrailingTap: removingCategoryIds.contains(
                                category.id,
                              )
                                  ? null
                                  : () => onRemove(category.id),
                              isLoading: removingCategoryIds.contains(
                                category.id,
                              ),
                            ),
                          ),
                          if (hiddenCount > 0)
                            _PreferencePill(label: '+$hiddenCount more'),
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
    this.trailingIcon,
    this.onTrailingTap,
    this.isLoading = false,
    this.isPlaceholder = false,
  });

  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingTap;
  final bool isLoading;
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
              color: isPlaceholder
                  ? AppColors.primary
                  : AppColors.onSurface,
            ),
          ),
          if (isLoading) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: AppColors.primary,
              ),
            ),
          ] else if (trailingIcon != null && onTrailingTap != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onTrailingTap,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Icon(
                  trailingIcon,
                  size: 13,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
