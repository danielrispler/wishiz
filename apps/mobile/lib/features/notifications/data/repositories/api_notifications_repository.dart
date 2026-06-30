import 'package:flutter/foundation.dart';
import 'package:wishiz/features/notifications/data/api/notifications_api_client.dart';
import 'package:wishiz/features/notifications/domain/entities/app_notification.dart';
import 'package:wishiz/features/notifications/domain/repositories/notifications_repository.dart';

class ApiNotificationsRepository implements NotificationsRepository {
  ApiNotificationsRepository({required NotificationsApiClient apiClient}) : _apiClient = apiClient;

  final NotificationsApiClient _apiClient;
  final ValueNotifier<List<AppNotification>> _notifications =
      ValueNotifier<List<AppNotification>>(const []);
  final ValueNotifier<int> _unreadCount = ValueNotifier<int>(0);
  final ValueNotifier<Set<String>> _mutedListIds = ValueNotifier<Set<String>>(const <String>{});

  // Monotonic guard so a slow in-flight refresh can't clobber a newer one (or a
  // concurrent optimistic markRead/markAllRead): only the latest refresh applies.
  int _refreshGeneration = 0;

  @override
  ValueListenable<List<AppNotification>> watchNotifications() => _notifications;

  @override
  ValueListenable<int> watchUnreadCount() => _unreadCount;

  @override
  ValueListenable<Set<String>> watchMutedListIds() => _mutedListIds;

  @override
  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    final results = await Future.wait([
      _apiClient.list(),
      _apiClient.unreadCount(),
      _apiClient.listMutes(),
    ]);
    // A newer refresh (or an optimistic mutation that bumped the generation) raced
    // ahead — drop this stale result rather than clobbering the current state.
    if (generation != _refreshGeneration) return;
    _notifications.value = List<AppNotification>.unmodifiable(results[0] as List<AppNotification>);
    _unreadCount.value = results[1] as int;
    _mutedListIds.value = Set<String>.unmodifiable(results[2] as List<String>);
  }

  @override
  Future<void> markRead(String id) async {
    await _apiClient.markRead(id);
    // Invalidate any refresh in flight: its pre-mutation server snapshot must not
    // overwrite this optimistic read once it resolves.
    _refreshGeneration++;
    final wasUnread = _notifications.value.any((n) => n.id == id && !n.isRead);
    if (wasUnread) {
      final now = DateTime.now();
      _notifications.value = List<AppNotification>.unmodifiable(
        _notifications.value.map((n) => n.id == id ? n.copyWith(readAt: now) : n),
      );
      _unreadCount.value = (_unreadCount.value - 1).clamp(0, 1 << 31);
    }
  }

  @override
  Future<void> markAllRead() async {
    await _apiClient.markAllRead();
    _refreshGeneration++;
    final now = DateTime.now();
    _notifications.value = List<AppNotification>.unmodifiable(
      _notifications.value.map((n) => n.isRead ? n : n.copyWith(readAt: now)),
    );
    _unreadCount.value = 0;
  }

  @override
  Future<void> registerDevice({required String token, required String platform}) {
    return _apiClient.registerDevice(token: token, platform: platform);
  }

  @override
  Future<void> deregisterDevice(String token) => _apiClient.deregisterDevice(token);

  @override
  Future<void> muteList(String wishlistId) async {
    await _apiClient.mute(wishlistId);
    _mutedListIds.value = Set<String>.unmodifiable({..._mutedListIds.value, wishlistId});
  }

  @override
  Future<void> unmuteList(String wishlistId) async {
    await _apiClient.unmute(wishlistId);
    _mutedListIds.value = Set<String>.unmodifiable(
      _mutedListIds.value.where((id) => id != wishlistId),
    );
  }
}
