class ProductImportJob {
  const ProductImportJob({
    required this.id,
    this.wishlistId,
    required this.clientRequestId,
    required this.normalizedUrl,
    required this.domain,
    required this.targetCurrencyCode,
    required this.status,
    required this.attemptCount,
    this.lastAttemptedAt,
    this.lastError,
    this.errorCode,
    required this.retryable,
    this.title,
    this.priceLabel,
    this.priceConfidence,
    this.priceSource,
    this.priceWarnings = const [],
    this.imageUrl,
    required this.completeness,
    this.createdItemId,
    this.acknowledgedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? wishlistId;
  final String clientRequestId;
  final String normalizedUrl;
  final String domain;
  final String targetCurrencyCode;
  final String status;
  final int attemptCount;
  final DateTime? lastAttemptedAt;
  final String? lastError;
  final String? errorCode;
  final bool retryable;
  final String? title;
  final String? priceLabel;
  final String? priceConfidence;
  final String? priceSource;
  final List<String> priceWarnings;
  final String? imageUrl;
  final int completeness;
  final String? createdItemId;
  final DateTime? acknowledgedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status == 'pending' || status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get needsReview => status == 'needs_review';
  bool get failed => status == 'failed';
}
