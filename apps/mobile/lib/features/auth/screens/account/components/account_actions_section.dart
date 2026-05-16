import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/theme/app_colors.dart';

class AccountActionsSection extends StatelessWidget {
  const AccountActionsSection({
    super.key,
    required this.isSaving,
    required this.hasChanges,
    required this.onSave,
    required this.onLogOut,
  });

  final bool isSaving;
  final bool hasChanges;
  final VoidCallback onSave;
  final VoidCallback onLogOut;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: hasChanges
                  ? [colorScheme.primary, colorScheme.primaryContainer]
                  : [
                      AppColors.onSurfaceVariant.withValues(alpha: 0.28),
                      AppColors.onSurfaceVariant.withValues(alpha: 0.18),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          ),
          child: ElevatedButton(
            onPressed: isSaving || !hasChanges ? null : onSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(
                vertical: AppConstants.spacing4,
              ),
            ),
            child: Text(
              isSaving
                  ? 'Saving...'
                  : hasChanges
                  ? 'Save changes'
                  : 'No changes to save',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spacing3),
        TextButton.icon(
          onPressed: isSaving ? null : onLogOut,
          icon: const Icon(Icons.logout_outlined),
          label: const Text('Log out'),
        ),
      ],
    );
  }
}
