import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/data/api/wishlist_api_client.dart';
import 'package:wishiz/features/wishlists/data/repositories/http_wishlist_repository.dart';

void main() {
  group('HttpWishlistRepository', () {
    test('loads wishlists from the backend during creation', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/wishlists');
        await _writeJsonResponse(
          request.response,
          HttpStatus.ok,
          [
            _wishlistJson(
              id: 'travel',
              title: 'Travel',
              description: 'Carry-on ideas',
              year: 2027,
            ),
          ],
        );
      });

      final repository = await HttpWishlistRepository.create(
        apiClient: WishlistApiClient(baseUri: _serverUri(server)),
      );

      expect(repository.getWishlists(), hasLength(1));
      expect(repository.findById('travel')?.title, 'Travel');
      expect(repository.findById('travel')?.description, 'Carry-on ideas');
    });

    test('creates a wishlist and updates the local cache', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        if (request.method == 'GET' && request.uri.path == '/wishlists') {
          await _writeJsonResponse(request.response, HttpStatus.ok, const []);
          return;
        }

        if (request.method == 'POST' && request.uri.path == '/wishlists') {
          final body = await utf8.decoder.bind(request).join();
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          expect(decoded['title'], 'Hosting');
          expect(decoded['year'], 2026);

          await _writeJsonResponse(
            request.response,
            HttpStatus.created,
            _wishlistJson(
              id: 'hosting',
              title: decoded['title'] as String,
              description: decoded['description'] as String,
              year: decoded['year'] as int,
              isShared: decoded['isShared'] as bool? ?? false,
            ),
          );
          return;
        }

        fail('Unexpected request: ${request.method} ${request.uri.path}');
      });

      final repository = await HttpWishlistRepository.create(
        apiClient: WishlistApiClient(baseUri: _serverUri(server)),
      );

      final created = await repository.createWishlist(
        title: 'Hosting',
        description: 'Candles and plates',
        year: 2026,
      );

      expect(created.id, 'hosting');
      expect(repository.findById('hosting'), isNotNull);
      expect(repository.getWishlists().first.title, 'Hosting');
    });

    test('refreshes wishlist details after adding an item', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      var detailRequestCount = 0;
      server.listen((request) async {
        if (request.method == 'GET' && request.uri.path == '/wishlists') {
          await _writeJsonResponse(
            request.response,
            HttpStatus.ok,
            [
              _wishlistJson(
                id: 'home',
                title: 'Home',
                description: 'Decor',
                year: 2026,
              ),
            ],
          );
          return;
        }

        if (request.method == 'POST' &&
            request.uri.path == '/wishlists/home/items') {
          await _writeJsonResponse(
            request.response,
            HttpStatus.created,
            _itemJson(
              id: 'lamp',
              title: 'Marble lamp',
              rank: 1,
            ),
          );
          return;
        }

        if (request.method == 'GET' && request.uri.path == '/wishlists/home') {
          detailRequestCount += 1;
          await _writeJsonResponse(
            request.response,
            HttpStatus.ok,
            _wishlistJson(
              id: 'home',
              title: 'Home',
              description: 'Decor',
              year: 2026,
              items: [
                _itemJson(
                  id: 'lamp',
                  title: 'Marble lamp',
                  rank: 1,
                ),
              ],
            ),
          );
          return;
        }

        fail('Unexpected request: ${request.method} ${request.uri.path}');
      });

      final repository = await HttpWishlistRepository.create(
        apiClient: WishlistApiClient(baseUri: _serverUri(server)),
      );

      final createdItem = await repository.addWishlistItem(
        wishlistId: 'home',
        title: 'Marble lamp',
      );

      expect(detailRequestCount, 1);
      expect(createdItem.id, 'lamp');
      expect(repository.findById('home')?.items, hasLength(1));
      expect(repository.findById('home')?.items.first.title, 'Marble lamp');
    });
  });
}

Uri _serverUri(HttpServer server) {
  return Uri.parse('http://${server.address.host}:${server.port}');
}

Map<String, dynamic> _wishlistJson({
  required String id,
  required String title,
  required String description,
  required int year,
  bool isArchived = false,
  bool isShared = false,
  List<Map<String, dynamic>> items = const [],
}) {
  return {
    'id': id,
    'title': title,
    'description': description,
    'year': year,
    'coverImageUrl': null,
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-02T00:00:00Z',
    'isArchived': isArchived,
    'isShared': isShared,
    'sharedUsers': const [],
    'items': items,
  };
}

Map<String, dynamic> _itemJson({
  required String id,
  required String title,
  required int rank,
}) {
  return {
    'id': id,
    'title': title,
    'rank': rank,
    'notes': null,
    'priceLabel': null,
    'priority': 'Medium',
    'status': 'Saved',
    'imageUrl': null,
    'productUrl': null,
    'purchasedAt': null,
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-02T00:00:00Z',
  };
}

Future<void> _writeJsonResponse(
  HttpResponse response,
  int statusCode,
  Object payload,
) async {
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(payload));
  await response.close();
}
