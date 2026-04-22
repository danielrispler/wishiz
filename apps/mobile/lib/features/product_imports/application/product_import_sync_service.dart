import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';
import 'package:wishiz/features/product_imports/domain/product_import_repository.dart';

typedef ProductImportTimerFactory =
    Timer Function(Duration duration, void Function() callback);
typedef ProductImportCompletedCallback =
    Future<void> Function(ProductImportJob job);

class ProductImportSyncService {
  ProductImportSyncService({
    required ProductImportRepository repository,
    this.pollInterval = productImportPollInterval,
    ProductImportCompletedCallback? onJobCompleted,
    ProductImportTimerFactory? createTimer,
  }) : _repository = repository,
       _onJobCompleted = onJobCompleted,
       _createTimer = createTimer ?? Timer.new;

  static const Duration productImportPollInterval = Duration(seconds: 5);

  final ProductImportRepository _repository;
  final Duration pollInterval;
  final ProductImportCompletedCallback? _onJobCompleted;
  final ProductImportTimerFactory _createTimer;

  Timer? _pollTimer;
  bool _isRunning = false;
  bool _isDisposed = false;
  bool _isRefreshing = false;
  bool _refreshRequested = false;
  bool _hadActiveJobs = false;
  final Set<String> _notifiedCompletedJobIds = <String>{};

  ValueListenable<List<ProductImportJob>>? _jobsListenable;

  void start() {
    if (_isDisposed || _isRunning) {
      return;
    }

    _isRunning = true;
    _jobsListenable = _repository.watchJobs()..addListener(_handleJobsChanged);
    refreshNow();
  }

  void stop() {
    if (!_isRunning) {
      return;
    }

    _pollTimer?.cancel();
    _pollTimer = null;
    _jobsListenable?.removeListener(_handleJobsChanged);
    _jobsListenable = null;
    _hadActiveJobs = false;
    _isRunning = false;
  }

  Future<void> refreshNow() async {
    if (_isDisposed || !_isRunning) {
      return;
    }

    if (_isRefreshing) {
      _refreshRequested = true;
      return;
    }

    _pollTimer?.cancel();
    _pollTimer = null;
    _isRefreshing = true;

    try {
      await _repository.refresh();
    } catch (error, stackTrace) {
      debugPrint('Failed to refresh product imports: $error\n$stackTrace');
    } finally {
      _isRefreshing = false;
    }

    if (_isDisposed || !_isRunning) {
      return;
    }

    _hadActiveJobs = _hasActiveJobs;
    _schedulePollingIfNeeded();
    _notifyCompletedJobs();

    if (_refreshRequested) {
      _refreshRequested = false;
      await refreshNow();
    }
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }

    stop();
    _isDisposed = true;
  }

  void _handleJobsChanged() {
    if (_isDisposed || !_isRunning) {
      return;
    }

    final hasActiveJobs = _hasActiveJobs;
    if (_isRefreshing) {
      _hadActiveJobs = hasActiveJobs;
      return;
    }

    if (!hasActiveJobs) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _hadActiveJobs = false;
      _notifyCompletedJobs();
      return;
    }

    if (!_hadActiveJobs) {
      _hadActiveJobs = true;
      refreshNow();
      return;
    }

    _schedulePollingIfNeeded();
    _notifyCompletedJobs();
  }

  bool get _hasActiveJobs => _repository.getJobs().any((job) => job.isActive);

  void _schedulePollingIfNeeded() {
    if (!_isRunning ||
        _isDisposed ||
        _isRefreshing ||
        _pollTimer != null ||
        !_hasActiveJobs) {
      return;
    }

    _pollTimer = _createTimer(pollInterval, () {
      _pollTimer = null;
      refreshNow();
    });
  }

  void _notifyCompletedJobs() {
    final onJobCompleted = _onJobCompleted;
    if (onJobCompleted == null) {
      return;
    }

    for (final job in _repository.getJobs()) {
      if (!job.isCompleted ||
          job.createdItemId == null ||
          !_notifiedCompletedJobIds.add(job.id)) {
        continue;
      }

      unawaited(_notifyCompletedJob(job, onJobCompleted));
    }
  }

  Future<void> _notifyCompletedJob(
    ProductImportJob job,
    ProductImportCompletedCallback onJobCompleted,
  ) async {
    try {
      await onJobCompleted(job);
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to refresh after completed product import: $error\n$stackTrace',
      );
    }
  }
}
