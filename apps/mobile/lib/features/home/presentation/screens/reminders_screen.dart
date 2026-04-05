import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/core/widgets/wishiz_app_bar.dart';
import 'package:wishiz/core/utils/currency_utils.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';
import 'package:wishiz/features/wishlists/presentation/screens/wishlist_detail_screen.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({
    super.key,
    required this.repository,
    required this.authRepository,
    required this.sharedProductRepository,
  });

  final WishlistRepository repository;
  final AuthRepository authRepository;
  final SharedProductRepository sharedProductRepository;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  static const int _allYears = -1;

  String _searchQuery = '';
  int _searchFieldVersion = 0;
  int _selectedYear = _allYears;
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

  Future<void> _openWishlistDetails(String wishlistId) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WishlistDetailScreen(
          repository: widget.repository,
          authRepository: widget.authRepository,
          sharedProductRepository: widget.sharedProductRepository,
          wishlistId: wishlistId,
        ),
      ),
    );
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

  List<int> _availableYears(List<Wishlist> wishlists) {
    final years = wishlists.map((wishlist) => wishlist.year).toSet().toList()
      ..sort((left, right) => right.compareTo(left));
    return years;
  }

  List<_ReminderEntry> _buildReminderEntries(List<Wishlist> wishlists) {
    if (!_notificationsEnabled) {
      return const [];
    }

    final now = DateTime.now();
    final minimumAge = Duration(days: _reminderDays);
    final reminders = <_ReminderEntry>[];

    for (final wishlist in wishlists) {
      for (final item in wishlist.activeItems) {
        final age = now.difference(item.createdAt);
        if (age < minimumAge) {
          continue;
        }

        reminders.add(
          _ReminderEntry(
            wishlist: wishlist,
            item: item,
            daysWaiting: age.inDays,
          ),
        );
      }
    }

    reminders.sort((left, right) {
      final dayComparison = right.daysWaiting.compareTo(left.daysWaiting);
      if (dayComparison != 0) {
        return dayComparison;
      }
      return left.item.rank.compareTo(right.item.rank);
    });

    return reminders;
  }

  List<_ReminderEntry> _filterReminders(List<_ReminderEntry> reminders) {
    final query = _searchQuery.toLowerCase();

    return reminders
        .where((reminder) {
          final matchesQuery =
              query.isEmpty ||
              reminder.item.title.toLowerCase().contains(query) ||
              reminder.wishlist.title.toLowerCase().contains(query);
          final matchesYear =
              _selectedYear == _allYears ||
              reminder.wishlist.year == _selectedYear;
          return matchesQuery && matchesYear;
        })
        .toList(growable: false);
  }

  Widget _buildSearchAndFilters({
    required String hintText,
    required List<int> availableYears,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.cardPadding,
            vertical: 2,
          ),
          child: TextFormField(
            key: ValueKey('$hintText-$_searchFieldVersion'),
            initialValue: _searchQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              icon: const Icon(Icons.search),
              hintText: hintText,
              border: InputBorder.none,
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _searchFieldVersion += 1;
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.trim();
              });
            },
          ),
        ),
        const SizedBox(height: AppConstants.itemGap),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.cardPadding,
            vertical: 2,
          ),
          child: DropdownButtonFormField<int>(
            value: _selectedYear,
            decoration: const InputDecoration(
              labelText: 'Filter by year',
              border: InputBorder.none,
            ),
            items: [
              const DropdownMenuItem(
                value: _allYears,
                child: Text('All years'),
              ),
              ...availableYears.map(
                (year) =>
                    DropdownMenuItem(value: year, child: Text(year.toString())),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedYear = value ?? _allYears;
              });
            },
          ),
        ),
      ],
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

  Widget _buildReminderCard(_ReminderEntry reminder, AppUser currentUser) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.itemGap),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reminder.item.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '${reminder.wishlist.title} · ${reminder.wishlist.year}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Saved ${reminder.daysWaiting} day${reminder.daysWaiting == 1 ? '' : 's'} ago.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (reminder.item.priceLabel != null &&
              reminder.item.priceLabel!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              CurrencyUtils.convertPriceLabel(
                    reminder.item.priceLabel,
                    targetCurrencyCode: currentUser.preferredCurrencyCode,
                  ) ??
                  reminder.item.priceLabel!,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
          const SizedBox(height: AppConstants.sectionGap),
          Wrap(
            spacing: AppConstants.spacing2,
            runSpacing: AppConstants.spacing2,
            children: [
              TextButton.icon(
                onPressed: () => _openWishlistDetails(reminder.wishlist.id),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Open List'),
              ),
              if (reminder.item.productUrl != null &&
                  reminder.item.productUrl!.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _openWishlistDetails(reminder.wishlist.id),
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: const Text('View in List'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
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
        child: ValueListenableBuilder<List<Wishlist>>(
          valueListenable: widget.repository.watchWishlists(),
          builder: (context, wishlists, _) {
            final visibleWishlists = wishlists
                .where((wishlist) => !wishlist.isArchived)
                .toList(growable: false);
            final availableYears = _availableYears(visibleWishlists);
            final reminders = _filterReminders(
              _buildReminderEntries(visibleWishlists),
            );

            return ListView(
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
                const SizedBox(height: AppConstants.spacing4),
                _buildSearchAndFilters(
                  hintText: 'Search reminders',
                  availableYears: availableYears,
                ),
                const SizedBox(height: AppConstants.sectionGap),
                if (!_notificationsEnabled)
                  _buildEmptyState(
                    title: 'Reminders are turned off',
                    description:
                        'Enable reminder notifications above and choose how long items should wait before showing up here.',
                  )
                else if (reminders.isEmpty)
                  _buildEmptyState(
                    title: _searchQuery.isEmpty && _selectedYear == _allYears
                        ? 'No reminders yet'
                        : 'No matching reminders',
                    description:
                        _searchQuery.isEmpty && _selectedYear == _allYears
                        ? 'When saved items sit on your wishlist longer than your chosen reminder window, they will show up here.'
                        : 'Try another search term or clear the year filter.',
                  )
                else
                  ...reminders.map(
                    (reminder) => _buildReminderCard(reminder, currentUser),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReminderEntry {
  const _ReminderEntry({
    required this.wishlist,
    required this.item,
    required this.daysWaiting,
  });

  final Wishlist wishlist;
  final WishlistItem item;
  final int daysWaiting;
}
