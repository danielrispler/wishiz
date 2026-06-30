import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/auth/data/api/auth_api_client.dart';

void main() {
  late HttpServer server;
  late AuthApiClient client;
  late List<_CapturedRequest> received;

  setUp(() async {
    received = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      received.add(
        _CapturedRequest(
          method: request.method,
          path: request.uri.path,
          body: body,
          contentLength: request.contentLength,
          chunked: request.headers.chunkedTransferEncoding,
        ),
      );
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    client = AuthApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('deleteAccount sends the password in the DELETE request body', () async {
    await client.deleteAccount(authToken: 'token', password: 'secret');

    expect(received, hasLength(1));
    final req = received.single;
    expect(req.method, 'DELETE');
    expect(req.path, '/auth/me');
    expect(jsonDecode(req.body), {'password': 'secret'});

    // The bug: dart:io sends the body chunked (no Content-Length) when
    // contentLength is unset, and proxies in front of the real API strip the
    // chunked DELETE body -> server sees an empty body. Require an explicit
    // Content-Length so the body survives the wire.
    expect(req.chunked, isFalse, reason: 'DELETE body must not be chunked');
    expect(
      req.contentLength,
      utf8.encode(jsonEncode({'password': 'secret'})).length,
    );
  });

  test('logIn sends the credentials in the POST request body', () async {
    // POST already worked; guards against the Content-Length fix regressing it.
    try {
      await client.logIn(email: 'a@b.co', password: 'pw');
    } on AuthApiException {
      // 204 isn't a valid login response; we only care about the sent body.
    }

    expect(received, hasLength(1));
    expect(received.single.method, 'POST');
    expect(jsonDecode(received.single.body), {'email': 'a@b.co', 'password': 'pw'});
  });
}

class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.path,
    required this.body,
    required this.contentLength,
    required this.chunked,
  });

  final String method;
  final String path;
  final String body;
  final int contentLength;
  final bool chunked;
}
