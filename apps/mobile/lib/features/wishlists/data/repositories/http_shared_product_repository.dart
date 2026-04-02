import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:wishiz/features/wishlists/domain/entities/shared_product_draft.dart';
import 'package:wishiz/features/wishlists/domain/repositories/shared_product_repository.dart';

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

    final title = _firstNonEmpty([
      metadata.title,
      sharedTitle,
      _inferTitleFromProductUri(productUrl),
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

    return null;
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

  String? _readString(Object? value) {
    if (value is String) {
      return _normalizeText(value);
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
      final decoded = Uri.decodeComponent(segment)
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

  String _toTitleCase(String value) {
    return value.split(' ').map((part) {
      if (part.isEmpty) {
        return part;
      }
      return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
    }).join(' ');
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
    this.notes,
    this.priceLabel,
    this.imageUrl,
  });

  final String? title;
  final String? notes;
  final String? priceLabel;
  final String? imageUrl;
}
