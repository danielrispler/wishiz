import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
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

  bool _isSaving = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;

  @override
  void initState() {
    super.initState();
    final user = widget.authRepository.getCurrentUser()!;
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

  Future<void> _selectBirthday() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthday,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
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
    if (_isSaving || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final result = await widget.authRepository.updateCurrentUser(
      email: _emailController.text.trim(),
      fullName: _fullNameController.text.trim(),
      birthday: _selectedBirthday,
      preferredCurrencyCode: _selectedCurrencyCode,
      notificationsEnabled: widget.authRepository
          .getCurrentUser()!
          .notificationsEnabled,
      reminderDays: widget.authRepository.getCurrentUser()!.reminderDays,
      currentPassword: _currentPasswordController.text.trim().isEmpty
          ? null
          : _currentPasswordController.text,
      newPassword: _newPasswordController.text.trim().isEmpty
          ? null
          : _newPasswordController.text,
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

    if (result.isSuccess) {
      _currentPasswordController.clear();
      _newPasswordController.clear();
    }
  }

  Future<void> _logOut() async {
    await widget.authRepository.logOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.pagePadding,
            AppConstants.pagePadding,
            AppConstants.pagePadding,
            120,
          ),
          children: [
            Text(
              'Manage your profile, password, and default pricing currency.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppConstants.sectionGap),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildFieldCard(
                    context,
                    child: TextFormField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        border: InputBorder.none,
                      ),
                      validator: _validateRequired,
                    ),
                  ),
                  const SizedBox(height: AppConstants.itemGap),
                  _buildFieldCard(
                    context,
                    child: TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: InputBorder.none,
                      ),
                      validator: _validateEmail,
                    ),
                  ),
                  const SizedBox(height: AppConstants.itemGap),
                  _buildFieldCard(
                    context,
                    child: TextFormField(
                      controller: _birthdayController,
                      readOnly: true,
                      onTap: _selectBirthday,
                      decoration: const InputDecoration(
                        labelText: 'Birthday',
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                        border: InputBorder.none,
                      ),
                      validator: _validateRequired,
                    ),
                  ),
                  const SizedBox(height: AppConstants.itemGap),
                  _buildFieldCard(
                    context,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Password',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: AppConstants.spacing2),
                        Text(
                          'Current password is hidden for safety. Add a new password below to change it.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppConstants.itemGap),
                        TextFormField(
                          controller: _currentPasswordController,
                          obscureText: !_showCurrentPassword,
                          decoration: InputDecoration(
                            labelText: 'Current password',
                            border: InputBorder.none,
                            suffixIcon: IconButton(
                              tooltip: _showCurrentPassword
                                  ? 'Hide password'
                                  : 'Show password',
                              onPressed: () {
                                setState(() {
                                  _showCurrentPassword = !_showCurrentPassword;
                                });
                              },
                              icon: Icon(
                                _showCurrentPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          validator: _validateCurrentPassword,
                        ),
                        const SizedBox(height: AppConstants.itemGap),
                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: !_showNewPassword,
                          decoration: InputDecoration(
                            labelText: 'New password',
                            border: InputBorder.none,
                            suffixIcon: IconButton(
                              tooltip: _showNewPassword
                                  ? 'Hide password'
                                  : 'Show password',
                              onPressed: () {
                                setState(() {
                                  _showNewPassword = !_showNewPassword;
                                });
                              },
                              icon: Icon(
                                _showNewPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          validator: _validateOptionalPassword,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppConstants.sectionGap),
                  _buildSectionCard(
                    context,
                    title: 'Pricing',
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCurrencyCode,
                      decoration: const InputDecoration(
                        labelText: 'Default currency for item prices',
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
                ],
              ),
            ),
            const SizedBox(height: AppConstants.sectionGap),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.primaryContainer],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppConstants.spacing4,
                  ),
                ),
                child: Text(
                  _isSaving ? 'Saving...' : 'Update Account',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            const SizedBox(height: AppConstants.itemGap),
            TextButton.icon(
              onPressed: _logOut,
              icon: const Icon(Icons.logout_outlined),
              label: const Text('Log Out'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldCard(BuildContext context, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.cardPadding,
        vertical: AppConstants.itemGap,
      ),
      child: child,
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppConstants.itemGap),
          child,
        ],
      ),
    );
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
