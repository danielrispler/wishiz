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
    this.priceAmount,
    this.priceAmountMax,
    this.priceCurrencyCode,
    this.priceConfidence,
    this.priceSource,
    this.priceWarnings = const [],
    this.imageUrl,
    required this.completeness,
    this.progressStage,
    this.progressPercent = 0,
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

  /// Structured price for range-aware display. priceAmount is the low/"starting"
  /// bound; priceAmountMax is the high bound (non-null only for a range, e.g.
  /// configurable furniture). Both are in priceCurrencyCode and are converted to the
  /// viewing user's currency at display time. priceLabel stays the scalar fallback.
  final String? priceAmount;
  final String? priceAmountMax;
  final String? priceCurrencyCode;
  final String? priceConfidence;
  final String? priceSource;
  final List<String> priceWarnings;
  final String? imageUrl;
  final int completeness;
  final String? progressStage;
  final int progressPercent;
  final String? createdItemId;
  final DateTime? acknowledgedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status == 'pending' || status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get needsReview => status == 'needs_review';
  bool get failed => status == 'failed';

  /// The store hard-blocks automated import (anti-bot). Terminal and not
  /// retryable — the user should add the item manually instead of retrying.
  bool get unsupported => failed && errorCode == 'unsupported_site';
}
