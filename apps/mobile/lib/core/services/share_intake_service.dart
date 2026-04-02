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

  Future<String?> getInitialSharedText() async {
    if (!_supportsAndroidShareIntake) {
      return null;
    }

    final value =
        await _methodChannel.invokeMethod<String>('getInitialSharedText');
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Stream<String> watchSharedText() {
    if (!_supportsAndroidShareIntake) {
      return const Stream<String>.empty();
    }

    return _eventChannel.receiveBroadcastStream().map((event) {
      return (event as String).trim();
    }).where((value) => value.isNotEmpty);
  }

  bool get _supportsAndroidShareIntake => !kIsWeb && Platform.isAndroid;
}
