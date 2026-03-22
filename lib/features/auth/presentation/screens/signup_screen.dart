import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
    required this.authRepository,
    required this.onShowLogin,
    this.showBirthdayPicker,
  });

  final AuthRepository authRepository;
  final VoidCallback onShowLogin;
  final Future<DateTime?> Function(BuildContext context, DateTime initialDate)?
      showBirthdayPicker;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _birthdayController = TextEditingController();
  DateTime? _selectedBirthday;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _birthdayController.dispose();
    super.dispose();
  }

  Future<void> _selectBirthday() async {
    final initialDate = _selectedBirthday ??
        DateTime.now().subtract(const Duration(days: 365 * 18));
    final picked =
        await (widget.showBirthdayPicker?.call(context, initialDate) ??
            showDatePicker(
              context: context,
              initialDate: initialDate,
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            ));
    if (picked != null) {
      setState(() {
        _selectedBirthday = picked;
        _birthdayController.text = _formatBirthday(picked);
      });
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting ||
        !_formKey.currentState!.validate() ||
        _selectedBirthday == null) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final result = await widget.authRepository.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        birthday: _selectedBirthday!,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
      });

      if (result.isSuccess) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(result.errorMessage ?? 'Unable to sign up.')),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      final message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
              content: Text(
                  message.isEmpty ? 'An unexpected error occurred.' : message)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(AppConstants.spacing4),
              children: [
                const SizedBox(height: AppConstants.spacing8),
                Text(
                  'Create Account',
                  style: Theme.of(context).textTheme.displaySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppConstants.spacing4),
                Text(
                  'Sign up once and keep using the app offline until the backend arrives.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppConstants.spacing8),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildFieldCard(
                        context,
                        child: TextFormField(
                          controller: _firstNameController,
                          decoration: const InputDecoration(
                            labelText: 'First name',
                            border: InputBorder.none,
                          ),
                          validator: _validateRequired,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacing3),
                      _buildFieldCard(
                        context,
                        child: TextFormField(
                          controller: _lastNameController,
                          decoration: const InputDecoration(
                            labelText: 'Last name',
                            border: InputBorder.none,
                          ),
                          validator: _validateRequired,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacing3),
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
                          validator: _validateBirthday,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacing3),
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
                      const SizedBox(height: AppConstants.spacing3),
                      _buildFieldCard(
                        context,
                        child: TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: InputBorder.none,
                          ),
                          validator: _validatePassword,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacing3),
                      _buildFieldCard(
                        context,
                        child: TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            border: InputBorder.none,
                          ),
                          validator: _validateConfirmPassword,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppConstants.spacing6),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primary,
                        colorScheme.primaryContainer,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppConstants.spacing4,
                      ),
                    ),
                    child: Text(
                      _isSubmitting ? 'Creating Account...' : 'Sign Up',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacing4),
                TextButton(
                  onPressed: widget.onShowLogin,
                  child: const Text('Already have an account? Log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldCard(
    BuildContext context, {
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing4,
        vertical: AppConstants.spacing3,
      ),
      child: child,
    );
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

  String? _validatePassword(String? value) {
    if (value == null || value.length < 6) {
      return 'Please enter at least 6 characters.';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value != _passwordController.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  String? _validateBirthday(String? value) {
    if (_selectedBirthday == null) {
      return 'Please specify your birthday.';
    }
    return null;
  }

  String _formatBirthday(DateTime birthday) {
    final month = birthday.month.toString().padLeft(2, '0');
    final day = birthday.day.toString().padLeft(2, '0');
    return '${birthday.year}-$month-$day';
  }
}
