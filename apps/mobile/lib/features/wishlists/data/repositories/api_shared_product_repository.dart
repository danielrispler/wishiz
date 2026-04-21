import 'package:wishiz/features/wishlists/data/api/shared_product_api_client.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';

class ApiSharedProductRepository implements SharedProductRepository {
  ApiSharedProductRepository({required SharedProductApiClient apiClient})
    : _apiClient = apiClient;

  final SharedProductApiClient _apiClient;

  @override
  Future<SharedProductDraft?> createDraftFromSharedText(
    String sharedText, {
    String targetCurrencyCode = 'USD',
  }) async {
    final normalizedText = sharedText.trim();
    if (normalizedText.isEmpty) {
      return null;
    }

    final productUrl = _extractProductUrl(normalizedText);
    if (productUrl == null) {
      return null;
    }

    final sharedLines = _extractSharedLines(normalizedText, productUrl);
    final scrapedProduct = await _apiClient.scrapeProduct(
      productUrl,
      targetCurrencyCode: targetCurrencyCode,
    );
    final title = scrapedProduct.name.trim().isEmpty
        ? null
        : scrapedProduct.name;
    final notes = _extractSharedNotes(sharedLines, resolvedTitle: title);
    final priceLabel =
        '${scrapedProduct.priceCurrency.trim()} ${scrapedProduct.priceAmount.trim()}'
            .trim();
    final imageUrl = scrapedProduct.imageUrl.trim().isEmpty
        ? null
        : scrapedProduct.imageUrl;

    return SharedProductDraft(
      productUrl: productUrl,
      title: title,
      notes: notes,
      priceLabel: priceLabel.isEmpty ? null : priceLabel,
      imageUrl: imageUrl,
      sharedText: normalizedText,
    );
  }

  String? _extractProductUrl(String text) {
    final match = RegExp(
      r'https?://[^\s]+',
      caseSensitive: false,
    ).firstMatch(text);

    final value = match?.group(0)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return null;
    }

    return value;
  }

  List<String> _extractSharedLines(String sharedText, String productUrl) {
    return sharedText
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => line != productUrl)
        .toList(growable: false);
  }

  String? _extractSharedNotes(List<String> lines, {String? resolvedTitle}) {
    final remainingLines = lines
        .where((line) => resolvedTitle == null || line != resolvedTitle)
        .toList(growable: false);

    if (remainingLines.isEmpty) {
      return null;
    }

    return remainingLines.join('\n');
  }
}
