import 'package:wishiz/core/config/api_config.dart';

class WishizAppLink {
  WishizAppLink._();

  static Uri get _shareBaseUri => Uri.parse(ApiConfig.shareBaseUrl);

  static RegExp get _wishlistLinkPattern {
    final hostPattern = RegExp.escape(_shareBaseUri.host);
    return RegExp(
      '(?:wishiz://lists|https?://(?:www\\\\.)?$hostPattern/lists)/[^\\s]+',
      caseSensitive: false,
    );
  }

  static Uri wishlistShareUri(String wishlistId, {String? inviteToken}) {
    final normalizedInviteToken = inviteToken?.trim();
    return _shareBaseUri.replace(
      pathSegments: [
        ..._shareBaseUri.pathSegments.where((segment) => segment.isNotEmpty),
        'lists',
        wishlistId,
      ],
      queryParameters:
          normalizedInviteToken == null || normalizedInviteToken.isEmpty
          ? null
          : {'token': normalizedInviteToken},
      fragment: null,
    );
  }

  static String wishlistShareLink(String wishlistId, {String? inviteToken}) {
    return wishlistShareUri(wishlistId, inviteToken: inviteToken).toString();
  }

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

    if (!normalized.contains(RegExp(r'\s'))) {
      final directMatch = _extractWishlistIdFromUri(normalized);
      if (directMatch != null) {
        return directMatch;
      }
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

  static String? extractInviteToken(String? rawValue) {
    final normalized = rawValue?.trim() ?? '';
    if (normalized.isEmpty || normalized == '/') {
      return null;
    }

    if (!normalized.contains(RegExp(r'\s'))) {
      final token = _extractInviteTokenFromUri(normalized);
      if (token != null) {
        return token;
      }
    }

    for (final match in _wishlistLinkPattern.allMatches(normalized)) {
      final link = _trimTrailingPunctuation(match.group(0)!);
      final token = _extractInviteTokenFromUri(link);
      if (token != null) {
        return token;
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

    final expectedPrefix = _shareBaseUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        _matchesShareHost(uri.host) &&
        uri.pathSegments.length >= expectedPrefix.length + 2 &&
        _matchesPathPrefix(uri.pathSegments, expectedPrefix) &&
        uri.pathSegments[expectedPrefix.length] == 'lists') {
      return uri.pathSegments[expectedPrefix.length + 1];
    }

    if (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'lists') {
      return uri.pathSegments[1];
    }

    return null;
  }

  static String? _extractInviteTokenFromUri(String value) {
    final uri = Uri.tryParse(value);
    final token = uri?.queryParameters['token']?.trim();
    return token == null || token.isEmpty ? null : token;
  }

  static bool _matchesShareHost(String host) {
    final normalizedHost = host.toLowerCase();
    final expectedHost = _shareBaseUri.host.toLowerCase();
    return normalizedHost == expectedHost ||
        normalizedHost == 'www.$expectedHost';
  }

  static bool _matchesPathPrefix(
    List<String> pathSegments,
    List<String> expectedPrefix,
  ) {
    if (expectedPrefix.isEmpty) {
      return true;
    }

    for (var index = 0; index < expectedPrefix.length; index += 1) {
      if (pathSegments[index] != expectedPrefix[index]) {
        return false;
      }
    }

    return true;
  }

  static String _trimTrailingPunctuation(String value) {
    return value.replaceFirst(RegExp(r'[\.,;:!?)\]]+$'), '');
  }
}
