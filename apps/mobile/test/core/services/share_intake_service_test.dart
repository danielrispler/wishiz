import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/core/services/share_intake_service.dart';

void main() {
  group('ShareIntakeService.normalizeSharedTextEvents', () {
    test('skips non-String/empty events and keeps delivering valid strings', () async {
      final controller = StreamController<dynamic>();
      final received = <String>[];
      final sub = ShareIntakeService.normalizeSharedTextEvents(
        controller.stream,
      ).listen(received.add);

      controller.add(42); // non-String — must be skipped (not cast → no teardown)
      controller.add(null); // null — skipped
      controller.add('   '); // empty after trim — skipped
      controller.add('  https://example.com/p  '); // valid → trimmed
      await Future<void>.delayed(Duration.zero);

      expect(received, ['https://example.com/p']);

      await sub.cancel();
      await controller.close();
    });

    test('survives a stream error and keeps delivering later events', () async {
      final controller = StreamController<dynamic>();
      final received = <String>[];
      final sub = ShareIntakeService.normalizeSharedTextEvents(
        controller.stream,
      ).listen(received.add);

      controller.addError(Exception('native event channel blew up'));
      controller.add('https://example.com/after-error');
      await Future<void>.delayed(Duration.zero);

      expect(received, ['https://example.com/after-error']);

      await sub.cancel();
      await controller.close();
    });
  });
}
