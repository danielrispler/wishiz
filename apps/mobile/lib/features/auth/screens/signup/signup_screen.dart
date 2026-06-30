import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
    required this.authRepository,
    required this.onShowLogin,
  });

  final AuthRepository authRepository;
  final VoidCallback onShowLogin;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final result = await widget.authRepository.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _fullNameController.text.trim(),
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
              message.isEmpty ? 'An unexpected error occurred.' : message,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.pagePadding,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppConstants.pagePadding,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: AppConstants.spacing4),
                          Text(
                            'Create Account',
                            style: Theme.of(context).textTheme.displaySmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppConstants.spacing4),
                          Text(
                            'Create your account and keep your wishlists synced with the backend.',
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
                                    controller: _passwordController,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Password',
                                      border: InputBorder.none,
                                    ),
                                    validator: _validatePassword,
                                  ),
                                ),
                                const SizedBox(height: AppConstants.itemGap),
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
                          const SizedBox(height: AppConstants.sectionGap),
                          Container(
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
                              onPressed: _isSubmitting ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppConstants.spacing4,
                                ),
                              ),
                              child: Text(
                                _isSubmitting
                                    ? 'Creating Account...'
                                    : 'Sign Up',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppConstants.spacing4),
                          TextButton(
                            onPressed: widget.onShowLogin,
                            child: const Text(
                              'Already have an account? Log in',
                            ),
                          ),
                        ],
                      ),
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
}
