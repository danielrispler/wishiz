class WishizAppLink {
  WishizAppLink._();

  static final RegExp _wishlistLinkPattern = RegExp(
    r'wishiz://lists/[^\s]+',
    caseSensitive: false,
  );

  static Uri wishlistUri(String wishlistId) {
    return Uri(scheme: 'wishiz', host: 'lists', pathSegments: [wishlistId]);
  }

  static String wishlistLink(String wishlistId) {
    return wishlistUri(wishlistId).toString();
  }

  static String? extractWishlistId(String? rawValue) {
    final normalized = rawValue?.trim() ?? '';
    if (normalized.isEmpty || normalized == '/') {
      return null;
    }

    final directMatch = _extractWishlistIdFromUri(normalized);
    if (directMatch != null) {
      return directMatch;
    }

    for (final match in _wishlistLinkPattern.allMatches(normalized)) {
      final link = _trimTrailingPunctuation(match.group(0)!);
      final wishlistId = _extractWishlistIdFromUri(link);
      if (wishlistId != null) {
        return wishlistId;
      }
    }

    return null;
  }

  static String? _extractWishlistIdFromUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return null;
    }

    if (uri.scheme == 'wishiz' &&
        uri.host == 'lists' &&
        uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }

    if (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'lists') {
      return uri.pathSegments[1];
    }

    return null;
  }

  static String _trimTrailingPunctuation(String value) {
    return value.replaceFirst(RegExp(r'[\.,;:!?)\]]+$'), '');
  }
}
