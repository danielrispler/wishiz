import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';

class AccountFormSection extends StatefulWidget {
  const AccountFormSection({
    super.key,
    required this.formKey,
    required this.fullNameController,
    required this.emailController,
    required this.birthdayController,
    required this.currentPasswordController,
    required this.newPasswordController,
    required this.selectedGender,
    required this.selectedCurrencyCode,
    required this.isChangingPassword,
    required this.onSelectBirthday,
    required this.onGenderChanged,
    required this.onTogglePasswordEditing,
    required this.onCurrencyChanged,
    required this.onFieldChanged,
    required this.validateRequired,
    required this.validateEmail,
    required this.validateCurrentPassword,
    required this.validateOptionalPassword,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController fullNameController;
  final TextEditingController emailController;
  final TextEditingController birthdayController;
  final TextEditingController currentPasswordController;
  final TextEditingController newPasswordController;
  final String? selectedGender;
  final String selectedCurrencyCode;
  final bool isChangingPassword;
  final VoidCallback onSelectBirthday;
  final ValueChanged<String?> onGenderChanged;
  final VoidCallback onTogglePasswordEditing;
  final ValueChanged<String> onCurrencyChanged;
  final VoidCallback onFieldChanged;
  final String? Function(String?) validateRequired;
  final String? Function(String?) validateEmail;
  final String? Function(String?) validateCurrentPassword;
  final String? Function(String?) validateOptionalPassword;

  @override
  State<AccountFormSection> createState() => _AccountFormSectionState();
}

class _AccountFormSectionState extends State<AccountFormSection> {
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
      child: Column(
        children: [
          _SectionCard(
            icon: Icons.person_outline,
            title: 'Personal details',
            subtitle:
                'Keep the basics accurate so shared lists and reminders stay personal and easy to recognize.',
            child: Column(
              children: [
                _LabeledField(
                  label: 'Full name',
                  hint: 'How your name appears on wishlists',
                  child: TextFormField(
                    controller: widget.fullNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'Enter your full name',
                      border: InputBorder.none,
                    ),
                    validator: widget.validateRequired,
                    onChanged: (_) => widget.onFieldChanged(),
                  ),
                ),
                const SizedBox(height: AppConstants.itemGap),
                _LabeledField(
                  label: 'Email address',
                  hint: 'Used for sign-in and account updates',
                  child: TextFormField(
                    controller: widget.emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'name@example.com',
                      border: InputBorder.none,
                    ),
                    validator: widget.validateEmail,
                    onChanged: (_) => widget.onFieldChanged(),
                  ),
                ),
                const SizedBox(height: AppConstants.itemGap),
                _LabeledField(
                  label: 'Birthday',
                  hint: 'Helps personalize reminders and gifting moments',
                  child: TextFormField(
                    controller: widget.birthdayController,
                    readOnly: true,
                    onTap: widget.onSelectBirthday,
                    decoration: const InputDecoration(
                      hintText: 'Select your birthday',
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                      border: InputBorder.none,
                    ),
                    validator: widget.validateRequired,
                  ),
                ),
                const SizedBox(height: AppConstants.itemGap),
                _LabeledField(
                  label: 'Gender',
                  hint: 'Used to keep Discover aligned with what you shop for',
                  child: DropdownButtonFormField<String>(
                    initialValue: widget.selectedGender,
                    decoration: const InputDecoration(
                      hintText: 'Select your gender',
                      border: InputBorder.none,
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Prefer not to say'),
                      ),
                      ...AppUser.supportedGenders.map(
                        (gender) => DropdownMenuItem<String>(
                          value: gender,
                          child: Text(AppUser.genderLabel(gender)),
                        ),
                      ),
                    ],
                    onChanged: widget.onGenderChanged,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.sectionGap),
          _SectionCard(
            icon: Icons.payments_outlined,
            title: 'Shopping preferences',
            subtitle:
                'Choose the currency you want to see by default when browsing item prices.',
            child: _LabeledField(
              label: 'Default currency',
              hint: 'This affects how prices are shown across the app',
              child: DropdownButtonFormField<String>(
                initialValue: widget.selectedCurrencyCode,
                decoration: const InputDecoration(border: InputBorder.none),
                items: AppUser.supportedCurrencyCodes
                    .map(
                      (code) => DropdownMenuItem(
                        value: code,
                        child: Text(_currencyLabel(code)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => widget.onCurrencyChanged(value ?? 'USD'),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.sectionGap),
          _SectionCard(
            icon: Icons.lock_outline,
            title: 'Password',
            subtitle:
                'Leave this alone if you do not want to change it. Showing it only when needed keeps the page simpler.',
            child: Column(
              children: [
                _ActionRow(
                  title: 'Change password',
                  description: widget.isChangingPassword
                      ? 'Enter your current password once, then choose a new one.'
                      : 'Optional. Open this only when you want to update your password.',
                  action: OutlinedButton(
                    onPressed: widget.onTogglePasswordEditing,
                    child: Text(
                      widget.isChangingPassword ? 'Cancel' : 'Edit password',
                    ),
                  ),
                ),
                if (widget.isChangingPassword) ...[
                  const SizedBox(height: AppConstants.itemGap),
                  _LabeledField(
                    label: 'Current password',
                    hint: 'Needed to confirm this change',
                    child: TextFormField(
                      controller: widget.currentPasswordController,
                      obscureText: !_showCurrentPassword,
                      decoration: InputDecoration(
                        hintText: 'Enter current password',
                        border: InputBorder.none,
                        suffixIcon: IconButton(
                          tooltip: _showCurrentPassword
                              ? 'Hide password'
                              : 'Show password',
                          onPressed: () => setState(
                            () => _showCurrentPassword = !_showCurrentPassword,
                          ),
                          icon: Icon(
                            _showCurrentPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      validator: widget.validateCurrentPassword,
                    ),
                  ),
                  const SizedBox(height: AppConstants.itemGap),
                  _LabeledField(
                    label: 'New password',
                    hint: 'Use at least 6 characters',
                    child: TextFormField(
                      controller: widget.newPasswordController,
                      obscureText: !_showNewPassword,
                      decoration: InputDecoration(
                        hintText: 'Create new password',
                        border: InputBorder.none,
                        suffixIcon: IconButton(
                          tooltip: _showNewPassword
                              ? 'Hide password'
                              : 'Show password',
                          onPressed: () => setState(
                            () => _showNewPassword = !_showNewPassword,
                          ),
                          icon: Icon(
                            _showNewPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      validator: widget.validateOptionalPassword,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _currencyLabel(String code) {
    final symbol = AppUser.currencySymbols[code] ?? code;
    if (code == 'ILS') {
      return 'ILS / NIS ($symbol)';
    }
    return '$code ($symbol)';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: AppConstants.spacing3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppConstants.spacing1),
                    Text(subtitle, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacing5),
          child,
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.hint,
    required this.child,
  });

  final String label;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.cardPadding,
        vertical: AppConstants.spacing3,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppConstants.spacing1),
          Text(hint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppConstants.spacing2),
          child,
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.description,
    required this.action,
  });

  final String title;
  final String description;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppConstants.spacing1),
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(width: AppConstants.spacing3),
        action,
      ],
    );
  }
}
