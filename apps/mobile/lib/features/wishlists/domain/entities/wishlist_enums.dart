enum WishlistMemberRole {
  viewer('viewer'),
  editor('editor');

  const WishlistMemberRole(this.apiValue);

  final String apiValue;

  static WishlistMemberRole fromApiValue(String value) {
    return switch (value) {
      'viewer' => WishlistMemberRole.viewer,
      'editor' => WishlistMemberRole.editor,
      _ => throw FormatException('Unknown wishlist member role: $value'),
    };
  }

  String get label => switch (this) {
    WishlistMemberRole.viewer => 'Viewer',
    WishlistMemberRole.editor => 'Editor',
  };
}

enum WishlistItemPriority {
  low('low'),
  medium('medium'),
  high('high');

  const WishlistItemPriority(this.apiValue);

  final String apiValue;

  static WishlistItemPriority fromApiValue(String value) {
    return switch (value) {
      'low' => WishlistItemPriority.low,
      'medium' => WishlistItemPriority.medium,
      'high' => WishlistItemPriority.high,
      _ => throw FormatException('Unknown wishlist item priority: $value'),
    };
  }

  String get label => switch (this) {
    WishlistItemPriority.low => 'Low',
    WishlistItemPriority.medium => 'Medium',
    WishlistItemPriority.high => 'High',
  };
}

enum WishlistItemStatus {
  saved('saved'),
  considering('considering'),
  purchased('purchased');

  const WishlistItemStatus(this.apiValue);

  final String apiValue;

  static WishlistItemStatus fromApiValue(String value) {
    return switch (value) {
      'saved' => WishlistItemStatus.saved,
      'considering' => WishlistItemStatus.considering,
      'purchased' => WishlistItemStatus.purchased,
      _ => throw FormatException('Unknown wishlist item status: $value'),
    };
  }

  String get label => switch (this) {
    WishlistItemStatus.saved => 'Saved',
    WishlistItemStatus.considering => 'Considering',
    WishlistItemStatus.purchased => 'Purchased',
  };
}
