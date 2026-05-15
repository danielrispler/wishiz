import 'package:flutter/foundation.dart';
import 'package:wishiz/features/product_imports/data/product_import_api_client.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';
import 'package:wishiz/features/product_imports/domain/product_import_repository.dart';

class ApiProductImportRepository implements ProductImportRepository {
  ApiProductImportRepository({required ProductImportApiClient apiClient})
    : _apiClient = apiClient;

  final ProductImportApiClient _apiClient;
  final ValueNotifier<List<ProductImportJob>> _jobs =
      ValueNotifier<List<ProductImportJob>>(const []);

  @override
  ValueListenable<List<ProductImportJob>> watchJobs() => _jobs;

  @override
  List<ProductImportJob> getJobs() => _jobs.value;

  @override
  Future<ProductImportJob> enqueue({
    String? wishlistId,
    required String sharedText,
    required String clientRequestId,
    required String targetCurrencyCode,
  }) async {
    final job = await _apiClient.enqueue(
      wishlistId: wishlistId,
      sharedText: sharedText,
      clientRequestId: clientRequestId,
      targetCurrencyCode: targetCurrencyCode,
    );
    _upsert(job);
    return job;
  }

  @override
  Future<void> refresh() async {
    _jobs.value = List<ProductImportJob>.unmodifiable(await _apiClient.list());
  }

  @override
  Future<ProductImportJob> retry(String id) async {
    final job = await _apiClient.retry(id);
    _upsert(job);
    return job;
  }

  @override
  Future<ProductImportJob> acknowledge(String id) async {
    final job = await _apiClient.acknowledge(id);
    _jobs.value = List<ProductImportJob>.unmodifiable(
      _jobs.value.where((entry) => entry.id != job.id),
    );
    return job;
  }

  @override
  Future<ProductImportJob> assign(String id, String wishlistId) async {
    final job = await _apiClient.assign(id, wishlistId);
    _upsert(job);
    return job;
  }

  void _upsert(ProductImportJob job) {
    final next = [job, ..._jobs.value.where((entry) => entry.id != job.id)];
    _jobs.value = List<ProductImportJob>.unmodifiable(next);
  }
}
