import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';
import 'shared_product_page_parser.dart';
import 'shared_product_text_utils.dart';

class HttpSharedProductRepository implements SharedProductRepository {
  HttpSharedProductRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<SharedProductDraft?> createDraftFromSharedText(
    String sharedText, {
    String targetCurrencyCode = 'USD',
  }) async {
    final normalizedText = sharedText.trim();
    if (normalizedText.isEmpty) return null;

    final productUrl = extractProductUrl(normalizedText);
    if (productUrl == null) return null;

    final sharedLines = extractSharedLines(normalizedText, productUrl);
    final metadata = await _fetchProductMetadata(productUrl);
    final sharedTitle = sharedLines.isEmpty ? null : sharedLines.first;
    final uriTitle = inferTitleFromProductUri(productUrl);

    final formattedTitle = buildProductTitle(
      productUrl: productUrl,
      rawCandidates: [metadata.title, sharedTitle, uriTitle],
      brandCandidate: metadata.brand,
    );
    final title = firstNonEmpty([
      formattedTitle,
      compactTitle(uriTitle),
    ]);
    final notes = firstNonEmpty([
      extractSharedNotes(sharedLines, resolvedTitle: title),
      metadata.notes,
      inferImportedFromNote(productUrl),
    ]);

    return SharedProductDraft(
      productUrl: productUrl,
      title: title,
      notes: notes,
      priceLabel: metadata.priceLabel,
      imageUrl: metadata.imageUrl,
      sharedText: normalizedText,
    );
  }

  Future<SharedProductParseResult> _fetchProductMetadata(String productUrl) async {
    final uri = Uri.parse(productUrl);
    final response = await _client.get(
      uri,
      headers: const {
        'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'user-agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 400) {
      return const SharedProductParseResult();
    }

    final document = html_parser.parse(response.body);
    return parseProductPage(document, uri);
  }
}
