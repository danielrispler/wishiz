import 'package:flutter/foundation.dart';
import 'package:wishiz/features/product_imports/domain/product_import_job.dart';

abstract class ProductImportRepository {
  ValueListenable<List<ProductImportJob>> watchJobs();

  List<ProductImportJob> getJobs();

  Future<ProductImportJob> enqueue({
    String? wishlistId,
    required String sharedText,
    required String clientRequestId,
    required String targetCurrencyCode,
  });

  Future<void> refresh();

  Future<ProductImportJob> retry(String id);

  Future<ProductImportJob> acknowledge(String id);

  Future<ProductImportJob> assign(String id, String wishlistId);
}
