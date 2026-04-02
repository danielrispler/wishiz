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

  Future<String?> consumePendingSharedText() async {
    if (!_supportsNativeShareIntake) {
      return null;
    }

    final value =
        await _methodChannel.invokeMethod<String>('consumePendingSharedText');
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
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
