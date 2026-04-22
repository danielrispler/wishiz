import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';
import 'package:wishiz/features/product_imports/domain/product_import_repository.dart';

class InMemoryProductImportRepository implements ProductImportRepository {
  final ValueNotifier<List<ProductImportJob>> _jobs =
      ValueNotifier<List<ProductImportJob>>(const []);
  static const Uuid _uuid = Uuid();

  @override
  ValueListenable<List<ProductImportJob>> watchJobs() => _jobs;

  @override
  List<ProductImportJob> getJobs() => _jobs.value;

  @override
  Future<ProductImportJob> enqueue({
    required String wishlistId,
    required String sharedText,
    required String clientRequestId,
    required String targetCurrencyCode,
  }) async {
    final now = DateTime.now();
    final job = ProductImportJob(
      id: _uuid.v4(),
      wishlistId: wishlistId,
      clientRequestId: clientRequestId,
      normalizedUrl: sharedText,
      domain: Uri.tryParse(sharedText)?.host ?? '',
      targetCurrencyCode: targetCurrencyCode,
      status: 'completed',
      attemptCount: 0,
      retryable: false,
      completeness: 0,
      createdAt: now,
      updatedAt: now,
    );
    _jobs.value = List<ProductImportJob>.unmodifiable([job, ..._jobs.value]);
    return job;
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<ProductImportJob> retry(String id) async {
    return _jobs.value.firstWhere((job) => job.id == id);
  }

  @override
  Future<ProductImportJob> acknowledge(String id) async {
    final job = _jobs.value.firstWhere((entry) => entry.id == id);
    _jobs.value = List<ProductImportJob>.unmodifiable(
      _jobs.value.where((entry) => entry.id != id),
    );
    return job;
  }
}
