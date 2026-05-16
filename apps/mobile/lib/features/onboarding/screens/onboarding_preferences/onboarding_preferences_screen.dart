import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/theme/app_colors.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/discover/domain/entities/brand_group.dart';

class OnboardingPreferencesScreen extends StatefulWidget {
  const OnboardingPreferencesScreen({
    super.key,
    required this.authRepository,
    required this.onComplete,
    required this.onSkip,
  });

  final AuthRepository authRepository;
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  @override
  State<OnboardingPreferencesScreen> createState() =>
      _OnboardingPreferencesScreenState();
}

class _OnboardingPreferencesScreenState
    extends State<OnboardingPreferencesScreen> {
  final _selectedBrands = ValueNotifier<Set<String>>({});
  bool _isSaving = false;

  @override
  void dispose() {
    _selectedBrands.dispose();
    super.dispose();
  }

  void _toggleBrand(String brand) {
    final current = Set<String>.of(_selectedBrands.value);
    if (current.contains(brand)) {
      current.remove(brand);
    } else {
      current.add(brand);
    }
    _selectedBrands.value = current;
  }

  Future<void> _startExploring() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    await widget.authRepository.savePreferences(
      brandNames: _selectedBrands.value.toList(),
    );
    if (!mounted) return;
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.pagePadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppConstants.spacing8),
                    Text(
                      'Pick the fashion brands you love',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppConstants.spacing3),
                    Text(
                      "We'll shape Discover around these labels first.",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacing8),
                    ValueListenableBuilder<Set<String>>(
                      valueListenable: _selectedBrands,
                      builder: (context, selectedBrands, _) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: BrandGroup.all
                              .map((group) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppConstants.sectionGap,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        group.label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              color: AppColors.onSurface,
                                            ),
                                      ),
                                      const SizedBox(
                                        height: AppConstants.spacing3,
                                      ),
                                      Wrap(
                                        spacing: AppConstants.spacing2,
                                        runSpacing: AppConstants.spacing2,
                                        children: group.brands
                                            .map((brand) {
                                              final isSelected = selectedBrands
                                                  .contains(brand);
                                              return FilterChip(
                                                label: Text(brand),
                                                selected: isSelected,
                                                onSelected: (_) =>
                                                    _toggleBrand(brand),
                                                selectedColor: colorScheme
                                                    .primary
                                                    .withValues(alpha: 0.14),
                                                checkmarkColor:
                                                    colorScheme.primary,
                                                backgroundColor: AppColors
                                                    .surfaceContainerLowest,
                                                side: BorderSide(
                                                  color: isSelected
                                                      ? colorScheme.primary
                                                      : AppColors
                                                            .outlineVariant,
                                                ),
                                                labelStyle: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: isSelected
                                                      ? colorScheme.primary
                                                      : AppColors.onSurface,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 10,
                                                    ),
                                              );
                                            })
                                            .toList(growable: false),
                                      ),
                                    ],
                                  ),
                                );
                              })
                              .toList(growable: false),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.pagePadding,
                vertical: AppConstants.spacing4,
              ),
              child: Column(
                children: [
                  ValueListenableBuilder<Set<String>>(
                    valueListenable: _selectedBrands,
                    builder: (context, selectedBrands, _) {
                      final hasSelection = selectedBrands.isNotEmpty;
                      return AnimatedOpacity(
                        opacity: hasSelection ? 1.0 : 0.5,
                        duration: const Duration(milliseconds: 180),
                        child: Container(
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
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull,
                            ),
                          ),
                          child: ElevatedButton(
                            onPressed: hasSelection && !_isSaving
                                ? _startExploring
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              disabledBackgroundColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                vertical: AppConstants.spacing4,
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Start Exploring',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(color: Colors.white),
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppConstants.spacing2),
                  TextButton(
                    onPressed: _isSaving ? null : widget.onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.onSurfaceVariant,
                    ),
                    child: const Text('Skip for now'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
