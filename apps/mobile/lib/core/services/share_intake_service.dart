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

    return _eventChannel.receiveBroadcastStream().map((event) {
      return (event as String).trim();
    }).where((value) => value.isNotEmpty);
  }

  bool get _supportsNativeShareIntake =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _supportsLiveShareEvents => !kIsWeb && Platform.isAndroid;
}
