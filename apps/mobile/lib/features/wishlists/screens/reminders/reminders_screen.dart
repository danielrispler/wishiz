import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/shared/widgets/wishiz_app_bar.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({
    super.key,
    required this.authRepository,
  });

  final AuthRepository authRepository;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  late bool _notificationsEnabled;
  late int _reminderDays;
  bool _isSavingReminderSettings = false;

  @override
  void initState() {
    super.initState();
    final user = widget.authRepository.getCurrentUser()!;
    _notificationsEnabled = user.notificationsEnabled;
    _reminderDays = user.reminderDays;
  }

  Future<void> _saveReminderSettings(AppUser currentUser) async {
    if (_isSavingReminderSettings) {
      return;
    }

    setState(() {
      _isSavingReminderSettings = true;
    });

    final result = await widget.authRepository.updateCurrentUser(
      email: currentUser.email,
      fullName: currentUser.fullName,
      birthday: currentUser.birthday,
      preferredCurrencyCode: currentUser.preferredCurrencyCode,
      notificationsEnabled: _notificationsEnabled,
      reminderDays: _reminderDays,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSavingReminderSettings = false;
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
                ? 'Reminder settings updated.'
                : result.errorMessage ?? 'Unable to update reminder settings.',
          ),
        ),
      );
  }

  Widget _buildReminderSettingsCard(AppUser currentUser) {
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
            title: const Text('Enable wishlist reminders'),
            subtitle: const Text(
              'Show reminders inside the app when saved items have been waiting too long.',
            ),
            value: _notificationsEnabled,
            onChanged: _isSavingReminderSettings
                ? null
                : (value) {
                    setState(() {
                      _notificationsEnabled = value;
                    });
                  },
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
              Text(
                '$_reminderDays',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          Slider(
            value: _reminderDays.toDouble(),
            min: 1,
            max: 60,
            divisions: 59,
            label: '$_reminderDays days',
            onChanged: _notificationsEnabled && !_isSavingReminderSettings
                ? (value) {
                    setState(() {
                      _reminderDays = value.round();
                    });
                  }
                : null,
          ),
          const SizedBox(height: AppConstants.itemGap),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed:
                  _isSavingReminderSettings ||
                          (_notificationsEnabled ==
                                  currentUser.notificationsEnabled &&
                              _reminderDays == currentUser.reminderDays)
                      ? null
                      : () => _saveReminderSettings(currentUser),
              child: Text(
                _isSavingReminderSettings
                    ? 'Saving...'
                    : 'Update Reminder Settings',
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = widget.authRepository.getCurrentUser()!;

    return Scaffold(
      appBar: const WishizAppBar(titleText: 'Reminders'),
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
                  ? 'Items appear here once they have been waiting for $_reminderDays days or longer.'
                  : 'Reminder notifications are off right now. Turn them back on here whenever you want the app to nudge you again.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppConstants.sectionGap),
            _buildReminderSettingsCard(currentUser),
          ],
        ),
      ),
    );
  }
}
