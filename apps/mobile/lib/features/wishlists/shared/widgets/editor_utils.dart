bool isRemoteUri(Uri? uri) {
  return uri != null &&
      (uri.scheme == 'http' ||
          uri.scheme == 'https' ||
          uri.scheme == 'blob' ||
          uri.scheme == 'data');
}
