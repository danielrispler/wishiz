import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/shared/widgets/wishiz_app_bar.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'components/account_actions_section.dart';
import 'components/account_delete_dialog.dart';
import 'components/account_form_section.dart';
import 'components/account_hero_card.dart';

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

  DateTime? _selectedBirthday;
  late String? _selectedGender;
  late String _selectedCurrencyCode;
  late AppUser _savedUserSnapshot;

  bool _isSaving = false;
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
    _selectedGender = user.gender;
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
        _selectedGender != _savedUserSnapshot.gender ||
        _selectedCurrencyCode != _savedUserSnapshot.preferredCurrencyCode ||
        _currentPasswordController.text.trim().isNotEmpty ||
        _newPasswordController.text.trim().isNotEmpty;
  }

  Future<void> _selectBirthday() async {
    final initialDate =
        _selectedBirthday ??
        DateTime.now().subtract(const Duration(days: 365 * 18));
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Select your birthday',
    );
    if (picked == null) return;
    setState(() {
      _selectedBirthday = picked;
      _birthdayController.text = _formatBirthday(picked);
    });
  }

  void _clearBirthday() {
    setState(() {
      _selectedBirthday = null;
      _birthdayController.clear();
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_isSaving || !_hasChanges || !_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final currentPassword = _currentPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final user = widget.authRepository.getCurrentUser()!;
    final result = await widget.authRepository.updateCurrentUser(
      email: _emailController.text.trim(),
      fullName: _fullNameController.text.trim(),
      birthday: _selectedBirthday,
      gender: _selectedGender,
      preferredCurrencyCode: _selectedCurrencyCode,
      notificationsEnabled: user.notificationsEnabled,
      reminderDays: user.reminderDays,
      currentPassword: currentPassword.isEmpty ? null : currentPassword,
      newPassword: newPassword.isEmpty ? null : newPassword,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

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

    if (!result.isSuccess) return;

    _currentPasswordController.clear();
    _newPasswordController.clear();
    setState(() {
      _savedUserSnapshot = widget.authRepository.getCurrentUser()!;
      _isChangingPassword = false;
    });
  }

  Future<void> _logOut() async {
    FocusScope.of(context).unfocus();
    await widget.authRepository.logOut();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _deleteAccount() async {
    FocusScope.of(context).unfocus();
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) =>
          AccountDeleteDialog(authRepository: widget.authRepository),
    );
    if (deleted != true || !mounted) return;
    // The session is now cleared, so the auth gate shows the login screen
    // underneath; pop this screen to reveal it.
    Navigator.of(context).pop();
  }

  void _togglePasswordEditing() {
    setState(() {
      _isChangingPassword = !_isChangingPassword;
      if (!_isChangingPassword) {
        _currentPasswordController.clear();
        _newPasswordController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
                        AccountHeroCard(
                          colorScheme: colorScheme,
                          userName: userName,
                          email: _emailController.text.trim(),
                          birthday: _birthdayController.text,
                          currencyLabel: _currencyLabel(_selectedCurrencyCode),
                        ),
                        const SizedBox(height: AppConstants.sectionGap),
                        AccountFormSection(
                          formKey: _formKey,
                          fullNameController: _fullNameController,
                          emailController: _emailController,
                          birthdayController: _birthdayController,
                          currentPasswordController: _currentPasswordController,
                          newPasswordController: _newPasswordController,
                          selectedGender: _selectedGender,
                          selectedCurrencyCode: _selectedCurrencyCode,
                          isChangingPassword: _isChangingPassword,
                          onSelectBirthday: _selectBirthday,
                          onClearBirthday: _clearBirthday,
                          onGenderChanged: (gender) =>
                              setState(() => _selectedGender = gender),
                          onTogglePasswordEditing: _togglePasswordEditing,
                          onCurrencyChanged: (code) =>
                              setState(() => _selectedCurrencyCode = code),
                          onFieldChanged: () => setState(() {}),
                          validateRequired: _validateRequired,
                          validateEmail: _validateEmail,
                          validateCurrentPassword: _validateCurrentPassword,
                          validateOptionalPassword: _validateOptionalPassword,
                        ),
                        const SizedBox(height: AppConstants.sectionGap),
                        AccountActionsSection(
                          isSaving: _isSaving,
                          hasChanges: _hasChanges,
                          onSave: _save,
                          onLogOut: _logOut,
                          onDeleteAccount: _deleteAccount,
                        ),
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

  bool _isSameDate(DateTime? left, DateTime? right) {
    if (left == null || right == null) {
      return left == right;
    }
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _formatBirthday(DateTime? value) {
    if (value == null) {
      return '';
    }
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _currencyLabel(String code) {
    final symbol = AppUser.currencySymbols[code] ?? code;
    if (code == 'ILS') return 'ILS / NIS ($symbol)';
    return '$code ($symbol)';
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) return 'This field is required.';
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
    if (trimmed.isEmpty) return null;
    if (trimmed.length < 6) {
      return 'Use at least 6 characters for a new password.';
    }
    return null;
  }

  String? _validateCurrentPassword(String? value) {
    if (_newPasswordController.text.trim().isEmpty) return null;
    if ((value?.trim() ?? '').isEmpty) {
      return 'Enter your current password to change it.';
    }
    return null;
  }
}
