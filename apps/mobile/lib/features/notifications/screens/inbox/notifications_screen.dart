import 'package:flutter/material.dart';
import 'package:wishiz/core/constants/app_constants.dart';
import 'package:wishiz/shared/widgets/wishiz_app_bar.dart';
import 'package:wishiz/features/auth/domain/entities/app_user.dart';
import 'package:wishiz/features/auth/domain/repositories/auth_repository.dart';
import 'package:wishiz/features/notifications/domain/entities/app_notification.dart';
import 'package:wishiz/features/notifications/domain/repositories/notifications_repository.dart';
import 'package:wishiz/features/notifications/screens/settings/reminder_settings_screen.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/repositories/wishlist_repository.dart';

/// The bell screen: a top Reminders section (client-computed aging items, gear =
/// reminder settings) and a Notifications section (durable event inbox). Only
/// the Notifications section drives the unread badge.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.authRepository,
    required this.wishlistRepository,
    required this.notificationsRepository,
    required this.currentUser,
    required this.onOpenWishlist,
    this.onOpenImportQueue,
  });

  final AuthRepository authRepository;
  final WishlistRepository wishlistRepository;
  final NotificationsRepository notificationsRepository;
  final AppUser currentUser;
  final void Function(String wishlistId) onOpenWishlist;
  final VoidCallback? onOpenImportQueue;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Pull fresh inbox/badge/mutes when the screen opens; failures are non-fatal.
    widget.notificationsRepository.refresh().catchError((Object _) {});
  }

  Future<void> _openReminderSettings() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReminderSettingsScreen(authRepository: widget.authRepository),
      ),
    );
  }

  void _openWishlist(String wishlistId) {
    Navigator.of(context).pop();
    widget.onOpenWishlist(wishlistId);
  }

  Future<void> _onNotificationTap(AppNotification notification) async {
    // Mark-read is optimistic — a failure must not block navigation (a throwing
    // markRead previously left the tap dead). Surface it, then route regardless.
    try {
      await widget.notificationsRepository.markRead(notification.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text("Couldn't update the notification.")));
      }
    }
    if (!mounted) return;
    final wishlistId = notification.wishlistId;
    if (wishlistId != null && wishlistId.isNotEmpty) {
      _openWishlist(wishlistId);
    } else if (notification.importJobId != null && widget.onOpenImportQueue != null) {
      Navigator.of(context).pop();
      widget.onOpenImportQueue!.call();
    }
  }

  Future<void> _onMarkAllRead() async {
    try {
      await widget.notificationsRepository.markAllRead();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text("Couldn't mark all as read.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lazy slivers (SliverList.builder) so a long inbox + reminder list is built on
    // demand, not all up-front. The listenables are lifted to wrap the whole
    // CustomScrollView, so the data still drives rebuilds while the rows stay lazy.
    return Scaffold(
      appBar: const WishizAppBar(titleText: 'Notifications'),
      body: SafeArea(
        child: ValueListenableBuilder<AppUser?>(
          valueListenable: widget.authRepository.watchCurrentUser(),
          builder: (context, user, _) {
            final currentUser = user ?? widget.currentUser;
            final remindersEnabled = currentUser.notificationsEnabled;
            return ValueListenableBuilder<List<Wishlist>>(
              valueListenable: widget.wishlistRepository.watchWishlists(),
              builder: (context, wishlists, _) {
                final reminders = remindersEnabled
                    ? _agingReminders(wishlists, currentUser.reminderDays)
                    : const <_AgingReminder>[];
                return ValueListenableBuilder<List<AppNotification>>(
                  valueListenable: widget.notificationsRepository.watchNotifications(),
                  builder: (context, notifications, _) {
                    return CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            AppConstants.pagePadding,
                            AppConstants.spacing4,
                            AppConstants.pagePadding,
                            120,
                          ),
                          sliver: SliverMainAxisGroup(
                            slivers: [
                              _remindersHeaderSliver(),
                              const SliverToBoxAdapter(child: SizedBox(height: AppConstants.itemGap)),
                              _remindersSliver(remindersEnabled, reminders),
                              const SliverToBoxAdapter(child: SizedBox(height: AppConstants.sectionGap)),
                              _notificationsHeaderSliver(),
                              const SliverToBoxAdapter(child: SizedBox(height: AppConstants.itemGap)),
                              _notificationsSliver(notifications),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _remindersHeaderSliver() {
    return SliverToBoxAdapter(
      child: _sectionHeader(
        context,
        'Reminders',
        trailing: IconButton(
          tooltip: 'Reminder settings',
          onPressed: _openReminderSettings,
          icon: const Icon(Icons.settings_outlined),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  Widget _remindersSliver(bool enabled, List<_AgingReminder> reminders) {
    if (!enabled) {
      return SliverToBoxAdapter(child: _emptyHint('Reminders are off. Turn them on in settings.'));
    }
    if (reminders.isEmpty) {
      return SliverToBoxAdapter(
        child: _emptyHint('Nothing waiting yet. Saved items show up here once they age.'),
      );
    }
    return SliverList.builder(
      itemCount: reminders.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: AppConstants.itemGap),
        child: _reminderCard(reminders[index]),
      ),
    );
  }

  Widget _notificationsHeaderSliver() {
    return SliverToBoxAdapter(
      child: ValueListenableBuilder<int>(
        valueListenable: widget.notificationsRepository.watchUnreadCount(),
        builder: (context, unread, _) {
          return _sectionHeader(
            context,
            'Notifications',
            trailing: TextButton(
              onPressed: unread > 0 ? _onMarkAllRead : null,
              child: const Text('Mark all read'),
            ),
          );
        },
      ),
    );
  }

  Widget _notificationsSliver(List<AppNotification> notifications) {
    if (notifications.isEmpty) {
      return SliverToBoxAdapter(
        child: _emptyHint('No notifications yet. Activity on your shared lists shows up here.'),
      );
    }
    return SliverList.builder(
      itemCount: notifications.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: AppConstants.itemGap),
        child: _notificationCard(notifications[index]),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, {Widget? trailing}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _card({required Widget child, VoidCallback? onTap}) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(AppConstants.cardPadding), child: child),
      ),
    );
  }

  Widget _reminderCard(_AgingReminder reminder) {
    final theme = Theme.of(context);
    return _card(
      onTap: () => _openWishlist(reminder.wishlistId),
      child: Row(
        children: [
          Icon(Icons.schedule_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: AppConstants.itemGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reminder.itemTitle, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'Waiting ${reminder.days} day${reminder.days == 1 ? '' : 's'} · ${reminder.wishlistTitle}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notificationCard(AppNotification notification) {
    final theme = Theme.of(context);
    return _card(
      onTap: () => _onNotificationTap(notification),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: notification.isRead ? Colors.transparent : theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.itemGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: notification.isRead ? FontWeight.w500 : FontWeight.w700,
                  ),
                ),
                if (notification.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    notification.body,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppConstants.itemGap),
          Text(
            _relativeTime(notification.createdAt),
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint(String message) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.itemGap),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  List<_AgingReminder> _agingReminders(List<Wishlist> wishlists, int reminderDays) {
    final now = DateTime.now();
    final minimumAge = Duration(days: reminderDays);
    final reminders = <_AgingReminder>[];
    for (final wishlist in wishlists.where((w) => !w.isArchived)) {
      for (final item in wishlist.activeItems) {
        final waited = now.difference(item.createdAt);
        if (waited >= minimumAge) {
          reminders.add(_AgingReminder(
            wishlistId: wishlist.id,
            wishlistTitle: wishlist.title,
            itemTitle: item.title,
            days: waited.inDays,
          ));
        }
      }
    }
    reminders.sort((a, b) => b.days.compareTo(a.days));
    return reminders;
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }
}

class _AgingReminder {
  const _AgingReminder({
    required this.wishlistId,
    required this.wishlistTitle,
    required this.itemTitle,
    required this.days,
  });

  final String wishlistId;
  final String wishlistTitle;
  final String itemTitle;
  final int days;
}
