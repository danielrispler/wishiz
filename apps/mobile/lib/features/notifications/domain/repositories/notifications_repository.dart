import 'package:flutter/foundation.dart';
import 'package:wishiz/features/notifications/domain/entities/app_notification.dart';

/// Reactive access to the notification inbox. Implementations are
/// ValueNotifier-backed (no state-management lib), matching the app's
/// constructor-injected-repo convention.
abstract class NotificationsRepository {
  /// Unread event count — drives the bell badge.
  ValueListenable<int> watchUnreadCount();

  /// The loaded inbox, newest first.
  ValueListenable<List<AppNotification>> watchNotifications();

  /// Wishlist ids the current user has muted.
  ValueListenable<Set<String>> watchMutedListIds();

  /// Reload inbox, unread count and mutes from the server.
  Future<void> refresh();

  Future<void> markRead(String id);
  Future<void> markAllRead();

  Future<void> registerDevice({required String token, required String platform});
  Future<void> deregisterDevice(String token);

  Future<void> muteList(String wishlistId);
  Future<void> unmuteList(String wishlistId);
}
