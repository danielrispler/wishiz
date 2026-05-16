import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/theme/app_colors.dart';
import 'package:wishiz/core/widgets/wishiz_app_bar.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _fullNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _birthdayController;
  late final TextEditingController _currentPasswordController;
  late final TextEditingController _newPasswordController;

  late DateTime _selectedBirthday;
  late String _selectedCurrencyCode;
  late AppUser _savedUserSnapshot;

  bool _isSaving = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _isChangingPassword = false;

  @override
  void initState() {
    super.initState();
    final user = widget.authRepository.getCurrentUser()!;
    _savedUserSnapshot = user;
    _fullNameController = TextEditingController(text: user.fullName);
    _emailController = TextEditingController(text: user.email);
    _birthdayController = TextEditingController(
      text: _formatBirthday(user.birthday),
    );
    _currentPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _selectedBirthday = user.birthday;
    _selectedCurrencyCode = user.preferredCurrencyCode;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _birthdayController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    return _fullNameController.text.trim() != _savedUserSnapshot.fullName ||
        _emailController.text.trim() != _savedUserSnapshot.email ||
        !_isSameDate(_selectedBirthday, _savedUserSnapshot.birthday) ||
        _selectedCurrencyCode != _savedUserSnapshot.preferredCurrencyCode ||
        _currentPasswordController.text.trim().isNotEmpty ||
        _newPasswordController.text.trim().isNotEmpty;
  }

  Future<void> _selectBirthday() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthday,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Select your birthday',
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _selectedBirthday = picked;
      _birthdayController.text = _formatBirthday(picked);
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    if (_isSaving || !_hasChanges || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final currentPassword = _currentPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();

    final result = await widget.authRepository.updateCurrentUser(
      email: _emailController.text.trim(),
      fullName: _fullNameController.text.trim(),
      birthday: _selectedBirthday,
      preferredCurrencyCode: _selectedCurrencyCode,
      notificationsEnabled: widget.authRepository
          .getCurrentUser()!
          .notificationsEnabled,
      reminderDays: widget.authRepository.getCurrentUser()!.reminderDays,
      currentPassword: currentPassword.isEmpty ? null : currentPassword,
      newPassword: newPassword.isEmpty ? null : newPassword,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.isSuccess
                ? 'Account updated.'
                : result.errorMessage ?? 'Unable to update your account.',
          ),
        ),
      );

    if (!result.isSuccess) {
      return;
    }

    _currentPasswordController.clear();
    _newPasswordController.clear();

    setState(() {
      _savedUserSnapshot = widget.authRepository.getCurrentUser()!;
      _showCurrentPassword = false;
      _showNewPassword = false;
      _isChangingPassword = false;
    });
  }

  Future<void> _logOut() async {
    FocusScope.of(context).unfocus();
    await widget.authRepository.logOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  void _togglePasswordEditing() {
    setState(() {
      _isChangingPassword = !_isChangingPassword;
      if (!_isChangingPassword) {
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _showCurrentPassword = false;
        _showNewPassword = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final userName = _fullNameController.text.trim().isEmpty
        ? _savedUserSnapshot.fullName
        : _fullNameController.text.trim();

    return Scaffold(
      appBar: const WishizAppBar(titleText: 'Account'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.pagePadding,
                  AppConstants.pagePadding,
                  AppConstants.pagePadding,
                  120,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth >= 720 ? 720 : 560,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroCard(
                          context,
                          colorScheme: colorScheme,
                          userName: userName,
                        ),
                        const SizedBox(height: AppConstants.sectionGap),
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              _buildSectionCard(
                                context,
                                icon: Icons.person_outline,
                                title: 'Personal details',
                                subtitle:
                                    'Keep the basics accurate so shared lists and reminders stay personal and easy to recognize.',
                                child: Column(
                                  children: [
                                    _buildLabeledField(
                                      context,
                                      label: 'Full name',
                                      hint:
                                          'How your name appears on wishlists',
                                      child: TextFormField(
                                        controller: _fullNameController,
                                        textInputAction: TextInputAction.next,
                                        decoration: const InputDecoration(
                                          hintText: 'Enter your full name',
                                          border: InputBorder.none,
                                        ),
                                        validator: _validateRequired,
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                    const SizedBox(
                                      height: AppConstants.itemGap,
                                    ),
                                    _buildLabeledField(
                                      context,
                                      label: 'Email address',
                                      hint:
                                          'Used for sign-in and account updates',
                                      child: TextFormField(
                                        controller: _emailController,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        textInputAction: TextInputAction.next,
                                        decoration: const InputDecoration(
                                          hintText: 'name@example.com',
                                          border: InputBorder.none,
                                        ),
                                        validator: _validateEmail,
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                    const SizedBox(
                                      height: AppConstants.itemGap,
                                    ),
                                    _buildLabeledField(
                                      context,
                                      label: 'Birthday',
                                      hint:
                                          'Helps personalize reminders and gifting moments',
                                      child: TextFormField(
                                        controller: _birthdayController,
                                        readOnly: true,
                                        onTap: _selectBirthday,
                                        decoration: const InputDecoration(
                                          hintText: 'Select your birthday',
                                          suffixIcon: Icon(
                                            Icons.calendar_today_outlined,
                                          ),
                                          border: InputBorder.none,
                                        ),
                                        validator: _validateRequired,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppConstants.sectionGap),
                              _buildSectionCard(
                                context,
                                icon: Icons.payments_outlined,
                                title: 'Shopping preferences',
                                subtitle:
                                    'Choose the currency you want to see by default when browsing item prices.',
                                child: _buildLabeledField(
                                  context,
                                  label: 'Default currency',
                                  hint:
                                      'This affects how prices are shown across the app',
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _selectedCurrencyCode,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                    ),
                                    items: AppUser.supportedCurrencyCodes
                                        .map(
                                          (code) => DropdownMenuItem(
                                            value: code,
                                            child: Text(_currencyLabel(code)),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedCurrencyCode = value ?? 'USD';
                                      });
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppConstants.sectionGap),
                              _buildSectionCard(
                                context,
                                icon: Icons.lock_outline,
                                title: 'Password',
                                subtitle:
                                    'Leave this alone if you do not want to change it. Showing it only when needed keeps the page simpler.',
                                child: Column(
                                  children: [
                                    _buildActionRow(
                                      context,
                                      title: 'Change password',
                                      description: _isChangingPassword
                                          ? 'Enter your current password once, then choose a new one.'
                                          : 'Optional. Open this only when you want to update your password.',
                                      action: OutlinedButton(
                                        onPressed: _togglePasswordEditing,
                                        child: Text(
                                          _isChangingPassword
                                              ? 'Cancel'
                                              : 'Edit password',
                                        ),
                                      ),
                                    ),
                                    if (_isChangingPassword) ...[
                                      const SizedBox(
                                        height: AppConstants.itemGap,
                                      ),
                                      _buildLabeledField(
                                        context,
                                        label: 'Current password',
                                        hint: 'Needed to confirm this change',
                                        child: TextFormField(
                                          controller:
                                              _currentPasswordController,
                                          obscureText: !_showCurrentPassword,
                                          decoration: InputDecoration(
                                            hintText: 'Enter current password',
                                            border: InputBorder.none,
                                            suffixIcon: IconButton(
                                              tooltip: _showCurrentPassword
                                                  ? 'Hide password'
                                                  : 'Show password',
                                              onPressed: () {
                                                setState(() {
                                                  _showCurrentPassword =
                                                      !_showCurrentPassword;
                                                });
                                              },
                                              icon: Icon(
                                                _showCurrentPassword
                                                    ? Icons
                                                          .visibility_off_outlined
                                                    : Icons.visibility_outlined,
                                              ),
                                            ),
                                          ),
                                          validator: _validateCurrentPassword,
                                        ),
                                      ),
                                      const SizedBox(
                                        height: AppConstants.itemGap,
                                      ),
                                      _buildLabeledField(
                                        context,
                                        label: 'New password',
                                        hint: 'Use at least 6 characters',
                                        child: TextFormField(
                                          controller: _newPasswordController,
                                          obscureText: !_showNewPassword,
                                          decoration: InputDecoration(
                                            hintText: 'Create new password',
                                            border: InputBorder.none,
                                            suffixIcon: IconButton(
                                              tooltip: _showNewPassword
                                                  ? 'Hide password'
                                                  : 'Show password',
                                              onPressed: () {
                                                setState(() {
                                                  _showNewPassword =
                                                      !_showNewPassword;
                                                });
                                              },
                                              icon: Icon(
                                                _showNewPassword
                                                    ? Icons
                                                          .visibility_off_outlined
                                                    : Icons.visibility_outlined,
                                              ),
                                            ),
                                          ),
                                          validator: _validateOptionalPassword,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppConstants.sectionGap),
                        _buildFooterActions(context, colorScheme),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context, {
    required ColorScheme colorScheme,
    required String userName,
  }) {
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
              _buildInfoChip(
                icon: Icons.mail_outline,
                label: _emailController.text.trim(),
              ),
              _buildInfoChip(
                icon: Icons.cake_outlined,
                label: _birthdayController.text,
              ),
              _buildInfoChip(
                icon: Icons.payments_outlined,
                label: _currencyLabel(_selectedCurrencyCode),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooterActions(BuildContext context, ColorScheme colorScheme) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _hasChanges
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
            onPressed: _isSaving || !_hasChanges ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(
                vertical: AppConstants.spacing4,
              ),
            ),
            child: Text(
              _isSaving
                  ? 'Saving...'
                  : _hasChanges
                  ? 'Save changes'
                  : 'No changes to save',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spacing3),
        TextButton.icon(
          onPressed: _isSaving ? null : _logOut,
          icon: const Icon(Icons.logout_outlined),
          label: const Text('Log out'),
        ),
      ],
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
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

  Widget _buildLabeledField(
    BuildContext context, {
    required String label,
    required String hint,
    required Widget child,
  }) {
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

  Widget _buildActionRow(
    BuildContext context, {
    required String title,
    required String description,
    required Widget action,
  }) {
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

  Widget _buildInfoChip({required IconData icon, required String label}) {
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

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _formatBirthday(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _currencyLabel(String code) {
    final symbol = AppUser.currencySymbols[code] ?? code;
    if (code == 'ILS') {
      return 'ILS / NIS ($symbol)';
    }
    return '$code ($symbol)';
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty || !trimmed.contains('@')) {
      return 'Please enter a valid email.';
    }
    return null;
  }

  String? _validateOptionalPassword(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length < 6) {
      return 'Use at least 6 characters for a new password.';
    }
    return null;
  }

  String? _validateCurrentPassword(String? value) {
    if (_newPasswordController.text.trim().isEmpty) {
      return null;
    }
    if ((value?.trim() ?? '').isEmpty) {
      return 'Enter your current password to change it.';
    }
    return null;
  }
}
