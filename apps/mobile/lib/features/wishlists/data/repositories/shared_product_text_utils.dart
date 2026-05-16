import 'shared_product_page_parser.dart';

final RegExp _titleSeparatorPattern = RegExp(r'\s+\|\s+|\s+-\s+|\s+:\s+');

String? extractProductUrl(String sharedText) {
  final urlPattern = RegExp(r'https?:\/\/[^\s<>"\)\]]+', caseSensitive: false);
  final match = urlPattern.firstMatch(sharedText);
  if (match == null) return null;
  final candidate = match.group(0);
  final uri = candidate == null ? null : Uri.tryParse(candidate);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
  return uri.toString();
}

List<String> extractSharedLines(String sharedText, String productUrl) {
  return sharedText
      .split(RegExp(r'\r?\n'))
      .map(normalizeText)
      .whereType<String>()
      .where((line) => line != productUrl)
      .where((line) => !_containsUrl(line))
      .toList(growable: false);
}

String? extractSharedNotes(List<String> lines, {String? resolvedTitle}) {
  final remainingLines = lines.where((line) => resolvedTitle == null || line != resolvedTitle).toList(growable: false);
  if (remainingLines.isEmpty) return null;
  return remainingLines.join('\n');
}

String? inferTitleFromProductUri(String productUrl) {
  final uri = Uri.tryParse(productUrl);
  if (uri == null) return null;
  for (final segment in uri.pathSegments.reversed) {
    final decoded = _decodeUriComponentSafely(segment)
        .replaceAll(RegExp(r'[-_+]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final cleaned = decoded.replaceAll(RegExp(r'\b\d+\b'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length > 2) return _toTitleCase(cleaned);
  }
  return null;
}

String? inferImportedFromNote(String productUrl) {
  final uri = Uri.tryParse(productUrl);
  if (uri == null) return null;
  final host = uri.host.replaceFirst(RegExp(r'^www\.'), '').trim();
  if (host.isEmpty) return null;
  return 'Imported from $host.';
}

String? compactTitle(String? value) {
  final normalized = normalizeText(value);
  if (normalized == null) return null;
  final cleaned = normalized
      .split(_titleSeparatorPattern)
      .first
      .replaceAll(RegExp(r'[^\w\s&]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return null;
  final words = cleaned.split(' ').where((w) => w.isNotEmpty).where((w) => !_isStopWord(w)).take(3).toList(growable: false);
  final compact = words.isEmpty
      ? cleaned.split(' ').where((w) => w.isNotEmpty).take(3).join(' ')
      : words.join(' ');
  return _toTitleCase(compact);
}

String? buildProductTitle({
  required String productUrl,
  required List<String?> rawCandidates,
  String? brandCandidate,
}) {
  final brand = normalizeBrand(brandCandidate) ??
      inferBrandFromTitle(rawCandidates) ??
      inferBrandFromHost(Uri.tryParse(productUrl)?.host ?? '');

  for (final candidate in rawCandidates) {
    final type = _extractProductType(candidate, brand: brand);
    if (type == null) continue;
    if (brand != null) return '${_toTitleCase(type)}, $brand';
    return _toTitleCase(type);
  }
  return null;
}

String? inferBrandFromTitle(List<String?> rawCandidates) {
  for (final candidate in rawCandidates) {
    final normalized = normalizeText(candidate);
    if (normalized == null) continue;
    final cleaned = normalized
        .split(_titleSeparatorPattern)
        .first
        .replaceAll(RegExp(r'[^\w\s&]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) continue;
    final tokens = cleaned.split(' ').where((w) => w.isNotEmpty).toList(growable: false);
    if (tokens.length < 3) continue;
    final first = tokens.first;
    final normalizedBrand = normalizeBrand(first);
    if (normalizedBrand == null) continue;
    if (_isStopWord(first) || _looksLikeProductNoun(first) || _looksLikeProductDescriptor(first)) continue;
    return normalizedBrand;
  }
  return null;
}

String? _extractProductType(String? rawTitle, {String? brand}) {
  final normalized = normalizeText(rawTitle);
  if (normalized == null) return null;
  var cleaned = normalized
      .split(_titleSeparatorPattern)
      .first
      .replaceAll(RegExp(r'[^\w\s,&/]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (brand != null && brand.isNotEmpty) {
    cleaned = cleaned.replaceAll(RegExp(RegExp.escape(brand), caseSensitive: false), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  final tokens = cleaned.split(' ').where((w) => w.isNotEmpty).where((w) => !_isStopWord(w)).toList(growable: false);
  if (tokens.isEmpty) return null;

  final productKeywords = <String>[];
  var nounIndex = -1;
  for (final token in tokens) {
    productKeywords.add(token);
    if (_looksLikeProductNoun(token) && productKeywords.length >= 2) {
      nounIndex = productKeywords.length - 1;
      break;
    }
    if (productKeywords.length == 3) break;
  }
  if (nounIndex != -1 && productKeywords.length < 3 && tokens.length > nounIndex + 1) {
    if (_looksLikeProductDescriptor(tokens[nounIndex + 1])) productKeywords.add(tokens[nounIndex + 1]);
  }
  return productKeywords.join(' ');
}

bool _looksLikeProductNoun(String word) {
  const nouns = {
    'shirt', 'tshirt', 't-shirt', 'tee', 'socks', 'sock', 'hoodie', 'jacket',
    'sneakers', 'shoes', 'shoe', 'pants', 'jeans', 'dress', 'hat', 'cap',
    'bag', 'wallet', 'blanket', 'lamp', 'kettle', 'chair', 'mug', 'bowl',
  };
  return nouns.contains(word.toLowerCase());
}

bool _looksLikeProductDescriptor(String word) {
  const descriptors = {
    'matte', 'white', 'black', 'blue', 'red', 'green', 'grey', 'gray',
    'cotton', 'wool', 'leather', 'mini', 'max', 'pro', 'classic', 'crew',
    'slim', 'oversized',
  };
  return descriptors.contains(word.toLowerCase());
}

bool _isStopWord(String word) {
  const stopWords = {'the', 'and', 'with', 'for', 'from', 'new', 'best', 'official', 'shop', 'buy', 'sale'};
  return stopWords.contains(word.toLowerCase());
}

String _toTitleCase(String value) {
  return value.split(' ').map((part) {
    if (part.isEmpty) return part;
    return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
  }).join(' ');
}

String _decodeUriComponentSafely(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}

bool _containsUrl(String value) => RegExp(r'https?:\/\/', caseSensitive: false).hasMatch(value);

