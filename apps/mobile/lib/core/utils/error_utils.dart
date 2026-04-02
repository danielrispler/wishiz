String formatErrorMessage(
  Object error, {
  String fallbackMessage = 'Something went wrong.',
}) {
  final rawMessage = error.toString().trim();
  if (rawMessage.isEmpty) {
    return fallbackMessage;
  }

  const prefixes = [
    'Exception: ',
    'Bad state: ',
    'Invalid argument(s): ',
  ];

  for (final prefix in prefixes) {
    if (rawMessage.startsWith(prefix)) {
      final trimmed = rawMessage.substring(prefix.length).trim();
      return trimmed.isEmpty ? fallbackMessage : trimmed;
    }
  }

  return rawMessage;
}
