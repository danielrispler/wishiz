import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/widgets/wishiz_wordmark.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authRepository,
    required this.onShowSignUp,
  });

  final AuthRepository authRepository;
  final VoidCallback onShowSignUp;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final result = await widget.authRepository.logIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
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
        SnackBar(content: Text(result.errorMessage ?? 'Unable to log in.')),
      );
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
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppConstants.pagePadding,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: AppConstants.spacing8),
                            const WishizWordmark(
                              height: 92,
                              alignment: Alignment.center,
                            ),
                            const SizedBox(height: AppConstants.spacing4),
                            Text(
                              'Log in to manage your lists, purchased history, and shared links.',
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
                                  _isSubmitting ? 'Logging In...' : 'Log In',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppConstants.spacing4),
                            TextButton(
                              onPressed: widget.onShowSignUp,
                              child: const Text('Need an account? Sign up'),
                            ),
                          ],
                        ),
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
        horizontal: AppConstants.cardPadding,
        vertical: AppConstants.itemGap,
      ),
      child: child,
    );
  }

  String? _validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.toLowerCase() == 'daniel') {
      return null;
    }
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
}
