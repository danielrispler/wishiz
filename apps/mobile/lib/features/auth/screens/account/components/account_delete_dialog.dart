import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/features/auth/data/api/auth_api_client.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';

/// Confirmation dialog for permanent account deletion. Warns that owned shared
/// lists are removed for everyone, requires the account password, and only pops
/// with `true` once the deletion has succeeded server-side. A wrong password is
/// surfaced inline so the user can retry without losing the dialog.
class AccountDeleteDialog extends StatefulWidget {
  const AccountDeleteDialog({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<AccountDeleteDialog> createState() => _AccountDeleteDialogState();
}

class _AccountDeleteDialogState extends State<AccountDeleteDialog> {
  final _passwordController = TextEditingController();
  bool _isDeleting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Enter your password to confirm.');
      return;
    }

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      await widget.authRepository.deleteAccount(password: password);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
        _errorMessage = _friendlyError(error);
      });
    }
  }

  String _friendlyError(Object error) {
    if (error is AuthApiException) {
      return error.message;
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Delete account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This permanently deletes your account and data. Any lists you own '
            'are removed for everyone they are shared with. This cannot be undone.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppConstants.spacing4),
          TextField(
            controller: _passwordController,
            obscureText: true,
            enabled: !_isDeleting,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Password',
              hintText: 'Enter your password to confirm',
              errorText: _errorMessage,
            ),
            onSubmitted: (_) => _isDeleting ? null : _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isDeleting ? null : _confirm,
          style: TextButton.styleFrom(foregroundColor: colorScheme.error),
          child: Text(_isDeleting ? 'Deleting...' : 'Delete account'),
        ),
      ],
    );
  }
}
