import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';

class AccountHeroCard extends StatelessWidget {
  const AccountHeroCard({
    super.key,
    required this.colorScheme,
    required this.userName,
    required this.email,
    required this.birthday,
    required this.currencyLabel,
  });

  final ColorScheme colorScheme;
  final String userName;
  final String email;
  final String birthday;
  final String currencyLabel;

  @override
  Widget build(BuildContext context) {
    final initials = userName.isEmpty ? '?' : userName.characters.first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacing5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withValues(alpha: 0.94),
            colorScheme.primaryContainer.withValues(alpha: 0.94),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.24),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials.toUpperCase(),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spacing4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your account',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: AppConstants.spacing1),
                    Text(
                      'Review details, update preferences, and keep your login secure.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacing5),
          Wrap(
            spacing: AppConstants.spacing2,
            runSpacing: AppConstants.spacing2,
            children: [
              _InfoChip(icon: Icons.mail_outline, label: email),
              if (birthday.isNotEmpty)
                _InfoChip(icon: Icons.cake_outlined, label: birthday),
              _InfoChip(icon: Icons.payments_outlined, label: currencyLabel),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing3,
        vertical: AppConstants.spacing2,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: AppConstants.spacing2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
