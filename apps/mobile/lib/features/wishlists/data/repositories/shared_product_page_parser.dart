import 'dart:convert';

import 'package:html/dom.dart';

class SharedProductParseResult {
  const SharedProductParseResult({
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

SharedProductParseResult parseProductPage(Document document, Uri pageUri) {
  return SharedProductParseResult(
    title: _resolveTitle(document),
    brand: _resolveBrand(document, pageUri),
    imageUrl: _resolveImageUrl(document, pageUri),
    priceLabel: _resolvePriceLabel(document),
    notes: _resolveDescription(document),
  );
}

String? _resolveTitle(Document document) {
  final schemaTitle = _extractSchemaValue<String>(
    document,
    predicate: (node) => _matchesSchemaType(node, 'Product') && _readString(node['name']) != null,
    value: (node) => _readString(node['name']),
  );
  return firstNonEmpty([
    _metaContent(document, property: 'og:title'),
    _metaContent(document, name: 'twitter:title'),
    _metaContent(document, name: 'title'),
    schemaTitle,
    normalizeText(document.querySelector('title')?.text),
  ]);
}

String? _resolveBrand(Document document, Uri pageUri) {
  final schemaBrand = _extractSchemaValue<String>(
    document,
    predicate: (node) => _matchesSchemaType(node, 'Product') && _resolveSchemaBrand(node['brand']) != null,
    value: (node) => _resolveSchemaBrand(node['brand']),
  );
  return firstNonEmpty([
    _metaContent(document, property: 'product:brand'),
    _metaContent(document, name: 'brand'),
    _attributeContent(document, selector: '[itemprop="brand"]', attribute: 'content'),
    normalizeText(document.querySelector('[itemprop="brand"]')?.text),
    schemaBrand,
    inferBrandFromHost(pageUri.host),
  ]);
}

String? _resolveImageUrl(Document document, Uri pageUri) {
  final schemaImage = _extractSchemaValue<String>(
    document,
    predicate: (node) => _matchesSchemaType(node, 'Product') && _readImage(node['image']) != null,
    value: (node) => _readImage(node['image']),
  );
  final image = firstNonEmpty([
    _metaContent(document, property: 'og:image'),
    _metaContent(document, name: 'twitter:image'),
    _attributeContent(document, selector: '[itemprop="image"]', attribute: 'content'),
    _attributeContent(document, selector: '[itemprop="image"]', attribute: 'src'),
    schemaImage,
    _attributeContent(document, selector: 'link[rel="image_src"]', attribute: 'href'),
    _resolveFirstPageImage(document),
  ]);
  if (image == null) return null;
  return pageUri.resolve(image).toString();
}

String? _resolvePriceLabel(Document document) {
  final metaAmount = firstNonEmpty([
    _metaContent(document, property: 'product:price:amount'),
    _metaContent(document, property: 'og:price:amount'),
    _metaContent(document, name: 'price'),
    _attributeContent(document, selector: '[itemprop="price"]', attribute: 'content'),
    normalizeText(document.querySelector('[itemprop="price"]')?.text),
  ]);
  final metaCurrency = firstNonEmpty([
    _metaContent(document, property: 'product:price:currency'),
    _metaContent(document, property: 'og:price:currency'),
    _attributeContent(document, selector: '[itemprop="priceCurrency"]', attribute: 'content'),
    normalizeText(document.querySelector('[itemprop="priceCurrency"]')?.text),
  ]);
  if (_looksLikePrice(metaAmount)) return _formatPriceLabel(metaAmount!, currency: metaCurrency);

  final schemaPrice = _extractSchemaValue<String>(
    document,
    predicate: (node) => _schemaPriceValue(node) != null,
    value: (node) => _schemaPriceValue(node),
  );
  if (schemaPrice != null) return schemaPrice;

  return _extractSelectorPrice(document) ?? _extractVisiblePrice(document);
}

String? _resolveDescription(Document document) {
  return firstNonEmpty([
    _metaContent(document, property: 'og:description'),
    _metaContent(document, name: 'description'),
    _metaContent(document, name: 'twitter:description'),
  ]);
}

String? _schemaPriceValue(Map<String, dynamic> node) {
  final offerMaps = _collectOfferMaps(node['offers']);
  for (final offer in offerMaps) {
    if (_looksLikeNonPrimaryPrice(_readString(offer['name']))) continue;
    final amount = _readString(offer['price']);
    if (!_looksLikePrice(amount)) continue;
    return _formatPriceLabel(amount!, currency: _readString(offer['priceCurrency']));
  }
  return null;
}

List<Map<String, dynamic>> _collectOfferMaps(Object? offers) {
  if (offers is Map<String, dynamic>) return [offers];
  if (offers is List) return offers.whereType<Map<String, dynamic>>().toList(growable: false);
  return const [];
}

T? _extractSchemaValue<T>(
  Document document, {
  required bool Function(Map<String, dynamic> node) predicate,
  required T? Function(Map<String, dynamic> node) value,
}) {
  for (final script in document.querySelectorAll('script[type="application/ld+json"]')) {
    final raw = script.text.trim();
    if (raw.isEmpty) continue;
    final decoded = _tryDecodeJson(raw);
    if (decoded == null) continue;
    for (final node in _flattenJsonMaps(decoded)) {
      if (!predicate(node)) continue;
      final result = value(node);
      if (result != null) return result;
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
  if (type is String) return type.toLowerCase() == expectedType.toLowerCase();
  if (type is List) {
    return type.any((entry) => entry is String && entry.toLowerCase() == expectedType.toLowerCase());
  }
  return false;
}

String? _readImage(Object? value) {
  if (value is String) return normalizeText(value);
  if (value is List) {
    for (final entry in value) {
      final resolved = _readImage(entry);
      if (resolved != null) return resolved;
    }
  }
  if (value is Map<String, dynamic>) {
    return firstNonEmpty([_readString(value['url']), _readString(value['contentUrl'])]);
  }
  return null;
}

String? _resolveSchemaBrand(Object? value) {
  if (value is String) return normalizeBrand(value);
  if (value is Map<String, dynamic>) {
    return firstNonEmpty([normalizeBrand(_readString(value['name'])), normalizeBrand(_readString(value['brand']))]);
  }
  if (value is List) {
    for (final entry in value) {
      final resolved = _resolveSchemaBrand(entry);
      if (resolved != null) return resolved;
    }
  }
  return null;
}

String? _readString(Object? value) {
  if (value is String) return normalizeText(value);
  return null;
}

String? _resolveFirstPageImage(Document document) {
  for (final image in document.querySelectorAll('img')) {
    final candidate = firstNonEmpty([
      image.attributes['src'],
      image.attributes['data-src'],
      image.attributes['data-old-hires'],
      image.attributes['data-original'],
      image.attributes['data-image'],
    ]);
    if (candidate == null) continue;
    final normalized = candidate.toLowerCase();
    final looksLikeRealImage = normalized.startsWith('http') || normalized.startsWith('/') || normalized.startsWith('//');
    final isLikelyAsset = normalized.endsWith('.jpg') || normalized.endsWith('.jpeg') ||
        normalized.endsWith('.png') || normalized.endsWith('.webp') ||
        normalized.contains('image') || normalized.contains('product') || normalized.contains('main');
    final isIgnored = normalized.contains('logo') || normalized.contains('icon') ||
        normalized.contains('sprite') || normalized.contains('avatar') ||
        normalized.contains('placeholder') || normalized.contains('banner');
    if (looksLikeRealImage && isLikelyAsset && !isIgnored) return candidate;
  }
  return null;
}

String? _metaContent(Document document, {String? property, String? name}) {
  final selector = property != null ? 'meta[property="$property"]' : 'meta[name="$name"]';
  return _attributeContent(document, selector: selector, attribute: 'content');
}

String? _attributeContent(Document document, {required String selector, required String attribute}) {
  return normalizeText(document.querySelector(selector)?.attributes[attribute]);
}

String? _extractVisiblePrice(Document document) {
  final bodyText = normalizeText(document.body?.text);
  if (bodyText == null) return null;

  final symbolMatch = RegExp(
    r'([$€£₪])\s?(\d{1,3}(?:[,\s]\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)',
  ).firstMatch(bodyText);
  if (symbolMatch != null) {
    final symbol = symbolMatch.group(1)!;
    final amount = symbolMatch.group(2)!;
    return _isLikelyCurrentPriceContext(bodyText, symbolMatch.start) ? '$symbol $amount' : null;
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
    '[data-price]', '[data-product-price]', '[itemprop="price"]',
    '.price', '.product-price', '.sale-price', '.current-price',
    '.price-current', '.price__current', '.a-price .a-offscreen',
  ];
  for (final selector in selectors) {
    for (final element in document.querySelectorAll(selector)) {
      final rawAmount = firstNonEmpty([
        element.attributes['content'],
        element.attributes['data-price'],
        element.attributes['aria-label'],
        normalizeText(element.text),
      ]);
      if (!_looksLikePrice(rawAmount)) continue;
      final context = normalizeText(
        '${element.className} ${element.id} ${element.attributes.values.join(' ')} ${element.text}',
      );
      if (_looksLikeNonPrimaryPrice(context)) continue;
      final currency = firstNonEmpty([
        element.attributes['data-currency'],
        element.attributes['currency'],
        _attributeContent(document, selector: '[itemprop="priceCurrency"]', attribute: 'content'),
      ]);
      return _formatPriceLabel(rawAmount!, currency: currency ?? _extractCurrencySymbol(rawAmount));
    }
  }
  return null;
}

bool _looksLikeNonPrimaryPrice(String? context) {
  final normalized = context?.toLowerCase() ?? '';
  if (normalized.isEmpty) return false;
  return normalized.contains('compare') || normalized.contains('was ') ||
      normalized.contains('list price') || normalized.contains('save ') ||
      normalized.contains('installment') || normalized.contains('finance') ||
      normalized.contains('shipping');
}

bool _isLikelyCurrentPriceContext(String bodyText, int matchStart) {
  final start = matchStart < 40 ? 0 : matchStart - 40;
  final end = matchStart + 60 > bodyText.length ? bodyText.length : matchStart + 60;
  return !_looksLikeNonPrimaryPrice(bodyText.substring(start, end).toLowerCase());
}

String? _extractCurrencySymbol(String value) {
  final match = RegExp(r'([$€£₪])').firstMatch(value);
  if (match != null) return match.group(1);
  return RegExp(r'\b(USD|EUR|GBP|ILS)\b', caseSensitive: false).firstMatch(value)?.group(1)?.toUpperCase();
}

String? _formatPriceLabel(String amount, {String? currency}) {
  final normalizedAmount = amount.replaceAll(RegExp(r'[^0-9.,]'), '').trim();
  if (normalizedAmount.isEmpty) return null;
  final normalizedCurrency = normalizeText(currency);
  if (normalizedCurrency == null) return normalizedAmount;
  return '$normalizedCurrency $normalizedAmount';
}

bool _looksLikePrice(String? value) {
  if (value == null) return false;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  return RegExp(r'^\$?\d[\d,]*(?:\.\d{1,2})?$').hasMatch(trimmed) ||
      RegExp(r'^[A-Z]{3}\s*\d[\d,]*(?:\.\d{1,2})?$').hasMatch(trimmed) ||
      RegExp(r'^\d[\d,]*(?:\.\d{1,2})?$').hasMatch(trimmed);
}

String? normalizeBrand(String? brand) {
  final normalized = normalizeText(brand);
  if (normalized == null) return null;
  if (normalized.toUpperCase() == normalized) return normalized;
  final lower = normalized.toLowerCase();
  if (lower == 'hm' || lower == 'h&m') return 'H&M';
  return normalized.split(' ').where((p) => p.isNotEmpty).map((p) => '${p[0].toUpperCase()}${p.substring(1)}').join(' ');
}

String? inferBrandFromHost(String host) {
  final normalizedHost = host.replaceFirst(RegExp(r'^www\.'), '').trim();
  if (normalizedHost.isEmpty) return null;
  if (normalizedHost == 'localhost' || normalizedHost.startsWith('127.') ||
      RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(normalizedHost)) {
    return null;
  }
  final primary = normalizedHost.split('.').first;
  if (primary.isEmpty || primary.length < 2) return null;
  return normalizeBrand(primary);
}

String? normalizeText(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.replaceAll(RegExp(r'\s+'), ' ');
}

String? firstNonEmpty(List<String?> values) {
  for (final value in values) {
    final normalized = normalizeText(value);
    if (normalized != null) return normalized;
  }
  return null;
}
