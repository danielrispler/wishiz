import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/shared/widgets/wishiz_app_bar.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';

/// Settings for the aging-item reminders: the master notifications toggle
/// (app_users.notifications_enabled — also gates event notifications) and the
/// reminder-days window. Opened from the gear in the Reminders section of the
/// notifications inbox.
class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  late bool _notificationsEnabled;
  late int _reminderDays;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = widget.authRepository.getCurrentUser()!;
    _notificationsEnabled = user.notificationsEnabled;
    _reminderDays = user.reminderDays;
  }

  Future<void> _save(AppUser currentUser) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final result = await widget.authRepository.updateCurrentUser(
      email: currentUser.email,
      fullName: currentUser.fullName,
      birthday: currentUser.birthday,
      gender: currentUser.gender,
      preferredCurrencyCode: currentUser.preferredCurrencyCode,
      notificationsEnabled: _notificationsEnabled,
      reminderDays: _reminderDays,
    );

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (!result.isSuccess) {
        _notificationsEnabled = currentUser.notificationsEnabled;
        _reminderDays = currentUser.reminderDays;
      }
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.isSuccess
                ? 'Notification settings updated.'
                : result.errorMessage ?? 'Unable to update notification settings.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = widget.authRepository.getCurrentUser()!;

    return Scaffold(
      appBar: const WishizAppBar(titleText: 'Notification settings'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.pagePadding,
            AppConstants.spacing4,
            AppConstants.pagePadding,
            120,
          ),
          children: [
            Text(
              _notificationsEnabled
                  ? 'Master switch for all Wishiz notifications. Reminders nudge you about saved '
                        'items that have been waiting $_reminderDays day${_reminderDays == 1 ? '' : 's'} or longer.'
                  : 'Notifications are off. Turn them back on to get reminders and updates when '
                        'people join your lists or items are added.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppConstants.sectionGap),
            _buildCard(currentUser),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(AppUser currentUser) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppConstants.itemGap),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable notifications'),
            subtitle: const Text(
              'Reminders for waiting items, plus updates when collaborators join or change your lists.',
            ),
            value: _notificationsEnabled,
            onChanged: _isSaving
                ? null
                : (value) => setState(() => _notificationsEnabled = value),
          ),
          const SizedBox(height: AppConstants.itemGap),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Remind me after $_reminderDays day${_reminderDays == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Text('$_reminderDays', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          Slider(
            value: _reminderDays.toDouble(),
            min: 1,
            max: 60,
            divisions: 59,
            label: '$_reminderDays days',
            onChanged: _notificationsEnabled && !_isSaving
                ? (value) => setState(() => _reminderDays = value.round())
                : null,
          ),
          const SizedBox(height: AppConstants.itemGap),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed:
                  _isSaving ||
                      (_notificationsEnabled == currentUser.notificationsEnabled &&
                          _reminderDays == currentUser.reminderDays)
                  ? null
                  : () => _save(currentUser),
              child: Text(_isSaving ? 'Saving...' : 'Update settings'),
            ),
          ),
        ],
      ),
    );
  }
}
