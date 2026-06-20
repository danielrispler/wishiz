import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ShareIntakeService {
  const ShareIntakeService();

  static const MethodChannel _methodChannel =
      MethodChannel('wishiz/share_intake/methods');
  static const EventChannel _eventChannel =
      EventChannel('wishiz/share_intake/events');

  Future<List<String>> consumePendingSharedTexts() async {
    if (!_supportsNativeShareIntake) {
      return const [];
    }

    final values = await _methodChannel.invokeListMethod<String>(
      'consumePendingSharedTexts',
    );
    if (values == null) {
      return const [];
    }

    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Stream<String> watchSharedText() {
    if (!_supportsLiveShareEvents) {
      return const Stream<String>.empty();
    }

    return normalizeSharedTextEvents(_eventChannel.receiveBroadcastStream());
  }

  /// Turns the raw native event stream into clean, non-empty shared-text strings.
  /// A non-String/null event is skipped (not cast — an unchecked cast would throw
  /// and tear down the subscription for the rest of the session), and any stream
  /// error is logged and swallowed so the subscription stays alive.
  @visibleForTesting
  static Stream<String> normalizeSharedTextEvents(Stream<dynamic> raw) {
    return raw
        .map((event) => event is String ? event.trim() : null)
        .where((value) => value != null && value.isNotEmpty)
        .cast<String>()
        .handleError((Object error, StackTrace stackTrace) {
      debugPrint('share intake stream error (subscription kept alive): $error');
    });
  }

  bool get _supportsNativeShareIntake =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _supportsLiveShareEvents => !kIsWeb && Platform.isAndroid;
}
