/// The four server-emitted notification kinds, plus an `unknown` fallback so an
/// older client never crashes on a future type.
enum NotificationType { listMemberJoined, itemAdded, itemPurchased, importSettled, unknown }

NotificationType notificationTypeFromString(String value) {
  switch (value) {
    case 'list_member_joined':
      return NotificationType.listMemberJoined;
    case 'item_added':
      return NotificationType.itemAdded;
    case 'item_purchased':
      return NotificationType.itemPurchased;
    case 'import_settled':
      return NotificationType.importSettled;
    default:
      return NotificationType.unknown;
  }
}

/// A single inbox notification. `readAt == null` means unread (counts toward the
/// bell badge). The durable server row is the source of truth; this is the
/// client view of it.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.wishlistId,
    this.itemId,
    this.importJobId,
    this.readAt,
    required this.createdAt,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final String? wishlistId;
  final String? itemId;
  final String? importJobId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  AppNotification copyWith({DateTime? readAt}) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      wishlistId: wishlistId,
      itemId: itemId,
      importJobId: importJobId,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt,
    );
  }
}
