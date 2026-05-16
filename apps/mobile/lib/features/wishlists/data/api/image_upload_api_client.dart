import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;

class ImageUploadApiClient {
  ImageUploadApiClient({
    required Uri baseUri,
    required String authToken,
    http.Client? httpClient,
  }) : _baseUri = _normalizeBaseUri(baseUri),
       _authToken = authToken,
       _httpClient = httpClient ?? http.Client();

  final Uri _baseUri;
  final String _authToken;
  final http.Client _httpClient;

  Future<UploadedImageDto> uploadImage({
    required List<int> bytes,
    required String fileName,
    String? contentType,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _baseUri.resolve('/uploads/images'),
    );
    request.headers['Authorization'] = 'Bearer $_authToken';
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: _parseMediaType(contentType),
      ),
    );

    final streamedResponse = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    final payload = response.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 201) {
      throw _ApiError.fromJson(
        response.statusCode,
        payload,
        fallbackMessage: 'Could not upload this image.',
      );
    }

    return UploadedImageDto.fromJson(payload);
  }
}

class UploadedImageDto {
  const UploadedImageDto({required this.key, required this.url});

  factory UploadedImageDto.fromJson(Map<String, dynamic> json) {
    return UploadedImageDto(
      key: json['key'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }

  final String key;
  final String url;
}

class _ApiError implements Exception {
  const _ApiError(this.message);

  factory _ApiError.fromJson(
    int statusCode,
    Map<String, dynamic> json, {
    required String fallbackMessage,
  }) {
    final error = json['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'] as String?;
      if (message != null && message.trim().isNotEmpty) {
        return _ApiError(message);
      }
    }

    return _ApiError('$fallbackMessage (HTTP $statusCode)');
  }

  final String message;

  @override
  String toString() => message;
}

Uri _normalizeBaseUri(Uri uri) {
  final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
  return uri.replace(path: path);
}

http_parser.MediaType? _parseMediaType(String? contentType) {
  final value = contentType?.trim() ?? '';
  if (value.isEmpty || !value.contains('/')) {
    return null;
  }

  final parts = value.split('/');
  if (parts.length != 2) {
    return null;
  }

  return http_parser.MediaType(parts[0], parts[1]);
}
