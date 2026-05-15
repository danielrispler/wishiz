import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/product_imports/application/product_import_sync_service.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';
import 'package:wishiz/features/product_imports/domain/product_import_repository.dart';

void main() {
  group('ProductImportSyncService', () {
    test('starts with an immediate refresh', () async {
      final repository = _FakeProductImportRepository();
      final service = ProductImportSyncService(repository: repository);

      service.start();
      await _flushMicrotasks();

      expect(repository.refreshCallCount, 1);

      service.dispose();
    });

    test('schedules polling while active jobs exist', () async {
      final repository = _FakeProductImportRepository();
      repository.onRefresh = () {
        repository.setJobs([_job(status: 'pending')]);
      };
      final timers = <_ManualTimer>[];
      final service = ProductImportSyncService(
        repository: repository,
        createTimer: (duration, callback) {
          final timer = _ManualTimer(duration, callback);
          timers.add(timer);
          return timer;
        },
      );

      service.start();
      await _flushMicrotasks();

      expect(repository.refreshCallCount, 1);
      expect(
        timers.single.duration,
        ProductImportSyncService.productImportPollInterval,
      );

      timers.single.fire();
      await _flushMicrotasks();

      expect(repository.refreshCallCount, 2);

      service.dispose();
    });

    test('stops polling when no active jobs remain', () async {
      final repository = _FakeProductImportRepository();
      var refreshCount = 0;
      repository.onRefresh = () {
        refreshCount += 1;
        repository.setJobs([
          _job(status: refreshCount == 1 ? 'processing' : 'completed'),
        ]);
      };
      final timers = <_ManualTimer>[];
      final service = ProductImportSyncService(
        repository: repository,
        createTimer: (duration, callback) {
          final timer = _ManualTimer(duration, callback);
          timers.add(timer);
          return timer;
        },
      );

      service.start();
      await _flushMicrotasks();
      expect(timers.where((timer) => timer.isActive).length, 1);

      timers.single.fire();
      await _flushMicrotasks();

      expect(repository.refreshCallCount, 2);
      expect(timers.where((timer) => timer.isActive), isEmpty);

      service.dispose();
    });

    test('refreshes immediately when active jobs are added', () async {
      final repository = _FakeProductImportRepository();
      final timers = <_ManualTimer>[];
      final service = ProductImportSyncService(
        repository: repository,
        createTimer: (duration, callback) {
          final timer = _ManualTimer(duration, callback);
          timers.add(timer);
          return timer;
        },
      );

      service.start();
      await _flushMicrotasks();
      expect(repository.refreshCallCount, 1);

      repository.setJobs([_job(status: 'pending')]);
      await _flushMicrotasks();

      expect(repository.refreshCallCount, 2);
      expect(timers.where((timer) => timer.isActive).length, 1);

      service.dispose();
    });

    test('notifies once when a job completes with a created item', () async {
      final repository = _FakeProductImportRepository();
      final completedJobs = <String>[];
      final service = ProductImportSyncService(
        repository: repository,
        onJobCompleted: (job) async {
          completedJobs.add(job.id);
        },
      );

      service.start();
      await _flushMicrotasks();

      repository.setJobs([_job(status: 'completed', createdItemId: 'item-1')]);
      await _flushMicrotasks();

      repository.setJobs([_job(status: 'completed', createdItemId: 'item-1')]);
      await _flushMicrotasks();

      expect(completedJobs, ['job-completed']);

      service.dispose();
    });

    test('does not notify for completed jobs without a created item', () async {
      final repository = _FakeProductImportRepository();
      final completedJobs = <String>[];
      final service = ProductImportSyncService(
        repository: repository,
        onJobCompleted: (job) async {
          completedJobs.add(job.id);
        },
      );

      service.start();
      await _flushMicrotasks();

      repository.setJobs([_job(status: 'completed')]);
      await _flushMicrotasks();

      expect(completedJobs, isEmpty);

      service.dispose();
    });

    test('disposes cleanly without calling refresh again', () async {
      final repository = _FakeProductImportRepository();
      repository.onRefresh = () {
        repository.setJobs([_job(status: 'pending')]);
      };
      final timers = <_ManualTimer>[];
      final service = ProductImportSyncService(
        repository: repository,
        createTimer: (duration, callback) {
          final timer = _ManualTimer(duration, callback);
          timers.add(timer);
          return timer;
        },
      );

      service.start();
      await _flushMicrotasks();
      service.dispose();

      timers.single.fire();
      await _flushMicrotasks();

      expect(repository.refreshCallCount, 1);
    });
  });
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

ProductImportJob _job({required String status, String? createdItemId}) {
  final now = DateTime(2026, 1, 1);
  return ProductImportJob(
    id: 'job-$status',
    wishlistId: 'wishlist-1',
    clientRequestId: 'request-$status',
    normalizedUrl: 'https://example.com/products/mug',
    domain: 'example.com',
    targetCurrencyCode: 'USD',
    status: status,
    attemptCount: 0,
    retryable: status == 'failed',
    completeness: 0,
    createdItemId: createdItemId,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeProductImportRepository implements ProductImportRepository {
  final ValueNotifier<List<ProductImportJob>> _jobs =
      ValueNotifier<List<ProductImportJob>>(const []);

  int refreshCallCount = 0;
  VoidCallback? onRefresh;

  void setJobs(List<ProductImportJob> jobs) {
    _jobs.value = List<ProductImportJob>.unmodifiable(jobs);
  }

  @override
  ValueListenable<List<ProductImportJob>> watchJobs() => _jobs;

  @override
  List<ProductImportJob> getJobs() => _jobs.value;

  @override
  Future<void> refresh() async {
    refreshCallCount += 1;
    onRefresh?.call();
  }

  @override
  Future<ProductImportJob> enqueue({
    String? wishlistId,
    required String sharedText,
    required String clientRequestId,
    required String targetCurrencyCode,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ProductImportJob> retry(String id) {
    throw UnimplementedError();
  }

  @override
  Future<ProductImportJob> acknowledge(String id) {
    throw UnimplementedError();
  }

  @override
  Future<ProductImportJob> assign(String id, String wishlistId) {
    throw UnimplementedError();
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  var _isActive = true;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _isActive ? 0 : 1;

  @override
  void cancel() {
    _isActive = false;
  }

  void fire() {
    if (!_isActive) {
      return;
    }
    _isActive = false;
    _callback();
  }
}
