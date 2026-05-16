import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/theme/app_colors.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/onboarding/domain/entities/preference_category.dart';
import 'package:wishiz/features/onboarding/screens/onboarding_preferences/components/category_card.dart';

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
  final _selectedIds = ValueNotifier<Set<String>>({});
  bool _isSaving = false;

  @override
  void dispose() {
    _selectedIds.dispose();
    super.dispose();
  }

  void _toggleCategory(String id) {
    final current = Set<String>.of(_selectedIds.value);
    if (current.contains(id)) {
      current.remove(id);
    } else {
      current.add(id);
    }
    _selectedIds.value = current;
  }

  Future<void> _startExploring() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    await widget.authRepository.savePreferences(
      categoryIds: _selectedIds.value.toList(),
      brandNames: const [],
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
                      'Select your favorite categories',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppConstants.spacing3),
                    Text(
                      "We'll personalize your experience",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacing8),
                    ValueListenableBuilder<Set<String>>(
                      valueListenable: _selectedIds,
                      builder: (context, selectedIds, _) {
                        return GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: AppConstants.itemGap,
                          crossAxisSpacing: AppConstants.itemGap,
                          childAspectRatio: 1.1,
                          children: PreferenceCategory.all
                              .map(
                                (category) => CategoryCard(
                                  key: ValueKey(category.id),
                                  category: category,
                                  isSelected: selectedIds.contains(category.id),
                                  onTap: () => _toggleCategory(category.id),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                    const SizedBox(height: AppConstants.sectionGap),
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
                    valueListenable: _selectedIds,
                    builder: (context, selectedIds, _) {
                      final hasSelection = selectedIds.isNotEmpty;
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall?.copyWith(
                                      color: Colors.white,
                                    ),
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
