import 'package:flutter/foundation.dart';
import 'package:wishiz/features/notifications/domain/entities/app_notification.dart';
import 'package:wishiz/features/notifications/domain/repositories/notifications_repository.dart';

/// In-memory NotificationsRepository for the default (no-backend) wiring and
/// widget tests. Seed via [seed]/[seedMutes]; mutations update the notifiers so
/// ValueListenableBuilder-driven UI rebuilds exactly as with the API repo.
class InMemoryNotificationsRepository implements NotificationsRepository {
  InMemoryNotificationsRepository({
    List<AppNotification> initial = const [],
    Set<String> mutedListIds = const <String>{},
  }) : _notifications = ValueNotifier<List<AppNotification>>(List.unmodifiable(initial)),
       _mutedListIds = ValueNotifier<Set<String>>(Set.unmodifiable(mutedListIds)) {
    _unreadCount = ValueNotifier<int>(initial.where((n) => !n.isRead).length);
  }

  final ValueNotifier<List<AppNotification>> _notifications;
  late final ValueNotifier<int> _unreadCount;
  final ValueNotifier<Set<String>> _mutedListIds;

  void seed(List<AppNotification> notifications) {
    _notifications.value = List.unmodifiable(notifications);
    _unreadCount.value = notifications.where((n) => !n.isRead).length;
  }

  void seedMutes(Set<String> wishlistIds) {
    _mutedListIds.value = Set.unmodifiable(wishlistIds);
  }

  @override
  ValueListenable<List<AppNotification>> watchNotifications() => _notifications;

  @override
  ValueListenable<int> watchUnreadCount() => _unreadCount;

  @override
  ValueListenable<Set<String>> watchMutedListIds() => _mutedListIds;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> markRead(String id) async {
    final wasUnread = _notifications.value.any((n) => n.id == id && !n.isRead);
    if (!wasUnread) return;
    final now = DateTime.now();
    _notifications.value = List.unmodifiable(
      _notifications.value.map((n) => n.id == id ? n.copyWith(readAt: now) : n),
    );
    _unreadCount.value = (_unreadCount.value - 1).clamp(0, 1 << 31);
  }

  @override
  Future<void> markAllRead() async {
    final now = DateTime.now();
    _notifications.value = List.unmodifiable(
      _notifications.value.map((n) => n.isRead ? n : n.copyWith(readAt: now)),
    );
    _unreadCount.value = 0;
  }

  @override
  Future<void> registerDevice({required String token, required String platform}) async {}

  @override
  Future<void> deregisterDevice(String token) async {}

  @override
  Future<void> muteList(String wishlistId) async {
    _mutedListIds.value = Set.unmodifiable({..._mutedListIds.value, wishlistId});
  }

  @override
  Future<void> unmuteList(String wishlistId) async {
    _mutedListIds.value = Set.unmodifiable(_mutedListIds.value.where((id) => id != wishlistId));
  }
}
