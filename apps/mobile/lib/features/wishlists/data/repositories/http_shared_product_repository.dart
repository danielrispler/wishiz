import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';

final RegExp _titleSeparatorPattern = RegExp(r'\s+\|\s+|\s+-\s+|\s+:\s+');

class HttpSharedProductRepository implements SharedProductRepository {
  HttpSharedProductRepository({
    http.Client? client,
  }) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<SharedProductDraft?> createDraftFromSharedText(
      String sharedText) async {
    final normalizedText = sharedText.trim();
    if (normalizedText.isEmpty) {
      return null;
    }

    final productUrl = _extractProductUrl(normalizedText);
    if (productUrl == null) {
      return null;
    }

    final sharedLines = _extractSharedLines(normalizedText, productUrl);

    final metadata = await _fetchProductMetadata(productUrl);
    final sharedTitle = sharedLines.isEmpty ? null : sharedLines.first;

    final formattedTitle = _buildProductTitle(
      productUrl: productUrl,
      rawCandidates: [
        metadata.title,
        sharedTitle,
        _inferTitleFromProductUri(productUrl),
      ],
      brandCandidate: metadata.brand,
    );
    final title = _firstNonEmpty([
      formattedTitle,
      _compactTitle(_inferTitleFromProductUri(productUrl)),
    ]);
    final notes = _firstNonEmpty([
      _extractSharedNotes(sharedLines, resolvedTitle: title),
      metadata.notes,
      _inferImportedFromNote(productUrl),
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

  Future<_ResolvedProductMetadata> _fetchProductMetadata(
      String productUrl) async {
    final uri = Uri.parse(productUrl);
    final response = await _client.get(
      uri,
      headers: const {
        'accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'user-agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 400) {
      return const _ResolvedProductMetadata();
    }

    final document = html_parser.parse(response.body);

    return _ResolvedProductMetadata(
      title: _resolveTitle(document),
      brand: _resolveBrand(document, uri),
      imageUrl: _resolveImageUrl(document, uri),
      priceLabel: _resolvePriceLabel(document),
      notes: _resolveDescription(document),
    );
  }

  String? _resolveTitle(Document document) {
    final schemaTitle = _extractSchemaValue<String>(
      document,
      predicate: (node) =>
          _matchesSchemaType(node, 'Product') &&
          _readString(node['name']) != null,
      value: (node) => _readString(node['name']),
    );

    return _firstNonEmpty([
      _metaContent(document, property: 'og:title'),
      _metaContent(document, name: 'twitter:title'),
      _metaContent(document, name: 'title'),
      schemaTitle,
      _normalizeText(document.querySelector('title')?.text),
    ]);
  }

  String? _resolveBrand(Document document, Uri pageUri) {
    final schemaBrand = _extractSchemaValue<String>(
      document,
      predicate: (node) =>
          _matchesSchemaType(node, 'Product') &&
          _resolveSchemaBrand(node['brand']) != null,
      value: (node) => _resolveSchemaBrand(node['brand']),
    );

    return _firstNonEmpty([
      _metaContent(document, property: 'product:brand'),
      _metaContent(document, name: 'brand'),
      _attributeContent(
        document,
        selector: '[itemprop="brand"]',
        attribute: 'content',
      ),
      _normalizeText(document.querySelector('[itemprop="brand"]')?.text),
      schemaBrand,
      _inferBrandFromHost(pageUri.host),
    ]);
  }

  String? _resolveImageUrl(Document document, Uri pageUri) {
    final schemaImage = _extractSchemaValue<String>(
      document,
      predicate: (node) =>
          _matchesSchemaType(node, 'Product') &&
          _readImage(node['image']) != null,
      value: (node) => _readImage(node['image']),
    );

    final image = _firstNonEmpty([
      _metaContent(document, property: 'og:image'),
      _metaContent(document, name: 'twitter:image'),
      _attributeContent(document,
          selector: '[itemprop="image"]', attribute: 'content'),
      _attributeContent(document,
          selector: '[itemprop="image"]', attribute: 'src'),
      schemaImage,
      _attributeContent(
        document,
        selector: 'link[rel="image_src"]',
        attribute: 'href',
      ),
      _resolveFirstPageImage(document),
    ]);
    if (image == null) {
      return null;
    }

    return pageUri.resolve(image).toString();
  }

  String? _resolvePriceLabel(Document document) {
    final metaAmount = _firstNonEmpty([
      _metaContent(document, property: 'product:price:amount'),
      _metaContent(document, property: 'og:price:amount'),
      _metaContent(document, name: 'price'),
      _attributeContent(document,
          selector: '[itemprop="price"]', attribute: 'content'),
      _normalizeText(document.querySelector('[itemprop="price"]')?.text),
    ]);
    final metaCurrency = _firstNonEmpty([
      _metaContent(document, property: 'product:price:currency'),
      _metaContent(document, property: 'og:price:currency'),
      _attributeContent(
        document,
        selector: '[itemprop="priceCurrency"]',
        attribute: 'content',
      ),
      _normalizeText(
          document.querySelector('[itemprop="priceCurrency"]')?.text),
    ]);

    if (_looksLikePrice(metaAmount)) {
      return _formatPriceLabel(metaAmount!, currency: metaCurrency);
    }

    final schemaPrice = _extractSchemaValue<String>(
      document,
      predicate: (node) => _schemaPriceValue(node) != null,
      value: (node) => _schemaPriceValue(node),
    );
    if (schemaPrice != null) {
      return schemaPrice;
    }

    final visibleSelectors = _extractSelectorPrice(document);
    if (visibleSelectors != null) {
      return visibleSelectors;
    }

    return _extractVisiblePrice(document);
  }

  String? _resolveDescription(Document document) {
    return _firstNonEmpty([
      _metaContent(document, property: 'og:description'),
      _metaContent(document, name: 'description'),
      _metaContent(document, name: 'twitter:description'),
    ]);
  }

  String? _schemaPriceValue(Map<String, dynamic> node) {
    final offers = node['offers'];
    final offerMaps = _collectOfferMaps(offers);
    for (final offer in offerMaps) {
      if (_looksLikeNonPrimaryPrice(_readString(offer['name']))) {
        continue;
      }

      final amount = _readString(offer['price']);
      if (!_looksLikePrice(amount)) {
        continue;
      }

      return _formatPriceLabel(
        amount!,
        currency: _readString(offer['priceCurrency']),
      );
    }

    return null;
  }

  List<Map<String, dynamic>> _collectOfferMaps(Object? offers) {
    if (offers is Map<String, dynamic>) {
      return [offers];
    }
    if (offers is List) {
      return offers.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    return const [];
  }

  T? _extractSchemaValue<T>(
    Document document, {
    required bool Function(Map<String, dynamic> node) predicate,
    required T? Function(Map<String, dynamic> node) value,
  }) {
    for (final script
        in document.querySelectorAll('script[type="application/ld+json"]')) {
      final raw = script.text.trim();
      if (raw.isEmpty) {
        continue;
      }

      final decoded = _tryDecodeJson(raw);
      if (decoded == null) {
        continue;
      }

      for (final node in _flattenJsonMaps(decoded)) {
        if (!predicate(node)) {
          continue;
        }

        final result = value(node);
        if (result != null) {
          return result;
        }
      }
    }

    return null;
  }

  Object? _tryDecodeJson(String source) {
    try {
      return jsonDecode(source);
    } on FormatException {
      return null;
    }
  }

  Iterable<Map<String, dynamic>> _flattenJsonMaps(Object? value) sync* {
    if (value is Map<String, dynamic>) {
      yield value;
      for (final nested in value.values) {
        yield* _flattenJsonMaps(nested);
      }
      return;
    }

    if (value is List) {
      for (final nested in value) {
        yield* _flattenJsonMaps(nested);
      }
    }
  }

  bool _matchesSchemaType(Map<String, dynamic> node, String expectedType) {
    final type = node['@type'];
    if (type is String) {
      return type.toLowerCase() == expectedType.toLowerCase();
    }
    if (type is List) {
      return type.any((entry) =>
          entry is String && entry.toLowerCase() == expectedType.toLowerCase());
    }
    return false;
  }

  String? _readImage(Object? value) {
    if (value is String) {
      return _normalizeText(value);
    }
    if (value is List) {
      for (final entry in value) {
        final resolved = _readImage(entry);
        if (resolved != null) {
          return resolved;
        }
      }
    }
    if (value is Map<String, dynamic>) {
      return _firstNonEmpty([
        _readString(value['url']),
        _readString(value['contentUrl']),
      ]);
    }
    return null;
  }

  String? _resolveSchemaBrand(Object? value) {
    if (value is String) {
      return _normalizeBrand(value);
    }
    if (value is Map<String, dynamic>) {
      return _firstNonEmpty([
        _normalizeBrand(_readString(value['name'])),
        _normalizeBrand(_readString(value['brand'])),
      ]);
    }
    if (value is List) {
      for (final entry in value) {
        final resolved = _resolveSchemaBrand(entry);
        if (resolved != null) {
          return resolved;
        }
      }
    }
    return null;
  }

  String? _readString(Object? value) {
    if (value is String) {
      return _normalizeText(value);
    }
    return null;
  }

  String? _resolveFirstPageImage(Document document) {
    for (final image in document.querySelectorAll('img')) {
      final candidate = _firstNonEmpty([
        image.attributes['src'],
        image.attributes['data-src'],
        image.attributes['data-old-hires'],
        image.attributes['data-original'],
        image.attributes['data-image'],
      ]);
      if (candidate == null) {
        continue;
      }

      final normalized = candidate.toLowerCase();
      final looksLikeRealImage = normalized.startsWith('http') ||
          normalized.startsWith('/') ||
          normalized.startsWith('//');
      final isLikelyAsset = normalized.endsWith('.jpg') ||
          normalized.endsWith('.jpeg') ||
          normalized.endsWith('.png') ||
          normalized.endsWith('.webp') ||
          normalized.contains('image') ||
          normalized.contains('product') ||
          normalized.contains('main');
      final isIgnored = normalized.contains('logo') ||
          normalized.contains('icon') ||
          normalized.contains('sprite') ||
          normalized.contains('avatar') ||
          normalized.contains('placeholder') ||
          normalized.contains('banner');

      if (looksLikeRealImage && isLikelyAsset && !isIgnored) {
        return candidate;
      }
    }

    return null;
  }

  String? _metaContent(
    Document document, {
    String? property,
    String? name,
  }) {
    final selector =
        property != null ? 'meta[property="$property"]' : 'meta[name="$name"]';
    return _attributeContent(document,
        selector: selector, attribute: 'content');
  }

  String? _attributeContent(
    Document document, {
    required String selector,
    required String attribute,
  }) {
    final value = document.querySelector(selector)?.attributes[attribute];
    return _normalizeText(value);
  }

  String? _extractProductUrl(String sharedText) {
    final urlPattern =
        RegExp(r'https?:\/\/[^\s<>"\)\]]+', caseSensitive: false);
    final match = urlPattern.firstMatch(sharedText);
    if (match == null) {
      return null;
    }

    final candidate = match.group(0);
    final uri = candidate == null ? null : Uri.tryParse(candidate);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return null;
    }

    return uri.toString();
  }

  List<String> _extractSharedLines(String sharedText, String productUrl) {
    return sharedText
        .split(RegExp(r'\r?\n'))
        .map(_normalizeText)
        .whereType<String>()
        .where((line) => line != productUrl)
        .where((line) => !_containsUrl(line))
        .toList(growable: false);
  }

  String? _extractSharedNotes(
    List<String> lines, {
    String? resolvedTitle,
  }) {
    final remainingLines = lines
        .where((line) => resolvedTitle == null || line != resolvedTitle)
        .toList(growable: false);

    if (remainingLines.isEmpty) {
      return null;
    }

    return remainingLines.join('\n');
  }

  String? _inferTitleFromProductUri(String productUrl) {
    final uri = Uri.tryParse(productUrl);
    if (uri == null) {
      return null;
    }

    for (final segment in uri.pathSegments.reversed) {
      final decoded = _decodeUriComponentSafely(segment)
          .replaceAll(RegExp(r'[-_+]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final cleaned = decoded
          .replaceAll(RegExp(r'\b\d+\b'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (cleaned.length > 2) {
        return _toTitleCase(cleaned);
      }
    }

    return null;
  }

  String _decodeUriComponentSafely(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  String? _inferImportedFromNote(String productUrl) {
    final uri = Uri.tryParse(productUrl);
    if (uri == null) {
      return null;
    }

    final host = uri.host.replaceFirst(RegExp(r'^www\.'), '').trim();
    if (host.isEmpty) {
      return null;
    }

    return 'Imported from $host.';
  }

  String? _compactTitle(String? value) {
    final normalized = _normalizeText(value);
    if (normalized == null) {
      return null;
    }

    final cleaned = normalized
        .split(_titleSeparatorPattern)
        .first
        .replaceAll(RegExp(r'[^\w\s&]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) {
      return null;
    }

    final words = cleaned
        .split(' ')
        .where((word) => word.isNotEmpty)
        .where((word) => !_isStopWord(word))
        .take(3)
        .toList(growable: false);

    final compact = words.isEmpty
        ? cleaned.split(' ').where((word) => word.isNotEmpty).take(3).join(' ')
        : words.join(' ');
    return _toTitleCase(compact);
  }

  bool _isStopWord(String word) {
    const stopWords = {
      'the',
      'and',
      'with',
      'for',
      'from',
      'new',
      'best',
      'official',
      'shop',
      'buy',
      'sale',
    };
    return stopWords.contains(word.toLowerCase());
  }

  String? _extractVisiblePrice(Document document) {
    final bodyText = _normalizeText(document.body?.text);
    if (bodyText == null) {
      return null;
    }

    final symbolMatch = RegExp(
      r'([$€£₪])\s?(\d{1,3}(?:[,\s]\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)',
    ).firstMatch(bodyText);
    if (symbolMatch != null) {
      final symbol = symbolMatch.group(1)!;
      final amount = symbolMatch.group(2)!;
      return _isLikelyCurrentPriceContext(bodyText, symbolMatch.start)
          ? '$symbol $amount'
          : null;
    }

    final codeMatch = RegExp(
      r'\b(USD|EUR|GBP|ILS)\s?(\d{1,3}(?:[,\s]\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)\b',
      caseSensitive: false,
    ).firstMatch(bodyText);
    if (codeMatch != null) {
      return _isLikelyCurrentPriceContext(bodyText, codeMatch.start)
          ? '${codeMatch.group(1)!.toUpperCase()} ${codeMatch.group(2)!}'
          : null;
    }

    return null;
  }

  String? _extractSelectorPrice(Document document) {
    const selectors = [
      '[data-price]',
      '[data-product-price]',
      '[itemprop="price"]',
      '.price',
      '.product-price',
      '.sale-price',
      '.current-price',
      '.price-current',
      '.price__current',
      '.a-price .a-offscreen',
    ];

    for (final selector in selectors) {
      for (final element in document.querySelectorAll(selector)) {
        final rawAmount = _firstNonEmpty([
          element.attributes['content'],
          element.attributes['data-price'],
          element.attributes['aria-label'],
          _normalizeText(element.text),
        ]);
        if (!_looksLikePrice(rawAmount)) {
          continue;
        }

        final context = _normalizeText(
          '${element.className} ${element.id} ${element.attributes.values.join(' ')} ${element.text}',
        );
        if (_looksLikeNonPrimaryPrice(context)) {
          continue;
        }

        final currency = _firstNonEmpty([
          element.attributes['data-currency'],
          element.attributes['currency'],
          _attributeContent(
            document,
            selector: '[itemprop="priceCurrency"]',
            attribute: 'content',
          ),
        ]);
        return _formatPriceLabel(
          rawAmount!,
          currency: currency ?? _extractCurrencySymbol(rawAmount),
        );
      }
    }

    return null;
  }

  String _toTitleCase(String value) {
    return value.split(' ').map((part) {
      if (part.isEmpty) {
        return part;
      }
      return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
    }).join(' ');
  }

  String? _buildProductTitle({
    required String productUrl,
    required List<String?> rawCandidates,
    String? brandCandidate,
  }) {
    final brand = _normalizeBrand(brandCandidate) ??
        _inferBrandFromTitle(rawCandidates) ??
        _inferBrandFromHost(
          Uri.tryParse(productUrl)?.host ?? '',
        );

    for (final candidate in rawCandidates) {
      final type = _extractProductType(candidate, brand: brand);
      if (type == null) {
        continue;
      }

      if (brand != null) {
        return '${_toTitleCase(type)}, $brand';
      }

      return _toTitleCase(type);
    }

    return null;
  }

  String? _extractProductType(String? rawTitle, {String? brand}) {
    final normalized = _normalizeText(rawTitle);
    if (normalized == null) {
      return null;
    }

    var cleaned = normalized
        .split(_titleSeparatorPattern)
        .first
        .replaceAll(RegExp(r'[^\w\s,&/]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (brand != null && brand.isNotEmpty) {
      cleaned = cleaned
          .replaceAll(RegExp(RegExp.escape(brand), caseSensitive: false), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    final tokens = cleaned
        .split(' ')
        .where((word) => word.isNotEmpty)
        .where((word) => !_isStopWord(word))
        .toList(growable: false);
    if (tokens.isEmpty) {
      return null;
    }

    final productKeywords = <String>[];
    var nounIndex = -1;
    for (final token in tokens) {
      productKeywords.add(token);
      if (_looksLikeProductNoun(token) && productKeywords.length >= 2) {
        nounIndex = productKeywords.length - 1;
        break;
      }
      if (productKeywords.length == 3) {
        break;
      }
    }

    if (nounIndex != -1 &&
        productKeywords.length < 3 &&
        tokens.length > nounIndex + 1) {
      final nextToken = tokens[nounIndex + 1];
      if (_looksLikeProductDescriptor(nextToken)) {
        productKeywords.add(nextToken);
      }
    }

    return productKeywords.join(' ');
  }

  bool _looksLikeProductNoun(String word) {
    const nouns = {
      'shirt',
      'tshirt',
      't-shirt',
      'tee',
      'socks',
      'sock',
      'hoodie',
      'jacket',
      'sneakers',
      'shoes',
      'shoe',
      'pants',
      'jeans',
      'dress',
      'hat',
      'cap',
      'bag',
      'wallet',
      'blanket',
      'lamp',
      'kettle',
      'chair',
      'mug',
      'bowl',
    };
    return nouns.contains(word.toLowerCase());
  }

  bool _looksLikeProductDescriptor(String word) {
    const descriptors = {
      'matte',
      'white',
      'black',
      'blue',
      'red',
      'green',
      'grey',
      'gray',
      'cotton',
      'wool',
      'leather',
      'mini',
      'max',
      'pro',
      'classic',
      'crew',
      'slim',
      'oversized',
    };
    return descriptors.contains(word.toLowerCase());
  }

  String? _normalizeBrand(String? brand) {
    final normalized = _normalizeText(brand);
    if (normalized == null) {
      return null;
    }

    if (normalized.toUpperCase() == normalized) {
      return normalized;
    }

    final lower = normalized.toLowerCase();
    if (lower == 'hm' || lower == 'h&m') {
      return 'H&M';
    }

    return normalized
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String? _inferBrandFromHost(String host) {
    final normalizedHost = host.replaceFirst(RegExp(r'^www\.'), '').trim();
    if (normalizedHost.isEmpty) {
      return null;
    }

    if (normalizedHost == 'localhost' ||
        normalizedHost.startsWith('127.') ||
        RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(normalizedHost)) {
      return null;
    }

    final primary = normalizedHost.split('.').first;
    if (primary.isEmpty || primary.length < 2) {
      return null;
    }

    return _normalizeBrand(primary);
  }

  String? _inferBrandFromTitle(List<String?> rawCandidates) {
    for (final candidate in rawCandidates) {
      final normalized = _normalizeText(candidate);
      if (normalized == null) {
        continue;
      }

      final cleaned = normalized
          .split(_titleSeparatorPattern)
          .first
          .replaceAll(RegExp(r'[^\w\s&]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (cleaned.isEmpty) {
        continue;
      }

      final tokens = cleaned
          .split(' ')
          .where((word) => word.isNotEmpty)
          .toList(growable: false);
      if (tokens.length < 3) {
        continue;
      }

      final first = tokens.first;
      final normalizedBrand = _normalizeBrand(first);
      if (normalizedBrand == null) {
        continue;
      }

      if (_isStopWord(first) ||
          _looksLikeProductNoun(first) ||
          _looksLikeProductDescriptor(first)) {
        continue;
      }

      return normalizedBrand;
    }

    return null;
  }

  bool _looksLikeNonPrimaryPrice(String? context) {
    final normalized = context?.toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return false;
    }

    return normalized.contains('compare') ||
        normalized.contains('was ') ||
        normalized.contains('list price') ||
        normalized.contains('save ') ||
        normalized.contains('installment') ||
        normalized.contains('finance') ||
        normalized.contains('shipping');
  }

  bool _isLikelyCurrentPriceContext(String bodyText, int matchStart) {
    final start = matchStart < 40 ? 0 : matchStart - 40;
    final end =
        matchStart + 60 > bodyText.length ? bodyText.length : matchStart + 60;
    final context = bodyText.substring(start, end).toLowerCase();
    return !_looksLikeNonPrimaryPrice(context);
  }

  String? _extractCurrencySymbol(String value) {
    final match = RegExp(r'([$€£₪])').firstMatch(value);
    if (match != null) {
      return match.group(1);
    }

    final codeMatch = RegExp(r'\b(USD|EUR|GBP|ILS)\b', caseSensitive: false)
        .firstMatch(value);
    return codeMatch?.group(1)?.toUpperCase();
  }

  String? _formatPriceLabel(String amount, {String? currency}) {
    final normalizedAmount = amount.replaceAll(RegExp(r'[^0-9.,]'), '').trim();
    if (normalizedAmount.isEmpty) {
      return null;
    }

    final normalizedCurrency = _normalizeText(currency);
    if (normalizedCurrency == null) {
      return normalizedAmount;
    }

    return '$normalizedCurrency $normalizedAmount';
  }

  bool _looksLikePrice(String? value) {
    if (value == null) {
      return false;
    }

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    return RegExp(r'^\$?\d[\d,]*(?:\.\d{1,2})?$').hasMatch(trimmed) ||
        RegExp(r'^[A-Z]{3}\s*\d[\d,]*(?:\.\d{1,2})?$').hasMatch(trimmed) ||
        RegExp(r'^\d[\d,]*(?:\.\d{1,2})?$').hasMatch(trimmed);
  }

  bool _containsUrl(String value) =>
      RegExp(r'https?:\/\/', caseSensitive: false).hasMatch(value);

  String? _normalizeText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final normalized = _normalizeText(value);
      if (normalized != null) {
        return normalized;
      }
    }
    return null;
  }
}

class _ResolvedProductMetadata {
  const _ResolvedProductMetadata({
    this.title,
    this.brand,
    this.notes,
    this.priceLabel,
    this.imageUrl,
  });

  final String? title;
  final String? brand;
  final String? notes;
  final String? priceLabel;
  final String? imageUrl;
}
